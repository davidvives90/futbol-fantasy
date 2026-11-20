-- 0030 · Estadísticas ampliadas (jugador y liga). Solo partidos cerrados de la liga; lectura para miembros.
create or replace function estadisticas_jugador(p_miembro uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_liga uuid; v_res jsonb; v_forma text; v_racha_inv int := 0; v_max_inv int := 0; v_racha_v int := 0;
        v_max_v int := 0; r record; v_jugados int; v_total int;
begin
  select liga_id into v_liga from miembros where id = p_miembro;
  if v_liga is null or not es_miembro(v_liga) then raise exception 'No perteneces a esta liga'; end if;

  -- forma (últimos 5, el más reciente primero) y rachas
  select string_agg(case when victorias > 0 and derrotas = 0 then 'V' when derrotas > 0 and victorias = 0 then 'D' else 'E' end,
                    '' order by fecha_hora desc)
    into v_forma
    from (select pf.victorias, pf.derrotas, p.fecha_hora from puntos_fantasy pf join partidos p on p.id = pf.partido_id
           where pf.miembro_id = p_miembro and p.estado = 'cerrado' order by p.fecha_hora desc limit 5) t;
  for r in select pf.victorias, pf.derrotas from puntos_fantasy pf join partidos p on p.id = pf.partido_id
            where pf.miembro_id = p_miembro and p.estado = 'cerrado' order by p.fecha_hora loop
    if r.derrotas = 0 then v_racha_inv := v_racha_inv + 1; else v_racha_inv := 0; end if;
    if r.victorias > 0 and r.derrotas = 0 then v_racha_v := v_racha_v + 1; else v_racha_v := 0; end if;
    v_max_inv := greatest(v_max_inv, v_racha_inv); v_max_v := greatest(v_max_v, v_racha_v);
  end loop;

  select count(*) into v_jugados from puntos_fantasy pf join partidos p on p.id = pf.partido_id
   where pf.miembro_id = p_miembro and p.estado = 'cerrado';
  select count(*) into v_total from partidos where liga_id = v_liga and estado = 'cerrado'
     and fecha_hora >= (select coalesce(unido_en, '-infinity') from miembros where id = p_miembro);

  with mis as (
    select c.partido_id, c.equipo, pf.victorias, pf.derrotas from convocatorias c
      join puntos_fantasy pf on pf.partido_id = c.partido_id and pf.miembro_id = c.miembro_id
      join partidos p on p.id = c.partido_id
     where c.miembro_id = p_miembro and p.estado = 'cerrado' and c.equipo is not null),
  companeros as (
    select c.miembro_id, count(*) n, sum(m.victorias) v,
           round(100.0 * sum(m.victorias) / nullif(count(*), 0)) pct
      from mis m join convocatorias c on c.partido_id = m.partido_id and c.equipo = m.equipo and c.miembro_id <> p_miembro
     group by c.miembro_id),
  rivales as (
    select c.miembro_id, count(*) n, sum(m.derrotas) d,
           round(100.0 * sum(m.derrotas) / nullif(count(*), 0)) pct
      from mis m join convocatorias c on c.partido_id = m.partido_id and c.equipo is not null
                                      and c.equipo <> m.equipo and c.estado = 'confirmado'
     group by c.miembro_id)
  select jsonb_build_object(
    'forma', coalesce(v_forma, ''),
    'racha_invicto_max', v_max_inv, 'racha_victorias_max', v_max_v,
    'racha_invicto_actual', v_racha_inv,
    'asistencia_pct', case when v_total > 0 then round(100.0 * v_jugados / v_total) end,
    'porterias_cero', (select coalesce(sum(aj.porterias_cero), 0) from acta_jugador aj join partidos p on p.id = aj.partido_id
                        where aj.miembro_id = p_miembro and p.estado = 'cerrado'),
    'goles_encajados_partido', (select round(avg(aj.goles_encajados), 2) from acta_jugador aj join partidos p on p.id = aj.partido_id
                                 where aj.miembro_id = p_miembro and p.estado = 'cerrado'),
    'votos_mvp', (select coalesce(sum((pf.desglose ->> 'votos_mvp')::int), 0) from puntos_fantasy pf where pf.miembro_id = p_miembro),
    'destacados', (select coalesce(jsonb_object_agg(aspecto, veces), '{}') from v_destacados where miembro_id = p_miembro),
    'mejor_companero', (select jsonb_build_object('miembro_id', miembro_id, 'partidos', n, 'pct_victorias', pct)
                          from companeros where n >= 2 order by pct desc, n desc limit 1),
    'mas_juega_con', (select jsonb_build_object('miembro_id', miembro_id, 'partidos', n, 'pct_victorias', pct)
                        from companeros order by n desc, pct desc limit 1),
    'bestia_negra', (select jsonb_build_object('miembro_id', miembro_id, 'partidos', n, 'pct_derrotas', pct)
                       from rivales where n >= 2 and d > 0 order by pct desc, n desc limit 1))
    into v_res;
  return v_res;
end $$;

create or replace function estadisticas_liga(p_liga uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not es_miembro(p_liga) then raise exception 'No perteneces a esta liga'; end if;
  return (
    with cerr as (select p.* from partidos p where p.liga_id = p_liga and p.estado = 'cerrado'),
    enc as (select e.*, cerr.fecha_hora from encuentros e join cerr on cerr.id = e.partido_id),
    parejas as (
      select least(a.miembro_id, b.miembro_id) x, greatest(a.miembro_id, b.miembro_id) y, count(*) n,
             round(100.0 * sum(pa.victorias) / nullif(count(*), 0)) pct
        from convocatorias a join convocatorias b on b.partido_id = a.partido_id and b.equipo = a.equipo
                                                 and a.miembro_id < b.miembro_id
        join puntos_fantasy pa on pa.partido_id = a.partido_id and pa.miembro_id = a.miembro_id
        join cerr on cerr.id = a.partido_id
       where a.equipo is not null
       group by 1, 2)
    select jsonb_build_object(
      'partidos', (select count(*) from cerr),
      'goles', (select coalesce(sum(goles_local + goles_visitante), 0) from enc),
      'goles_partido', (select round(avg(t), 1) from (select sum(goles_local + goles_visitante) t from enc group by partido_id) s),
      'mayor_goleada', (select jsonb_build_object('partido_id', partido_id, 'fecha', fecha_hora, 'local', goles_local,
                                                  'visitante', goles_visitante)
                          from enc order by abs(goles_local - goles_visitante) desc, goles_local + goles_visitante desc limit 1),
      'mas_goles', (select jsonb_build_object('partido_id', partido_id, 'fecha', fecha_hora, 'local', goles_local,
                                              'visitante', goles_visitante)
                      from enc order by goles_local + goles_visitante desc limit 1),
      'empates_pct', (select round(100.0 * count(*) filter (where goles_local = goles_visitante) / nullif(count(*), 0)) from enc),
      'mejores_parejas', coalesce((select jsonb_agg(jsonb_build_object('a', x, 'b', y, 'partidos', n, 'pct_victorias', pct)
                                                     order by pct desc, n desc)
                                     from (select * from parejas where n >= 2 order by pct desc, n desc limit 5) q), '[]'),
      'mas_fieles', coalesce((select jsonb_agg(jsonb_build_object('miembro_id', miembro_id, 'partidos', n) order by n desc)
                                from (select pf.miembro_id, count(*) n from puntos_fantasy pf join cerr on cerr.id = pf.partido_id
                                       group by pf.miembro_id order by n desc limit 5) q), '[]'))
  );
end $$;

revoke execute on function estadisticas_jugador(uuid), estadisticas_liga(uuid) from public, anon;
grant execute on function estadisticas_jugador(uuid), estadisticas_liga(uuid) to authenticated;
