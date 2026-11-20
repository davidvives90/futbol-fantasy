\set ON_ERROR_STOP 1
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);
set role authenticated;
select t_como(301);
update ligas set equipaciones = '[{"nombre":"Blanco","color":"#FFFFFF"},{"nombre":"Rojo","color":"#C62828"}]', normas = 'Puntualidad: 5 min antes.'
 where id = current_setting('t.liga')::uuid;
select t_check((select equipaciones -> 1 ->> 'nombre' from ligas where id = current_setting('t.liga')::uuid) = 'Rojo', 'admin cambia equipaciones');
select t_debe_fallar(format('update ligas set equipaciones = %L where id = %L', '[]', current_setting('t.liga')), 'mínimo 2 equipaciones');
select t_como(302);
update ligas set normas = 'hackeado' where id = current_setting('t.liga')::uuid;
select t_check((select normas from ligas where id = current_setting('t.liga')::uuid) = 'Puntualidad: 5 min antes.', 'un jugador no cambia las normas');
reset role;
\echo '══════ ESCENARIO EQUIPACIONES/NORMAS COMPLETADO SIN ERRORES ══════'
