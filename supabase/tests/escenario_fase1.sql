-- 0053 · Fase 1: consentimiento, podio, equipo de la jornada, fusión de fichas, mánagers e historial
\set ON_ERROR_STOP 1
\pset pager off
reset role;
insert into auth.users (id, email) select t_uid(i), 'u' || i || '@test' from generate_series(801, 808) i;
insert into perfiles (id, nombre, apodo, posicion)
select t_uid(i), 'F1 ' || i, 'Apodo' || i,
       (array['portero', 'defensa', 'defensa', 'medio', 'medio', 'delantero', 'medio', 'defensa'])[i - 800]::posicion_campo
  from generate_series(801, 808) i;
set role authenticated;

-- ═════════ RGPD
select t_como(801);
select t_check(not (mi_consentimiento() ->> 'al_dia')::boolean, 'sin aceptar al principio');
select t_debe_fallar($$select registrar_consentimiento('2020-01-01')$$, 'versión antigua rechazada');
select t_check((registrar_consentimiento((politica_vigente()).version, true, false, 'android') ->> 'al_dia')::boolean,
               'aceptada la política vigente');
select registrar_consentimiento((politica_vigente()).version, false, false);
select t_check((select count(*) from user_consents) = 2, 'cada cambio queda registrado (solo los míos visibles)');
select t_check(((mi_consentimiento() -> 'ultimo' -> 'consent_flags' ->> 'errores')::boolean) = false, 'permiso opcional revocado');
select t_como(802);
select t_check((select count(*) from user_consents) = 0, 'no veo los consentimientos de otros');

-- ═════════ Liga con podio (3 contra 3)
select t_como(801);
select crear_liga('{"nombre":"Liga Fase1","jugadores_por_equipo":3,"num_equipos":2}') as lf \gset
select set_config('t.liga', :'lf', false);
select codigo_invitacion as codf from ligas where id = :'lf' \gset
select set_config('t.codigo', :'codf', false);
do $$ begin
  for i in 802..806 loop perform t_como(i); perform unirse(current_setting('t.codigo')); end loop;
  perform t_como(801);
  for i in 802..806 loop perform cambiar_rango(t_m(i), 'fijo'); end loop;
end $$;
reset role;
update ligas set modo_valoracion = 'podio' where id = :'lf';
set role authenticated;

set role authenticated;
select t_como(801);
select crear_partido(current_setting('t.liga')::uuid, '2027-06-01 20:00 Europe/Madrid', 0) as p \gset
select set_config('t.p', :'p', false);
select t_confirmar(:'p');
select guardar_equipos(:'p', jsonb_build_object(t_m(801), 1, t_m(802), 1, t_m(803), 1, t_m(804), 2, t_m(805), 2, t_m(806), 2));
select marcar_jugado(:'p');

select t_debe_fallar(format($$select enviar_post_partido(%L, p_podio => array[t_m(801)])$$, :'p'), 'no te puedes votar');
select t_debe_fallar(format($$select enviar_post_partido(%L, p_podio => array[t_m(802), t_m(802)])$$, :'p'), 'jugador repetido en el podio');
-- 804 marca 2 y casi todos lo ponen 1.º; 802 suele ir 2.º
do $$
declare r int; p uuid := current_setting('t.p')::uuid;
begin
  for r in 801..806 loop
    perform t_como(r);
    perform enviar_post_partido(p, t_res(1, 2),
      jsonb_build_array(t_jug(801, 0), t_jug(802, 1), t_jug(803, 0), t_jug(804, 2), t_jug(805, 0), t_jug(806, 0)),
      null, null,
      case when r = 804 then array[t_m(802), t_m(805), t_m(806)]
           when r = 802 then array[t_m(804), t_m(805), t_m(801)]
           when r = 805 then array[t_m(804), t_m(802), t_m(803)]
           else array[t_m(804), t_m(802), t_m(805)] end);
  end loop;
end $$;
select t_como(803);
select t_check(jsonb_array_length(mi_post_partido(:'p') -> 'podio') = 3, 'recupero mi podio');
select t_como(801);
select cerrar_post_partido(:'p');
reset role;
select t_check((select es_mvp and puesto = 1 from puntos_fantasy where partido_id = :'p' and miembro_id = t_m(804)), 'MVP = más puntos de podio');
select t_check((select puesto from puntos_fantasy where partido_id = :'p' and miembro_id = t_m(802)) = 2, '2.º del podio');
select t_check((select puesto from puntos_fantasy where partido_id = :'p' and miembro_id = t_m(805)) = 3, '3.º del podio');
select t_check((select (desglose ->> 'valoracion')::numeric = 5 from puntos_fantasy where partido_id = :'p' and miembro_id = t_m(804)),
               'el 1.º suma 5 de podio');
select t_check((select (desglose ->> 'valoracion')::numeric = 0 from puntos_fantasy where partido_id = :'p' and miembro_id = t_m(803)),
               'fuera del podio no suma valoración');
select t_check((select total = (select sum(value::numeric) from jsonb_each(desglose) where jsonb_typeof(value) = 'number'
                                  and key not in ('votos_mvp', 'votos_podio', 'votos_primero'))
                  from puntos_fantasy where partido_id = :'p' and miembro_id = t_m(802)),
               'el total cuadra con el desglose');
set role authenticated;
select t_como(803);
select t_check((select count(*) from equipo_jornada(:'p')) = 3, 'equipo de la jornada de 3');
select t_check(exists (select 1 from equipo_jornada(:'p') where miembro_id = t_m(804)), 'el MVP está en el equipo de la jornada');

-- ═════════ Modo rápido (notas): también hay podio de 3 y bonus 2.º/3.º
reset role;
update ligas set modo_valoracion = 'rapida' where id = :'lf';
set role authenticated;
select t_como(801);
select crear_partido(current_setting('t.liga')::uuid, '2027-06-08 20:00 Europe/Madrid', 0) as q \gset
select set_config('t.q', :'q', false);
select t_confirmar(:'q');
select guardar_equipos(:'q', jsonb_build_object(t_m(801), 1, t_m(802), 1, t_m(803), 1, t_m(804), 2, t_m(805), 2, t_m(806), 2));
select marcar_jugado(:'q');
do $$
declare r int; q uuid := current_setting('t.q')::uuid;
begin
  for r in 801..806 loop
    perform t_como(r);
    perform enviar_post_partido(q, t_res(2, 0),
      jsonb_build_array(t_jug(801, 0), t_jug(802, 2), t_jug(803, 0), t_jug(804, 0), t_jug(805, 0), t_jug(806, 0)),
      (select jsonb_agg(jsonb_build_object('votado_id', t_m(s), 'nota', case s when 802 then 9 when 803 then 8 when 801 then 7 else 5 end))
         from generate_series(801, 806) s where s <> r));
  end loop;
end $$;
select t_como(801);
select cerrar_post_partido(:'q');
reset role;
select t_check((select es_mvp from puntos_fantasy where partido_id = :'q' and miembro_id = t_m(802)), 'rápida: MVP la mejor nota');
select t_check((select puesto from puntos_fantasy where partido_id = :'q' and miembro_id = t_m(803)) = 2, 'rápida: 2.º');
select t_check((select (desglose ->> 'podio')::numeric from puntos_fantasy where partido_id = :'q' and miembro_id = t_m(803)) = 2,
               'rápida: bonus de 2.º');
set role authenticated;

-- ═════════ Fusión: fantasma con historial + jugador que entró por el código general
select t_como(801);
select miembro_id as fant, token as tok from precrear_jugadores(current_setting('t.liga')::uuid, array['Pepe Fantasma']) \gset
reset role;
insert into convocatorias (partido_id, miembro_id, estado, equipo) values (:'p', :'fant', 'confirmado', 1);
insert into historial_importado (miembro_id, liga_id, partidos, goles) values (:'fant', :'lf', 20, 12);
set role authenticated;
select t_como(807);
select unirse(current_setting('t.codigo'));
select t_como(807);
select unirse(:'tok');
reset role;
select t_check((select count(*) from miembros where liga_id = :'lf' and perfil_id = t_uid(807)) = 1, 'una sola ficha tras reclamar');
select t_check((select id from miembros where liga_id = :'lf' and perfil_id = t_uid(807)) = :'fant'::uuid, 'se conserva la ficha con historial');
select t_check(exists (select 1 from convocatorias where partido_id = :'p' and miembro_id = :'fant'), 'el partido sigue en su ficha');
select t_check((select goles from historial_importado where miembro_id = :'fant') = 12, 'el historial sigue');
select t_check(current_setting('session_replication_role') = 'origin', 'disparadores reactivados');

-- Fusión manual por el administrador
set role authenticated;
select t_como(801);
select miembro_id as f2 from precrear_jugadores(current_setting('t.liga')::uuid, array['Otro Fantasma']) \gset
select t_como(808);
select unirse(current_setting('t.codigo'));
select t_como(802);
select t_debe_fallar(format($$select fusionar_fichas(%L, t_m(808))$$, :'f2'), 'solo el admin une fichas');
select t_como(801);
select set_config('t.m808', t_m(808)::text, false);
select fusionar_fichas(:'f2', current_setting('t.m808')::uuid);
reset role;
select t_check((select perfil_id from miembros where id = :'f2') = t_uid(808), 'ficha unida a la cuenta');
select t_check(not exists (select 1 from miembros where id = current_setting('t.m808')::uuid), 'la ficha duplicada desaparece');

-- ═════════ Historial importado
set role authenticated;
select t_como(801);
select t_check((select (x ->> 'nuevo')::boolean from jsonb_array_elements(previsualizar_historial(current_setting('t.liga')::uuid,
  '[{"nombre":"Nuevo Total","partidos":10,"goles":3}]')) x), 'previsualizar detecta jugador nuevo');
select t_check((select x ->> 'miembro_id' from jsonb_array_elements(previsualizar_historial(current_setting('t.liga')::uuid,
  '[{"nombre":"apodo802","partidos":5}]')) x) = t_m(802)::text, 'empareja por apodo sin mayúsculas');
select t_check((select x ->> 'error' from jsonb_array_elements(previsualizar_historial(current_setting('t.liga')::uuid,
  '[{"nombre":"X","partidos":2,"victorias":3}]')) x) is not null, 'detecta victorias imposibles');
select t_debe_fallar(format($$select importar_historial(%L, '[{"nombre":"X","partidos":2,"victorias":3}]')$$, current_setting('t.liga')),
                     'no importa filas con errores');
select importar_historial(current_setting('t.liga')::uuid,
  '[{"nombre":"Apodo803","partidos":60,"victorias":30,"empates":10,"derrotas":20,"goles":55,"asistencias":10,"mvps":6,"valoracion_media":7.5},
    {"nombre":"Nuevo Total","partidos":10,"goles":3}]');
select t_check(exists (select 1 from miembros where liga_id = current_setting('t.liga')::uuid and nombre_provisional = 'Nuevo Total'
                                                and estado = 'pendiente_registro'), 'crea el fantasma para reclamar');
select t_check((select partidos from v_rendimiento where miembro_id = t_m(803)) = 62, 'rendimiento suma importados + app');
select t_check((select goles from v_rendimiento where miembro_id = t_m(803)) = 55, 'goles acumulados');
reset role;
select t_check((select count(*) from logros where miembro_id = t_m(803) and tipo in ('goles_50', 'partidos_50', 'mvp_5')) = 3,
               'logros retroactivos');
set role authenticated;
select t_como(802);
select t_debe_fallar(format($$select importar_historial(%L, '[]')$$, current_setting('t.liga')), 'solo el admin importa');

-- ═════════ Mánagers de golpe
reset role;
update ligas set fantasy_activo = true, presupuesto_inicial = coalesce(presupuesto_inicial, 100) where id = :'lf';
set role authenticated;
select t_como(801);
select crear_managers(current_setting('t.liga')::uuid) as nman \gset
reset role;
select t_check((select count(*) from fantasy_managers where liga_id = :'lf')
               = (select count(*) from miembros where liga_id = :'lf' and estado = 'activo' and perfil_id is not null),
               'un mánager por jugador registrado (' || :'nman' || ')');
set role authenticated;
select t_como(801);
select t_check(crear_managers(current_setting('t.liga')::uuid) = 0, 'repetir no duplica');

-- ═════════ Dorsal
select t_como(803);
select t_debe_fallar($$update perfiles set dorsal = 100 where id = auth.uid()$$, 'dorsal fuera de rango');
reset role;
\echo '══════ ESCENARIO FASE 1 COMPLETADO SIN ERRORES ══════'
