-- 0044 · Fantasy: precios y puntos ajustados a las valoraciones actuales + datos para las tarjetas de jugador
--  · puntos_por_nota: continuo (antes en escalones). Con estrellas (nota = ★×2): 5★ = 4 pts, 4★ = 2,5, 3★ = 1,5, ≤2★ = 0.
--  · recalcular_precios: rendimiento = 65 % percentil de puntos + 35 % percentil de nota de los compañeros,
--    media ponderada de los 8 últimos partidos (0,75^k) y contracción hacia el valor inicial 3/(3+n).
--    El resto igual: precio = curva(valoración) × demanda (0,85–1,25), como mucho ±max_variacion por jornada.
--  · resumen_jugadores_fantasy(liga): media, últimas 5 puntuaciones, goles, asistencias, MVP… para las tarjetas.

create or replace function puntos_por_nota(p_nota numeric, p_tope numeric) returns numeric
language sql immutable set search_path = public as $$
  select case when p_nota is null then 0
              else round(least(p_tope, greatest(0, p_tope * (p_nota - 4) / 6.0)) * 2) / 2 end
$$;

create or replace function recalcular_precios(p_liga uuid, p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare l ligas; v_dmedia numeric; r record; v_rend numeric; v_n int;
        v_w numeric; v_r numeric; v_d numeric; v_f numeric; v_nuevo numeric; v_lo numeric; v_hi numeric;
        k int := 0;
begin
  if auth.uid() is not null then perform exigir_admin(p_liga); end if;
  if exists (select 1 from historial_precios where liga_id = p_liga and partido_id = p_partido) then
    return 0;
  end if;
  if not exists (select 1 from mercado_jugador where liga_id = p_liga) then return 0; end if;
  perform congelar_vencidas_liga(p_liga);   -- congela con el estado no_habitual previo al cambio
  select * into l from ligas where id = p_liga;

  -- Demanda: fichas con dueño / C
  select avg(coalesce(h.n, 0)::numeric / l.copias_por_jugador) into v_dmedia
    from mercado_jugador mj
    left join (select jugador_id, count(*) n from fichas
                where liga_id = p_liga and propietario_id is not null group by jugador_id) h
      on h.jugador_id = mj.miembro_id
   where mj.liga_id = p_liga;

  -- Rendimiento: percentil (0–100) de la media de los últimos 5 partidos jugados
  -- Rendimiento reciente (últimos 8 partidos cerrados, los más recientes pesan más: 1, 0,75, 0,56…)
  --   pts  = media ponderada de los puntos Fantasy (goles, asistencias, resultado, notas, MVP…)
  --   nota = media ponderada de la nota de los compañeros (estrellas ×2 o valoración avanzada), si la hay
  -- Cada una se convierte en percentil dentro de la liga (0–100): así no importa la escala de puntos
  -- (los goles valen mucho) y un portero o un defensa con buenas notas también sube.
  create temp table if not exists tmp_rend (miembro_id uuid primary key, partidos int, pct numeric) on commit drop;
  delete from tmp_rend where true;
  insert into tmp_rend
  select miembro_id, n,
         case when pct_nota is null then pct_pts else 0.65 * pct_pts + 0.35 * pct_nota end
    from (select miembro_id, n,
                 case when count(*) over () = 1 then 50 else 100 * percent_rank() over (order by e_pts) end as pct_pts,
                 case when e_nota is null then null
                      when count(e_nota) over () <= 1 then 50
                      else 100 * percent_rank() over (partition by (e_nota is null) order by e_nota) end as pct_nota
            from (select h.miembro_id, count(*) n,
                         sum(h.total * h.w) / sum(h.w) as e_pts,
                         sum(h.nota * h.w) filter (where h.nota is not null)
                           / nullif(sum(h.w) filter (where h.nota is not null), 0) as e_nota
                    from (select pf.miembro_id, pf.total, pf.nota_media as nota,
                                 power(0.75, row_number() over (partition by pf.miembro_id order by p.fecha_hora desc) - 1) as w,
                                 row_number() over (partition by pf.miembro_id order by p.fecha_hora desc) as rn
                            from puntos_fantasy pf join partidos p on p.id = pf.partido_id
                           where p.liga_id = p_liga and p.estado = 'cerrado') h
                   where h.rn <= 8
                   group by h.miembro_id) t) u;

  for r in select mj.*, coalesce(vj.general, (select h.rating from historial_precios h where h.liga_id = mj.liga_id and h.miembro_id = mj.miembro_id and h.partido_id is null order by h.creado_en desc, h.id desc limit 1), 50) as g, (vj.general is not null) as con_encuesta,
                  (select count(*) from fichas f where f.liga_id = p_liga and f.jugador_id = mj.miembro_id
                                                   and f.propietario_id is not null) as duenos
             from mercado_jugador mj
             left join valoracion_jugador vj on vj.liga_id = mj.liga_id and vj.miembro_id = mj.miembro_id
            where mj.liga_id = p_liga for update of mj loop
    select partidos, pct into v_n, v_rend from tmp_rend where miembro_id = r.miembro_id;
    v_n := coalesce(v_n, 0);
    if not r.con_encuesta then
      -- Sin encuesta: todos parten de su valor inicial (45–55) y cada partido cuenta desde el primero
      v_w := 2.0 / (2 + v_n);
    elsif v_n < l.partidos_min_rendimiento then
      v_w := 1;                                    -- con pocos partidos solo cuenta la encuesta
    else
      v_w := case when l.k_encuesta + v_n = 0 then 1 else l.k_encuesta / (l.k_encuesta + v_n) end;
    end if;
    v_r := v_w * r.g + (1 - v_w) * coalesce(v_rend, r.g);
    v_d := r.duenos::numeric / l.copias_por_jugador;
    v_f := greatest(0.85, least(1.25, 1 + 0.4 * (coalesce(v_d, 0) - coalesce(v_dmedia, 0))));
    v_lo := r.precio * (1 - l.max_variacion);
    v_hi := r.precio * (1 + l.max_variacion);
    v_nuevo := greatest(v_lo, least(v_hi, precio_base(p_liga, v_r) * v_f));
    v_nuevo := greatest(l.precio_min, least(l.precio_max, v_nuevo));
    v_nuevo := redondear_005(v_nuevo);
    if v_nuevo > v_hi then v_nuevo := floor(v_hi * 20) / 20; end if;
    if v_nuevo < v_lo then v_nuevo := ceil(v_lo * 20) / 20; end if;
    v_nuevo := greatest(v_nuevo, l.precio_min);

    update mercado_jugador
       set precio = v_nuevo, rating = round(v_r, 2), no_habitual = es_no_habitual(r.miembro_id),
           actualizado_en = now()
     where liga_id = p_liga and miembro_id = r.miembro_id;
    insert into historial_precios (liga_id, miembro_id, partido_id, precio, rating, demanda)
    values (p_liga, r.miembro_id, p_partido, v_nuevo, round(v_r, 2), round(coalesce(v_d, 0), 4));
    k := k + 1;
  end loop;
  return k;
end $$;

create or replace function resumen_jugadores_fantasy(p_liga uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not es_miembro(p_liga) then raise exception 'No eres de esta liga'; end if;
  return coalesce((
    select jsonb_object_agg(x.miembro_id, x.datos) from (
      select pf.miembro_id,
             jsonb_build_object(
               'partidos', count(*),
               'media', round(avg(pf.total), 1),
               'maximo', max(pf.total),
               'goles', coalesce(sum((pf.desglose->>'goles')::numeric / nullif(regla(p_liga, 'gol'), 0)), 0)::int,
               'asistencias', coalesce(sum((pf.desglose->>'asistencias')::numeric / nullif(regla(p_liga, 'asistencia'), 0)), 0)::int,
               'mvps', count(*) filter (where pf.es_mvp),
               'nota', round(avg(pf.nota_media) / 2, 1),
               'ultimos', (select jsonb_agg(jsonb_build_object('fecha', u.fecha_hora, 'total', u.total, 'mvp', u.es_mvp,
                                                               'nota', round(u.nota_media / 2, 1)) order by u.fecha_hora desc)
                             from (select p2.fecha_hora, pf2.total, pf2.es_mvp, pf2.nota_media
                                     from puntos_fantasy pf2 join partidos p2 on p2.id = pf2.partido_id
                                    where pf2.miembro_id = pf.miembro_id and p2.liga_id = p_liga and p2.estado = 'cerrado'
                                    order by p2.fecha_hora desc limit 5) u)) as datos
        from puntos_fantasy pf join partidos p on p.id = pf.partido_id
       where p.liga_id = p_liga and p.estado = 'cerrado'
       group by pf.miembro_id) x), '{}');
end $$;
revoke execute on function resumen_jugadores_fantasy(uuid) from public, anon;
grant execute on function resumen_jugadores_fantasy(uuid) to authenticated;
