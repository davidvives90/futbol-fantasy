\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);
select set_config('t.admin', (select perfil_id::text from miembros where liga_id = current_setting('t.liga')::uuid and rol = 'admin'
                                and estado = 'activo' limit 1), false);
select set_config('t.jug', (select perfil_id::text from miembros where liga_id = current_setting('t.liga')::uuid and rol = 'jugador'
                              and estado = 'activo' and perfil_id is not null order by unido_en, id limit 1), false);
select set_config('t.jug2', (select perfil_id::text from miembros where liga_id = current_setting('t.liga')::uuid and rol = 'jugador'
                              and estado = 'activo' and perfil_id is not null order by unido_en, id offset 1 limit 1), false);
select t_check((select modalidad from ligas where id = current_setting('t.liga')::uuid) is not null, 'liga con modalidad');
select t_check(not valoracion_avanzada, 'post-partido simple por defecto') from ligas where id = current_setting('t.liga')::uuid;
set role authenticated;

-- reglamento
select t_como_uid(current_setting('t.jug')::uuid);
select t_check(jsonb_array_length(reglamento_liga(current_setting('t.liga')::uuid)) >= 10, 'reglamento con valores estándar');
select t_debe_fallar(format($$select cambiar_regla(%L, 'cesion', 'true')$$, current_setting('t.liga')), 'jugador no cambia reglas');
select t_como_uid(current_setting('t.admin')::uuid);
select cambiar_modalidad(current_setting('t.liga')::uuid, 'f7');
select cambiar_regla(current_setting('t.liga')::uuid, 'cesion', 'true');
select t_check((select (r ->> 'valor')::boolean and (r ->> 'personalizada')::boolean
                  from jsonb_array_elements(reglamento_liga(current_setting('t.liga')::uuid)) r where r ->> 'clave' = 'cesion'), 'regla cambiada');
select t_debe_fallar(format($$select cambiar_regla(%L, 'saque_banda', '"cabeza"')$$, current_setting('t.liga')), 'opción inválida');
select t_debe_fallar(format($$select cambiar_regla(%L, 'minutos_parte', '500')$$, current_setting('t.liga')), 'número fuera de rango');
select cambiar_modalidad(current_setting('t.liga')::uuid, 'f3');
select t_check(not exists (select 1 from jsonb_array_elements(reglamento_liga(current_setting('t.liga')::uuid)) r where r ->> 'clave' = 'cesion'),
               'en fútbol 3 no hay cesión');
select cambiar_modalidad(current_setting('t.liga')::uuid, 'f7');

-- votaciones
select crear_votacion(current_setting('t.liga')::uuid, '¿Jugamos con fuera de juego?', null, '["Sí","No"]',
                      now() + interval '2 days', 'fuera_de_juego', '[true,false]', false) as v1 \gset
select t_debe_fallar(format($$select crear_votacion(%L, 'mal', null, '["a","b"]', now() + interval '2 days', 'fuera_de_juego', '[1,2]')$$,
                     current_setting('t.liga')), 'valores de regla inválidos');
select t_como_uid(current_setting('t.jug')::uuid);
select t_debe_fallar(format($$select crear_votacion(%L, 'Hola', null, '["a","b"]', now() + interval '2 days')$$, current_setting('t.liga')),
                     'jugador no crea votaciones');
select votar_votacion(:'v1', 0);
select votar_votacion(:'v1', 1);   -- cambia de opinión
select votar_votacion(:'v1', 0);
select t_como_uid(current_setting('t.jug2')::uuid);
select votar_votacion(:'v1', 0);
select t_check((votacion_resultados(:'v1') -> 'votos' -> 0 ->> 'n')::int = 2, 'recuento');
select t_check(jsonb_array_length(votacion_resultados(:'v1') -> 'votos' -> 0 -> 'miembros') = 2, 'no anónima: se ve quién');
select t_debe_fallar(format($$select votar_votacion(%L, 7)$$, :'v1'), 'opción inexistente');
reset role;
update votaciones set cierra_en = now() - interval '1 minute' where id = :'v1';
select enviar_recordatorios();
select t_check((select estado = 'cerrada' and ganadora = 0 and aplicada from votaciones where id = :'v1'), 'cierre automático con ganadora');
select t_check((select (reglamento ->> 'fuera_de_juego')::boolean from ligas where id = current_setting('t.liga')::uuid), 'regla aplicada');
select t_check(exists (select 1 from notificaciones where tipo = 'votacion' and titulo = 'Votación cerrada'), 'aviso de resultado');
set role authenticated;
select t_como_uid(current_setting('t.jug')::uuid);
select t_debe_fallar(format($$select votar_votacion(%L, 0)$$, :'v1'), 'votación cerrada');
select t_debe_fallar('select * from votos_votacion', 'votos no legibles directamente');
reset role;

-- bajas y asistencia
select set_config('t.mj', (select id::text from miembros where perfil_id = current_setting('t.jug')::uuid and liga_id = current_setting('t.liga')::uuid), false);
set role authenticated;
select t_como_uid(current_setting('t.jug2')::uuid);
select t_debe_fallar(format($$select registrar_ausencia(%L, current_date, null, 'lesion')$$, current_setting('t.mj')), 'no registras bajas ajenas');
select t_como_uid(current_setting('t.jug')::uuid);
select registrar_ausencia(current_setting('t.mj')::uuid, current_date, current_date + 30, 'lesion', 'Esguince');
select registrar_ausencia(current_setting('t.mj')::uuid, current_date + 20, current_date + 60, 'lesion');
select t_check((select count(*) = 1 and max(hasta) = current_date + 60 from ausencias where miembro_id = current_setting('t.mj')::uuid),
               'bajas solapadas se funden');
reset role;
select t_check(esta_de_baja(current_setting('t.mj')::uuid, now() + interval '10 days'), 'está de baja');
set role authenticated;
select historial_asistencia(current_setting('t.liga')::uuid, 6) as h \gset
select t_check(jsonb_array_length(:'h'::jsonb -> 'partidos') between 1 and 6, 'historial: partidos');
select t_check((select x -> 'baja' is not null and x -> 'baja' <> 'null'::jsonb from jsonb_array_elements(:'h'::jsonb -> 'miembros') x
                 where x ->> 'miembro_id' = current_setting('t.mj')), 'historial: baja actual visible');
select t_check((select bool_and(e in ('"J"', '"D"', '"N"', '"B"', 'null')) from jsonb_array_elements(:'h'::jsonb -> 'miembros') x,
                 jsonb_array_elements(x -> 'estados') e(e)), 'historial: estados válidos');
select terminar_ausencia((select id from ausencias where miembro_id = current_setting('t.mj')::uuid));
select t_check(not exists (select 1 from ausencias where miembro_id = current_setting('t.mj')::uuid), 'he vuelto (baja que empezaba hoy se borra)');
select t_check(estadisticas_jugador(current_setting('t.mj')::uuid) ? 'asistencia_pct', 'estadísticas siguen funcionando');
reset role;
\echo '══════ ESCENARIO REGLAMENTO, VOTACIONES Y BAJAS COMPLETADO SIN ERRORES ══════'
