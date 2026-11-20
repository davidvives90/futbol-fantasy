\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);
set role authenticated;
select t_como(301);
select estadisticas_jugador(t_m(301)) as ej \gset
\echo :ej
select t_check(length(:'ej'::jsonb ->> 'forma') between 1 and 5, 'forma de los últimos partidos');
select t_check((:'ej'::jsonb -> 'mas_juega_con' ->> 'partidos')::int >= 1, 'con quién juega más');
select estadisticas_liga(current_setting('t.liga')::uuid) as el \gset
\echo :el
select t_check((:'el'::jsonb ->> 'partidos')::int >= 3 and jsonb_array_length(:'el'::jsonb -> 'mas_fieles') >= 1, 'resumen de la liga');
reset role;
set role anon;
select t_debe_fallar(format('select estadisticas_liga(%L)', current_setting('t.liga')), 'anon no ve estadísticas');
reset role;
\echo '══════ ESCENARIO ESTADÍSTICAS COMPLETADO SIN ERRORES ══════'
