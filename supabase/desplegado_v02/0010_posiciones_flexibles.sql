-- 0010 · Posiciones flexibles (ampliación 0.2, docs/mercado_fantasy.md §10.1)
-- En la liga no hay portero fijo: todos rotan. Los puntos del partido real son iguales para todos;
-- la posición del perfil queda solo como "posición preferida" (informativa).
-- Migración aditiva sobre 0001–0009: transforma reglas, aspectos, media de la encuesta y calcular_puntos.

-- ───────────── Ligas ─────────────
-- puntuar_por_posicion queda obsoleta (se ignora); se deja la columna para no romper la app 0.1.
alter table ligas alter column puntuar_por_posicion set default false;
update ligas set puntuar_por_posicion = false where puntuar_por_posicion;
comment on column ligas.puntuar_por_posicion is 'Obsoleta desde 0010: los puntos ya no dependen de la posición';

-- Bonus de rol en la alineación Fantasy (§10.2). false = el rol es solo estético.
alter table ligas add column bonus_roles boolean not null default true;

-- ───────────── Reglas de puntuación ─────────────
-- Fuera las reglas por posición y las de portería/encajados del jugador real.
delete from reglas_puntuacion
 where posicion is not null
    or clave in ('gol_portero', 'gol_defensa', 'gol_medio', 'gol_delantero',
                 'porteria_cero_portero', 'porteria_cero_defensa', 'goles_encajados_3');
-- Gol único = 5 (si la liga tenía el valor por defecto 4; un valor personalizado se respeta)
update reglas_puntuacion set puntos = 5 where clave = 'gol' and posicion is null and puntos = 4;
insert into reglas_puntuacion (liga_id, clave, puntos) select id, 'gol', 5 from ligas on conflict do nothing;
-- Bonus de rol en la alineación (solo para el mánager que alinea)
insert into reglas_puntuacion (liga_id, clave, puntos)
select l.id, r.clave, r.puntos
  from ligas l
 cross join (values ('rol_por_porteria_cero', 3), ('rol_por_menos_goleado', 2), ('rol_por_encajados_3', -1),
                    ('rol_def_menos_goleado', 1), ('rol_med_asistencia', 1), ('rol_del_gol', 1)) r(clave, puntos)
on conflict do nothing;

-- ───────────── Aspectos de valoración: iguales para todos ─────────────
update aspectos_valoracion set activo = false where clave = 'porteria';
update aspectos_valoracion set aplica_a = 'todos' where aplica_a <> 'todos';

-- ───────────── Valores por defecto de ligas nuevas ─────────────
create or replace function sembrar_liga_defecto(p_liga uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into reglas_puntuacion (liga_id, clave, puntos) values
    (p_liga, 'jugado',                 2),
    (p_liga, 'victoria',               3),   -- por encuentro ganado
    (p_liga, 'empate',                 1),
    (p_liga, 'gol',                    5),   -- igual para todos
    (p_liga, 'asistencia',             3),
    (p_liga, 'parada_clave_2',         1),   -- por cada 2 paradas clave (a quien estuviera de portero)
    (p_liga, 'penalti_parado',         3),
    (p_liga, 'penalti_fallado',       -2),
    (p_liga, 'autogol',               -2),
    (p_liga, 'valoracion_max',         4),   -- tope de puntos por nota de compañeros
    (p_liga, 'mvp',                    3),
    -- Bonus de rol en la alineación Fantasy (ligas.bonus_roles)
    (p_liga, 'rol_por_porteria_cero',  3),
    (p_liga, 'rol_por_menos_goleado',  2),
    (p_liga, 'rol_por_encajados_3',   -1),
    (p_liga, 'rol_def_menos_goleado',  1),
    (p_liga, 'rol_med_asistencia',     1),
    (p_liga, 'rol_del_gol',            1)
  on conflict do nothing;

  insert into aspectos_valoracion (liga_id, clave, nombre, descripcion, orden, aplica_a, activo) values
    (p_liga, 'ataque',       'Ataque',        'Peligro, regate, remate y desmarque',           1, 'todos', true),
    (p_liga, 'defensa',      'Defensa',       'Recuperaciones, marcaje, ayudas atrás',         2, 'todos', true),
    (p_liga, 'pase_vision',  'Pase y visión', 'Precisión, último pase, hacer jugar al equipo', 3, 'todos', true),
    (p_liga, 'esfuerzo',     'Esfuerzo',      'Intensidad, presión y compromiso',              4, 'todos', true),
    (p_liga, 'juego_limpio', 'Juego limpio',  'Deportividad y respeto',                        5, 'todos', true),
    (p_liga, 'porteria',     'Portería',      'Paradas, salidas y colocación (si se activa, a todos)', 6, 'todos', false)
  on conflict do nothing;
end $$;
revoke execute on function sembrar_liga_defecto(uuid) from public, anon, authenticated;

-- ───────────── Media general de la encuesta: única para todos ─────────────
-- Se mantiene la firma (el parámetro de posición se ignora) para no tocar cerrar_encuesta.
create or replace function media_general(p_pos posicion_campo, cal numeric, vel numeric, res numeric,
                                         def numeric, reg numeric, por numeric) returns numeric
language sql immutable set search_path = public as $$
  select 0.30 * coalesce(cal, 50) + 0.15 * coalesce(vel, 50) + 0.15 * coalesce(res, 50)
       + 0.15 * coalesce(def, 50) + 0.15 * coalesce(reg, 50) + 0.10 * coalesce(por, 50)
$$;
-- Recalcula la media de las valoraciones existentes (los precios ya fijados no se tocan;
-- la nueva G entra en el rating dinámico a partir de la próxima jornada)
update valoracion_jugador
   set general = round(media_general(null, calidad, velocidad, resistencia, defensa, regate, portero), 2),
       actualizado_en = now();

-- ───────────── Puntos del partido real: neutros respecto a la posición ─────────────
-- Igual que 0005 salvo: sin gol por posición, sin portería a cero ni goles encajados del jugador.
-- puntos_fantasy.posicion guarda la posición preferida solo como dato informativo.
create or replace function calcular_puntos(p_partido uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; a record; v_v int; v_e int; v_d int; v_nota record; d jsonb; v_total numeric;
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
    select count(*) filter (where gf > gc), count(*) filter (where gf = gc), count(*) filter (where gf < gc)
      into v_v, v_e, v_d
      from (select case when e.equipo_local = a.equipo then e.goles_local else e.goles_visitante end gf,
                   case when e.equipo_local = a.equipo then e.goles_visitante else e.goles_local end gc
              from encuentros e
             where e.partido_id = p_partido and a.equipo in (e.equipo_local, e.equipo_visitante)) t;

    v_nota := nota_partido(p_partido, a.miembro_id);

    d := jsonb_build_object(
      'jugado',            regla(l.id, 'jugado'),
      'resultado',         v_v * regla(l.id, 'victoria') + v_e * regla(l.id, 'empate'),
      'goles',             a.goles * regla(l.id, 'gol'),
      'asistencias',       a.asistencias * regla(l.id, 'asistencia'),
      'paradas',           floor(a.paradas_clave / 2.0) * regla(l.id, 'parada_clave_2'),
      'penaltis_parados',  a.penaltis_parados * regla(l.id, 'penalti_parado'),
      'penaltis_fallados', a.penaltis_fallados * regla(l.id, 'penalti_fallado'),
      'autogoles',         a.autogoles * regla(l.id, 'autogol'),
      'valoracion',        puntos_por_nota(v_nota.nota, regla(l.id, 'valoracion_max')),
      'mvp',               0);

    select sum(value::numeric) into v_total from jsonb_each_text(d);
    d := d || jsonb_build_object('notas', v_nota.por_aspecto);

    insert into puntos_fantasy (partido_id, miembro_id, posicion, victorias, empates, derrotas,
                                nota_media, num_votantes, es_mvp, desglose, total)
    values (p_partido, a.miembro_id, posicion_de(a.miembro_id), v_v, v_e, v_d, v_nota.nota, v_nota.votantes,
            false, d, v_total);
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
           desglose = jsonb_set(pf.desglose, '{mvp}', to_jsonb(regla(p.liga_id, 'mvp'))),
           total = pf.total + regla(p.liga_id, 'mvp')
      from acta_jugador aj
     where aj.partido_id = pf.partido_id and aj.miembro_id = pf.miembro_id
       and pf.partido_id = p_partido and pf.num_votantes >= 3
       and pf.nota_media = v_max_nota and aj.goles + aj.asistencias = v_max_ga;
  end if;

  update partidos set estado = 'cerrado' where id = p_partido;
end $$;
