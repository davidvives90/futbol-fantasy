-- 0062 · Alineación sin capitán/ariete y equipos con registro de quién los confirma
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Porra'), false);
select current_setting('t.liga') as lp \gset
update ligas set ariete_activo = true, capitan_activo = true, modo_alineacion = 'libre' where id = :'lp';
update partidos set estado = 'cancelado' where liga_id = :'lp' and estado not in ('cerrado', 'cancelado');
set role authenticated;
select t_como(1001);
select crear_partido(:'lp'::uuid, now() + interval '3 days', 0) as pa \gset
reset role;
update ligas set horas_cierre_alineacion = 1 where id = :'lp';
select array_agg(f.jugador_id) as js from fichas f where f.liga_id = :'lp' and f.propietario_id = t_m(1001) \gset
select t_check(:'js' is not null, '1001 tiene jugadores');
set role authenticated;
select t_como(1001);
-- Sin capitán ni ariete (antes fallaba)
select guardar_alineacion(:'pa', (select array_agg(x) from (select unnest(:'js'::uuid[]) x limit 1) t), null, null, null, '{}');
-- Con ariete y capitán el mismo jugador
select guardar_alineacion(:'pa', (select array_agg(x) from (select unnest(:'js'::uuid[]) x limit 1) t), null,
                          (:'js'::uuid[])[1], (:'js'::uuid[])[1], '{}');
reset role;
select t_check((select bool_and(capitan and ariete) from alineaciones where partido_id = :'pa' and manager_id = t_m(1001)),
               'capitán y ariete guardados');
select t_check((select count(*) from alineaciones where partido_id = :'pa' and (capitan is null or ariete is null)) = 0, 'sin nulos');
