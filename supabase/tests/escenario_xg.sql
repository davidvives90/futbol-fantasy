\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);
select p.id as px from partidos p where p.liga_id = current_setting('t.liga')::uuid
   and exists (select 1 from convocatorias c where c.partido_id = p.id and c.equipo is not null)
 order by p.fecha_hora desc limit 1 \gset
set role authenticated;
select t_como(302);
select prediccion_partido(:'px') as pred \gset
\echo :pred
select t_check((:'pred'::jsonb -> 'encuentros' -> 0 ->> 'xg_local')::numeric > 0, 'hay goles esperados del equipo local');
select t_check(abs((select (e->>'prob_local')::int + (e->>'prob_empate')::int + (e->>'prob_visitante')::int
                      from jsonb_array_elements(:'pred'::jsonb -> 'encuentros') e limit 1) - 100) <= 2,
               'las probabilidades suman ~100 %');
select t_check(jsonb_array_length(:'pred'::jsonb -> 'encuentros' -> 0 -> 'jugadores') >= 6, 'xG por jugador');
reset role;
update ligas set prediccion_activa = false where id = current_setting('t.liga')::uuid;
set role authenticated;
select t_check(prediccion_partido(:'px') is null, 'desactivada en ajustes: no hay predicción');
reset role;
update ligas set prediccion_activa = true where id = current_setting('t.liga')::uuid;
set role anon;
select t_debe_fallar(format('select prediccion_partido(%L)', :'px'), 'anon no la ve');
reset role;
\echo '══════ ESCENARIO XG COMPLETADO SIN ERRORES ══════'
