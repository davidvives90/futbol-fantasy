\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);
select set_config('t.admin', (select perfil_id::text from miembros where liga_id = current_setting('t.liga')::uuid and rol = 'admin'
                                and estado = 'activo' limit 1), false);
select set_config('t.jug', (select perfil_id::text from miembros where liga_id = current_setting('t.liga')::uuid and rol = 'jugador'
                              and estado = 'activo' and perfil_id is not null order by unido_en, id limit 1), false);
select set_config('t.mj', (select id::text from miembros where perfil_id = current_setting('t.jug')::uuid and liga_id = current_setting('t.liga')::uuid), false);

-- ── Deudas
select t_check((select recordatorio_deudas = 'mensual' and ultimo_recordatorio_deudas is not null from ligas
                 where id = current_setting('t.liga')::uuid), 'deudas: mensual y empieza a contar');
insert into movimientos (liga_id, miembro_id, tipo, importe, concepto) values
  (current_setting('t.liga')::uuid, current_setting('t.mj')::uuid, 'cargo', -15, 'prueba deuda');
set role authenticated;
select t_como_uid(current_setting('t.jug')::uuid);
select t_debe_fallar(format('select recordar_deudas(%L)', current_setting('t.liga')), 'jugador no manda recordatorios');
select t_como_uid(current_setting('t.admin')::uuid);
select recordar_deudas(current_setting('t.liga')::uuid) as n \gset
select t_check(:n >= 1, 'recordatorio enviado a los deudores');
select t_debe_fallar(format('select recordar_deudas(%L)', current_setting('t.liga')), 'no se repite en una hora');
reset role;
select t_check(exists (select 1 from notificaciones where tipo = 'deuda' and perfil_id = current_setting('t.jug')::uuid
                         and cuerpo like '%€%'), 'aviso con el importe');
update ligas set recordatorio_deudas = 'semanal', ultimo_recordatorio_deudas = now() - interval '8 days'
 where id = current_setting('t.liga')::uuid;
select enviar_recordatorios();
select t_check((select ultimo_recordatorio_deudas > now() - interval '1 minute' from ligas where id = current_setting('t.liga')::uuid)
               or extract(hour from now() at time zone 'Europe/Madrid') not between 10 and 20, 'recordatorio semanal automático');

-- ── Pagos
set role authenticated;
select t_como_uid(current_setting('t.jug')::uuid);
select avisar_pago(current_setting('t.liga')::uuid, 15, 'bizum') as av \gset
select avisar_pago(current_setting('t.liga')::uuid, 15, 'bizum') as av \gset
select t_check((select count(*) from avisos_pago where miembro_id = current_setting('t.mj')::uuid and estado = 'pendiente') = 1,
               'un solo aviso pendiente');
select t_debe_fallar(format('select resolver_aviso_pago(%L, true)', :'av'), 'jugador no confirma pagos');
select t_como_uid(current_setting('t.admin')::uuid);
select resolver_aviso_pago(:'av', true);
reset role;
select t_check(exists (select 1 from movimientos where miembro_id = current_setting('t.mj')::uuid and tipo = 'pago' and importe = 15),
               'pago apuntado en caja');

-- ── Calendario
set role authenticated;
select t_como_uid(current_setting('t.jug')::uuid);
select mi_calendario(current_setting('t.liga')::uuid) as tok \gset
select t_check(mi_calendario(current_setting('t.liga')::uuid) = :'tok', 'token estable');
set role anon;
select t_debe_fallar(format('select calendario_ics(%L)', :'tok'), 'el calendario no se pide directamente sin la función');
reset role;
select calendario_ics(:'tok') as ics \gset
select t_check(:'ics' like 'BEGIN:VCALENDAR%' and :'ics' like '%BEGIN:VEVENT%' and :'ics' like '%END:VCALENDAR%', 'ics del calendario');
select t_check(calendario_ics('x') is null and calendario_ics(repeat('a', 64)) is null, 'token inválido no da nada');
reset role;

-- ── Logros (retroactivos)
select t_check((select count(*) from logros where liga_id = current_setting('t.liga')::uuid) > 0, 'logros calculados con lo ya jugado');
select t_check(exists (select 1 from logros where tipo = 'primer_gol'), 'hay primer gol');
select t_check(exists (select 1 from notificaciones where tipo = 'logro'), 'avisos de logros al cerrar partidos');

-- ── Exportar
set role authenticated;
select t_como_uid(current_setting('t.admin')::uuid);
select exportar_liga(current_setting('t.liga')::uuid) as ex \gset
select t_check(jsonb_array_length(:'ex'::jsonb -> 'movimientos') > 0 and jsonb_array_length(:'ex'::jsonb -> 'saldos') > 0
               and jsonb_array_length(:'ex'::jsonb -> 'clasificacion') > 0, 'exportación completa');
select t_como_uid(current_setting('t.jug')::uuid);
select t_debe_fallar(format('select exportar_liga(%L)', current_setting('t.liga')), 'jugador no exporta');

-- ── Encuesta de fecha (opción múltiple)
select t_como_uid(current_setting('t.admin')::uuid);
select crear_encuesta(current_setting('t.liga')::uuid, '¿Qué día jugamos?', null, '["Lunes 21:00","Martes 21:00","Jueves 20:00"]',
                      now() + interval '2 days') as en \gset
select votar_encuesta(:'en', '{0,2}');
select t_como_uid(current_setting('t.jug')::uuid);
select votar_encuesta(:'en', '{2}');
select t_debe_fallar(format('select votar_votacion(%L, 0)', :'en'), 'en encuesta múltiple no se vota con una sola opción') ;
select t_check((votacion_resultados(:'en') -> 'votos' -> 2 ->> 'n')::int = 2
               and (votacion_resultados(:'en') -> 'votos' -> 0 ->> 'n')::int = 1, 'recuento múltiple');
select t_check(votacion_resultados(:'en') -> 'mis_opciones' = '[2]'::jsonb, 'mis opciones');
reset role;
update votaciones set cierra_en = now() - interval '1 minute' where id = :'en';
select cerrar_votaciones_vencidas();
select t_check((select ganadora from votaciones where id = :'en') = 2, 'gana el jueves');
\echo '══════ ESCENARIO EXTRAS COMPLETADO SIN ERRORES ══════'
