\set ON_ERROR_STOP 1
reset role;
set role authenticated;
select t_como(301);
update perfiles set fecha_nacimiento = '1990-05-10' where id = t_uid(301);
select t_check((select fecha_nacimiento from perfiles where id = t_uid(301)) = '1990-05-10', 'guardar fecha de nacimiento');
select t_debe_fallar(format('update perfiles set fecha_nacimiento = %L where id = %L', current_date, t_uid(301)), 'fecha imposible');
select t_check((select count(*) from perfiles where fecha_nacimiento is not null) >= 1, 'los compañeros la leen');
reset role;
\echo '══════ ESCENARIO PERFIL COMPLETADO SIN ERRORES ══════'
