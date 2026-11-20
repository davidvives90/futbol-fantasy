\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.p', (select id::text from perfiles order by creado_en limit 1), false);
update perfiles set idioma = 'en' where id = current_setting('t.p')::uuid;
select notificar(array[current_setting('t.p')::uuid], null, 'prueba_idioma', 'Convocatoria abierta ⚽',
                 '¿Juegas el lun 24/11 21:00? Pulsa «Voy» para apuntarte');
select t_check((select titulo = 'Line-up open ⚽' and cuerpo = 'Playing on Mon 24/11 21:00? Tap "I''m in" to sign up'
                  from notificaciones where tipo = 'prueba_idioma' order by id desc limit 1), 'aviso traducido al inglés con el día');
update perfiles set idioma = 'eu' where id = current_setting('t.p')::uuid;
select notificar(array[current_setting('t.p')::uuid], null, 'prueba_idioma', 'Faltan 3 jugadores', 'Texto sin plantilla');
select t_check((select titulo = '3 jokalari falta dira' and cuerpo = 'Texto sin plantilla'
                  from notificaciones where tipo = 'prueba_idioma' order by id desc limit 1), 'euskera y texto sin plantilla intacto');
update perfiles set idioma = 'de' where id = current_setting('t.p')::uuid;
select notificar(array[current_setting('t.p')::uuid], null, 'prueba_idioma', '🏅 Hat-trick', 'Ana consigue «5 partidos sin perder»');
select t_check((select titulo = '🏅 Hattrick' and cuerpo = 'Ana erreicht „5 Spiele ungeschlagen“'
                  from notificaciones where tipo = 'prueba_idioma' order by id desc limit 1), 'logros traducidos');
update perfiles set idioma = 'es' where id = current_setting('t.p')::uuid;
select notificar(array[current_setting('t.p')::uuid], null, 'prueba_idioma', 'Convocatoria abierta ⚽', 'x');
select t_check((select titulo = 'Convocatoria abierta ⚽' from notificaciones where tipo = 'prueba_idioma' order by id desc limit 1),
               'castellano sin cambios');
select t_check((select count(*) from avisos_traducciones) = 50 * 8, 'plantillas cargadas');
\echo '══════ ESCENARIO IDIOMA COMPLETADO SIN ERRORES ══════'
