\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);
select set_config('t.admin', (select perfil_id::text from miembros where liga_id = current_setting('t.liga')::uuid and rol = 'admin'
                                and estado = 'activo' and perfil_id not in (select perfil_id from masters) limit 1), false);
select set_config('t.jug', (select perfil_id::text from miembros where liga_id = current_setting('t.liga')::uuid and rol = 'jugador'
                              and estado = 'activo' and perfil_id is not null limit 1), false);
select set_config('t.mjug', (select id::text from miembros where perfil_id = current_setting('t.jug')::uuid
                               and liga_id = current_setting('t.liga')::uuid), false);
set role authenticated;
select t_como_uid(current_setting('t.jug')::uuid);
select t_debe_fallar($$select eliminar_mi_cuenta('si')$$, 'pide confirmación escrita');
select eliminar_mi_cuenta('ELIMINAR');
reset role;
select t_check(not exists (select 1 from perfiles where id = current_setting('t.jug')::uuid), 'perfil borrado');
select t_check((select perfil_id is null and nombre_provisional = 'Exjugador' and estado = 'abandonado' from miembros
                 where id = current_setting('t.mjug')::uuid), 'historial anónimo conservado');
select t_check((select count(*) from puntos_fantasy where miembro_id = current_setting('t.mjug')::uuid) > 0, 'sus puntos siguen');
-- el único admin no puede irse dejando la liga huérfana
update miembros set rol = 'jugador' where liga_id = current_setting('t.liga')::uuid and rol = 'admin'
   and perfil_id is distinct from current_setting('t.admin')::uuid;
set role authenticated;
select t_como_uid(current_setting('t.admin')::uuid);
select t_debe_fallar($$select eliminar_mi_cuenta('ELIMINAR')$$, 'único admin no puede eliminarse');
reset role;
\echo '══════ ESCENARIO ELIMINAR CUENTA COMPLETADO SIN ERRORES ══════'
