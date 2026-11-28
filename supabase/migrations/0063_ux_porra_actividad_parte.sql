-- 0063 · Bloques 3 y 4 de la prueba con usuarios
--  · Porra por módulos: el admin activa o quita 1X2, bote, goleador, MVP, combinadas, múltiples y seguro.
--  · Actividad del Fantasy: registro público de fichajes, ventas, cláusulas, subastas, ofertas y cesiones.
--  · Parte post-partido: quién ha votado y quién falta, recordatorio (cada 2 h como mucho) y podio con desglose.
--  · Resumen de la jornada: qué pasó y por qué cada jugador sumó sus puntos.

-- ───────────── Porra por módulos ─────────────
alter table ligas add column if not exists porra_modulos jsonb not null
  default '{"1x2": true, "bote": true, "goleador": true, "mvp": true, "combinadas": true, "multiples": true, "seguro": true}';

create or replace function porra_modulo(p_liga uuid, p_modulo text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (porra_modulos ->> p_modulo)::boolean from ligas where id = p_liga), true)
$$;

create or replace function validar_modulos_apuesta() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.tipo = 'combinada' and not porra_modulo(new.liga_id, 'combinadas') then
    raise exception 'Las combinadas no están activadas en esta liga';
  end if;
  if new.tipo = 'multiple' and not porra_modulo(new.liga_id, 'multiples') then
    raise exception 'Las múltiples no están activadas en esta liga';
  end if;
  if new.seguro and not porra_modulo(new.liga_id, 'seguro') then
    raise exception 'El seguro de apuesta no está activado en esta liga';
  end if;
  return new;
end $$;
create or replace trigger t_modulos_apuesta before insert on apuestas
  for each row execute function validar_modulos_apuesta();

create or replace function validar_modulos_seleccion() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_liga uuid; v_mod text;
begin
  select liga_id into v_liga from apuestas where id = new.apuesta_id;
  v_mod := case new.mercado when 'no_goleador' then 'goleador' else new.mercado end;
  if not porra_modulo(v_liga, v_mod) then
    raise exception 'Ese mercado de la porra no está activado en esta liga';
  end if;
  return new;
end $$;
create or replace trigger t_modulos_seleccion before insert on apuesta_selecciones
  for each row execute function validar_modulos_seleccion();

create or replace function validar_modulo_bote() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not porra_modulo(new.liga_id, 'bote') then raise exception 'El bote no está activado en esta liga'; end if;
  return new;
end $$;
create or replace trigger t_modulo_bote before insert on quinielas
  for each row execute function validar_modulo_bote();

create or replace function porra_modulos_liga(p_liga uuid, p_modulos jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform exigir_admin(p_liga);
  if jsonb_typeof(p_modulos) <> 'object' then raise exception 'Formato no válido'; end if;
  update ligas set porra_modulos = porra_modulos || (select coalesce(jsonb_object_agg(k, (v #>> '{}')::boolean), '{}')
                                                       from jsonb_each(p_modulos) e(k, v)
                                                      where k in ('1x2', 'bote', 'goleador', 'mvp', 'combinadas', 'multiples', 'seguro'))
   where id = p_liga;
end $$;
revoke execute on function porra_modulos_liga(uuid, jsonb) from public, anon;
grant execute on function porra_modulos_liga(uuid, jsonb) to authenticated;

-- ───────────── Actividad pública del Fantasy ─────────────
create or replace function actividad_fantasy(p_liga uuid, p_limite int default 60) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not es_miembro(p_liga) then '[]'::jsonb else coalesce((
    select jsonb_agg(x order by x.creado_en desc) from (
      select t.tipo, t.creado_en, round(abs(t.importe), 2) importe,
             t.manager_id, nombre_miembro(t.manager_id) manager,
             t.jugador_id, case when t.jugador_id is not null then nombre_miembro(t.jugador_id) end jugador,
             -- En una cláusula, a quién se la quitaron
             case when t.tipo = 'clausula_pagada' then
               (select nombre_miembro(c.manager_id) from transacciones_fantasy c
                 where c.liga_id = t.liga_id and c.tipo = 'clausula_cobrada' and c.jugador_id = t.jugador_id
                   and c.creado_en between t.creado_en - interval '10 seconds' and t.creado_en + interval '10 seconds'
                 limit 1) end otro
        from transacciones_fantasy t
       where t.liga_id = p_liga
         and t.tipo in ('compra', 'venta', 'clausula_pagada', 'subasta', 'subasta_venta', 'oferta_pagada', 'cesion_pagada', 'draft')
       order by t.creado_en desc
       limit least(greatest(p_limite, 1), 200)) x), '[]') end
$$;
grant execute on function actividad_fantasy(uuid, int) to authenticated;

-- ───────────── Parte post-partido: participación ─────────────
create or replace function participacion_post_partido(p_partido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p partidos;
begin
  select * into p from partidos where id = p_partido;
  if not found or not es_miembro(p.liga_id) then raise exception 'Partido no encontrado'; end if;
  return (
    with jug as (select c.miembro_id from convocatorias c
                  where c.partido_id = p_partido and c.estado = 'confirmado' and c.equipo is not null),
    vot as (select votante_id m from valoraciones where partido_id = p_partido
            union select votante_id from votos_podio where partido_id = p_partido
            union select votante_id from votos_mvp where partido_id = p_partido
            union select reportero_id from reportes_encuentro where partido_id = p_partido)
    select jsonb_build_object(
      'jugadores', (select count(*) from jug),
      'votaron', (select count(*) from jug where miembro_id in (select m from vot)),
      'faltan', coalesce((select jsonb_agg(jsonb_build_object('miembro_id', miembro_id, 'nombre', nombre_miembro(miembro_id))
                                           order by nombre_miembro(miembro_id))
                            from jug where miembro_id not in (select m from vot)), '[]'),
      'cierra', p.votacion_cierra,
      'ultimo_recordatorio', (select creado_en from recordatorios_enviados where partido_id = p_partido and tipo = 'votar_manual'),
      -- Podio: votos que lleva cada uno en 1.º, 2.º y 3.º (no se dice quién votó a quién)
      'podio', coalesce((select jsonb_agg(jsonb_build_object('miembro_id', votado_id, 'nombre', nombre_miembro(votado_id),
                                                             'primero', p1, 'segundo', p2, 'tercero', p3,
                                                             'puntos', 3 * p1 + 2 * p2 + p3)
                                          order by 3 * p1 + 2 * p2 + p3 desc, p1 desc)
                           from (select votado_id, count(*) filter (where puesto = 1) p1, count(*) filter (where puesto = 2) p2,
                                        count(*) filter (where puesto = 3) p3
                                   from votos_podio where partido_id = p_partido group by votado_id) v), '[]'))
  );
end $$;
grant execute on function participacion_post_partido(uuid) to authenticated;

-- Recordar a los que faltan por votar (cualquier jugador del partido; como mucho cada 2 horas)
create or replace function recordar_votar(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; v_ok int; v_faltan uuid[];
begin
  select * into p from partidos where id = p_partido;
  if not found or not es_miembro(p.liga_id) then raise exception 'Partido no encontrado'; end if;
  if p.estado <> 'post_partido' then raise exception 'La votación de este partido ya está cerrada'; end if;
  insert into recordatorios_enviados (partido_id, tipo, creado_en) values (p_partido, 'votar_manual', now())
  on conflict (partido_id, tipo) do update set creado_en = now()
   where recordatorios_enviados.creado_en < now() - interval '2 hours';
  get diagnostics v_ok = row_count;
  if v_ok = 0 then raise exception 'Ya se ha recordado hace poco: prueba dentro de un rato'; end if;
  select array_agg(x ->> 'miembro_id') into v_faltan
    from jsonb_array_elements(participacion_post_partido(p_partido) -> 'faltan') x;
  if v_faltan is null then return 0; end if;
  return notificar(perfiles_de_miembros(v_faltan), p.liga_id, 'recordatorio_votar', '¡Falta tu voto! 🗳️',
                   'Vota a tus compañeros del partido del ' || fecha_corta(p.fecha_hora) || ' antes de que cierre',
                   '/partidos/' || p_partido);
end $$;
revoke execute on function recordar_votar(uuid) from public, anon;
grant execute on function recordar_votar(uuid) to authenticated;

-- ───────────── Resumen de la jornada ─────────────
create or replace function resumen_jornada(p_partido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p partidos;
begin
  select * into p from partidos where id = p_partido;
  if not found or not es_miembro(p.liga_id) then raise exception 'Partido no encontrado'; end if;
  return jsonb_build_object(
    'estado', p.estado,
    'fecha', p.fecha_hora,
    'encuentros', coalesce((select jsonb_agg(jsonb_build_object('local', equipo_local, 'visitante', equipo_visitante,
                                                                'goles_local', goles_local, 'goles_visitante', goles_visitante) order by n)
                              from encuentros where partido_id = p_partido), '[]'),
    'mvp', (select jsonb_agg(nombre_miembro(miembro_id)) from puntos_fantasy where partido_id = p_partido and es_mvp),
    'jugadores', coalesce((select jsonb_agg(jsonb_build_object(
                    'miembro_id', pf.miembro_id, 'nombre', nombre_miembro(pf.miembro_id), 'total', pf.total,
                    'es_mvp', pf.es_mvp, 'nota', round(pf.nota_media, 1), 'desglose', pf.desglose,
                    'victorias', pf.victorias, 'empates', pf.empates, 'derrotas', pf.derrotas,
                    'precio', hp.precio,
                    'variacion', hp.precio - (select h2.precio from historial_precios h2
                                               where h2.liga_id = p.liga_id and h2.miembro_id = pf.miembro_id
                                                 and h2.creado_en < hp.creado_en order by h2.creado_en desc limit 1))
                   order by pf.total desc)
                  from puntos_fantasy pf
                  left join lateral (select precio, creado_en from historial_precios h
                                      where h.partido_id = p_partido and h.miembro_id = pf.miembro_id
                                      order by creado_en desc limit 1) hp on true
                 where pf.partido_id = p_partido), '[]'),
    'managers', coalesce((select jsonb_agg(jsonb_build_object('nombre', nombre_miembro(manager_id), 'puntos', round(puntos, 1),
                                                              'ingreso', round(ingreso, 1)) order by puntos desc)
                            from puntos_manager where partido_id = p_partido), '[]'),
    'porra', (select jsonb_build_object('boletos', count(*), 'ganados', count(*) filter (where estado = 'ganada'),
                                        'pagado', round(coalesce(sum(retorno) filter (where estado in ('ganada', 'parcial')), 0), 1))
                from apuestas where partido_id = p_partido),
    'bote', (select to_jsonb(b) from porra_bote_partidos b where partido_id = p_partido));
end $$;
grant execute on function resumen_jornada(uuid) to authenticated;
