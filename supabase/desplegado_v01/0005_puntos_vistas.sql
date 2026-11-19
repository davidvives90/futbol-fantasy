-- 0005 · Cálculo de puntos Fantasy y vistas de estadísticas
--
-- Puntuación (claves de reglas_puntuacion, valores por defecto en 0007):
--   jugado · victoria / empate (por encuentro) · gol_<posicion> (o gol si la liga no puntúa por posición)
--   asistencia · porteria_cero_<posicion> (por encuentro sin encajar) · goles_encajados_3 (portero, por cada 3)
--   parada_clave_2 (por cada 2) · penalti_parado · penalti_fallado · autogol
--   valoracion: tramos de la nota de compañeros, tope valoracion_max · mvp
--
-- Nota de compañeros: cada votante → media de sus aspectos; con ≥ 5 votantes media recortada
-- (sin el votante más alto ni el más bajo); con < 3 votantes no hay nota (0 puntos, sin MVP).

create or replace function puntos_por_nota(p_nota numeric, p_tope numeric) returns numeric
language sql immutable as $$
  select case when p_nota is null then 0
              else least(p_tope, case when p_nota < 5 then 0
                                      when p_nota < 6 then 1
                                      when p_nota < 7 then 2
                                      when p_nota < 8 then 3
                                      else 4 end)
         end
$$;

-- Nota general de un jugador en un partido + nº de votantes + media por aspecto
create or replace function nota_partido(p_partido uuid, p_miembro uuid,
                                        out nota numeric, out votantes int, out por_aspecto jsonb)
language plpgsql stable security definer set search_path = public as $$
declare v_suma numeric; v_max numeric; v_min numeric;
begin
  select count(*), sum(m), max(m), min(m) into votantes, v_suma, v_max, v_min
    from (select avg(v.nota) m from valoraciones v
           where v.partido_id = p_partido and v.votado_id = p_miembro group by v.votante_id) t;

  if votantes >= 5 then
    nota := round((v_suma - v_max - v_min) / (votantes - 2), 2);
  elsif votantes >= 3 then
    nota := round(v_suma / votantes, 2);
  else
    nota := null;
  end if;

  select coalesce(jsonb_object_agg(aspecto, round(m, 2)), '{}') into por_aspecto
    from (select v.aspecto, avg(v.nota) m from valoraciones v
           where v.partido_id = p_partido and v.votado_id = p_miembro group by v.aspecto) t;
  if votantes < 3 then por_aspecto := '{}'; end if;   -- con pocos votos no se publica nada
end $$;

create or replace function calcular_puntos(p_partido uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; a record; v_pos posicion_campo; v_gol text;
        v_v int; v_e int; v_d int; v_nota record; d jsonb; v_total numeric;
        v_max_nota numeric; v_max_ga int;
begin
  select * into p from partidos where id = p_partido for update;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado not in ('post_partido', 'en_revision') then
    raise exception 'El partido no está pendiente de puntuar (estado: %)', p.estado;
  end if;
  if exists (select 1 from disputas where partido_id = p_partido and not resuelta) then
    raise exception 'Quedan datos en disputa por resolver';
  end if;
  if exists (select 1 from encuentros where partido_id = p_partido and goles_local is null) then
    raise exception 'El acta no está consolidada';
  end if;
  select * into l from ligas where id = p.liga_id;

  delete from puntos_fantasy where partido_id = p_partido;

  for a in select aj.*, c.equipo from acta_jugador aj
             join convocatorias c on c.partido_id = aj.partido_id and c.miembro_id = aj.miembro_id
            where aj.partido_id = p_partido loop
    v_pos := posicion_de(a.miembro_id);
    v_gol := case when l.puntuar_por_posicion and v_pos is not null then 'gol_' || v_pos else 'gol' end;

    select count(*) filter (where gf > gc), count(*) filter (where gf = gc), count(*) filter (where gf < gc)
      into v_v, v_e, v_d
      from (select case when e.equipo_local = a.equipo then e.goles_local else e.goles_visitante end gf,
                   case when e.equipo_local = a.equipo then e.goles_visitante else e.goles_local end gc
              from encuentros e
             where e.partido_id = p_partido and a.equipo in (e.equipo_local, e.equipo_visitante)) t;

    v_nota := nota_partido(p_partido, a.miembro_id);

    d := jsonb_build_object(
      'jugado',            regla(l.id, 'jugado', v_pos),
      'resultado',         v_v * regla(l.id, 'victoria', v_pos) + v_e * regla(l.id, 'empate', v_pos),
      'goles',             a.goles * regla(l.id, v_gol, v_pos),
      'asistencias',       a.asistencias * regla(l.id, 'asistencia', v_pos),
      'porteria_cero',     case when v_pos is null then 0
                                else a.porterias_cero * regla(l.id, 'porteria_cero_' || v_pos, v_pos) end,
      'goles_encajados',   case when v_pos = 'portero'
                                then floor(a.goles_encajados / 3.0) * regla(l.id, 'goles_encajados_3', v_pos)
                                else 0 end,
      'paradas',           floor(a.paradas_clave / 2.0) * regla(l.id, 'parada_clave_2', v_pos),
      'penaltis_parados',  a.penaltis_parados * regla(l.id, 'penalti_parado', v_pos),
      'penaltis_fallados', a.penaltis_fallados * regla(l.id, 'penalti_fallado', v_pos),
      'autogoles',         a.autogoles * regla(l.id, 'autogol', v_pos),
      'valoracion',        puntos_por_nota(v_nota.nota, regla(l.id, 'valoracion_max', v_pos)),
      'mvp',               0);

    select sum(value::numeric) into v_total from jsonb_each_text(d);
    d := d || jsonb_build_object('notas', v_nota.por_aspecto);

    insert into puntos_fantasy (partido_id, miembro_id, posicion, victorias, empates, derrotas,
                                nota_media, num_votantes, es_mvp, desglose, total)
    values (p_partido, a.miembro_id, v_pos, v_v, v_e, v_d, v_nota.nota, v_nota.votantes, false, d, v_total);
  end loop;

  -- MVP: mayor nota (≥ 3 votantes); desempate goles + asistencias; si persiste, compartido
  select max(nota_media) into v_max_nota from puntos_fantasy
   where partido_id = p_partido and num_votantes >= 3;
  if v_max_nota is not null then
    select max(aj.goles + aj.asistencias) into v_max_ga
      from puntos_fantasy pf join acta_jugador aj using (partido_id, miembro_id)
     where pf.partido_id = p_partido and pf.num_votantes >= 3 and pf.nota_media = v_max_nota;

    update puntos_fantasy pf
       set es_mvp = true,
           desglose = jsonb_set(pf.desglose, '{mvp}', to_jsonb(regla(p.liga_id, 'mvp', pf.posicion))),
           total = pf.total + regla(p.liga_id, 'mvp', pf.posicion)
      from acta_jugador aj
     where aj.partido_id = pf.partido_id and aj.miembro_id = pf.miembro_id
       and pf.partido_id = p_partido and pf.num_votantes >= 3
       and pf.nota_media = v_max_nota and aj.goles + aj.asistencias = v_max_ga;
  end if;

  update partidos set estado = 'cerrado' where id = p_partido;
end $$;

-- ───────────── Vistas de estadísticas (respetan RLS del usuario) ─────────────
create view v_rendimiento with (security_invoker = true) as
select m.liga_id, pf.miembro_id,
       count(*)                                         as partidos,
       sum(pf.total)                                    as puntos_total,
       round(avg(pf.total), 2)                          as puntos_media,
       sum(aj.goles)                                    as goles,
       round(avg(aj.goles), 2)                          as goles_partido,
       sum(aj.asistencias)                              as asistencias,
       round(avg(pf.nota_media), 2)                     as nota_media,
       count(*) filter (where pf.es_mvp)                as mvps,
       sum(pf.victorias)                                as victorias,
       sum(pf.empates)                                  as empates,
       sum(pf.derrotas)                                 as derrotas,
       round(100.0 * sum(pf.victorias)
             / nullif(sum(pf.victorias + pf.empates + pf.derrotas), 0), 1) as pct_victorias
  from puntos_fantasy pf
  join miembros m on m.id = pf.miembro_id
  join acta_jugador aj using (partido_id, miembro_id)
 group by m.liga_id, pf.miembro_id;

create view v_clasificacion with (security_invoker = true) as
select r.*, rank() over (partition by r.liga_id order by r.puntos_total desc, r.puntos_media desc) as posicion
  from v_rendimiento r;

create view v_pichichi with (security_invoker = true) as
select r.*, rank() over (partition by r.liga_id order by r.goles desc, r.partidos asc) as posicion
  from v_rendimiento r
 where r.goles > 0;

-- Historial partido a partido (ficha del jugador y forma reciente para el balanceo)
create view v_historial_jugador with (security_invoker = true) as
select pf.miembro_id, p.liga_id, p.id as partido_id, p.fecha_hora,
       pf.victorias, pf.empates, pf.derrotas, aj.goles, aj.asistencias,
       pf.nota_media, pf.es_mvp, pf.total, pf.desglose,
       row_number() over (partition by pf.miembro_id order by p.fecha_hora desc) as recencia
  from puntos_fantasy pf
  join partidos p on p.id = pf.partido_id
  join acta_jugador aj using (partido_id, miembro_id);

-- Media por aspecto de valoración (a partir de las medias ya publicadas, nunca de votos sueltos)
create view v_notas_aspecto with (security_invoker = true) as
select m.liga_id, pf.miembro_id, n.key as aspecto,
       round(avg(n.value::numeric), 2) as nota_media, count(*) as partidos
  from puntos_fantasy pf
  join miembros m on m.id = pf.miembro_id
  cross join lateral jsonb_each_text(pf.desglose -> 'notas') n
 group by m.liga_id, pf.miembro_id, n.key;
