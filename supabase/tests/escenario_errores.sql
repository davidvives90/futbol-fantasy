\set ON_ERROR_STOP 1
reset role;
set role authenticated;
select t_como(301);
select registrar_error('Null check operator used on a null value', 'traza', '/partidos', '0.1.16');
select registrar_error('Null check operator used on a null value', 'traza', '/partidos', '0.1.16');
select t_debe_fallar('select count(*) from errores_app', 'un jugador no lee los errores');
select t_debe_fallar('select master_errores()', 'solo el máster ve los errores');
reset role;
select t_check((select veces from errores_app limit 1) = 2 and (select count(*) from errores_app) = 1, 'errores repetidos se cuentan');
set role anon;
select t_debe_fallar($$select registrar_error('x')$$, 'anon no registra');
reset role;
\echo '══════ ESCENARIO ERRORES COMPLETADO SIN ERRORES ══════'
