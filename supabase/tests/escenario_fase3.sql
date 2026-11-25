-- 0055 · Fase 3: porra del partido
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select t_check(porra_retorno('sencilla', 10, false, '[{"cuota":2.5,"acierto":true}]') = 25, 'sencilla ganada');
select t_check(porra_retorno('combinada', 10, false, '[{"cuota":2,"acierto":true},{"cuota":3,"acierto":false}]') = 0, 'combinada: todo o nada');
select t_check(porra_retorno('combinada', 10, true, '[{"cuota":2,"acierto":true},{"cuota":3,"acierto":false}]') = 5, 'seguro: recuperas el 50 %');
select t_check(porra_retorno('sencilla', 10, true, '[{"cuota":3,"acierto":true}]') = 24, 'seguro: beneficio al 70 % (10 + 20 × 0,7)');
-- múltiple de 3: 3 parejas de 10/3; aciertan 2 → solo la pareja (2 × 2)
select t_check(porra_retorno('multiple', 9, false,
  '[{"cuota":2,"acierto":true},{"cuota":2,"acierto":true},{"cuota":5,"acierto":false}]') = 12, 'múltiple: cobras las parejas acertadas');

insert into auth.users (id, email) select t_uid(i), 'u' || i || '@test' from generate_series(1001, 1006) i;
insert into perfiles (id, nombre) select t_uid(i), 'P3 ' || i from generate_series(1001, 1006) i;
set role authenticated;
select t_como(1001);
select crear_liga('{"nombre":"Liga Porra","jugadores_por_equipo":3,"num_equipos":2}') as lp \gset
select set_config('t.liga', :'lp', false);
select codigo_invitacion as codp from ligas where id = :'lp' \gset
select set_config('t.codigo', :'codp', false);
do $$ begin
  for i in 1002..1006 loop perform t_como(i); perform unirse(current_setting('t.codigo')); end loop;
  perform t_como(1001);
  for i in 1002..1006 loop perform cambiar_rango(t_m(i), 'fijo'); end loop;
end $$;
select crear_partido(current_setting('t.liga')::uuid, '2027-08-01 20:00 Europe/Madrid', 0) as p \gset
select set_config('t.p', :'p', false);
select t_confirmar(:'p');
select t_debe_fallar(format($$select apostar(%L, 'sencilla', '[{"mercado":"1x2","seleccion":"1"}]', 10)$$, :'p'),
                     'sin activar la porra no se apuesta');
reset role;
update ligas set porra_activa = true, porra_max = 100 where id = :'lp';
set role authenticated;
select t_como(1001);
select t_debe_fallar(format($$select apostar(%L, 'sencilla', '[{"mercado":"1x2","seleccion":"1"}]', 10)$$, :'p'),
                     'antes de hacer equipos, cerrada');
select guardar_equipos(:'p', jsonb_build_object(t_m(1001), 1, t_m(1002), 1, t_m(1003), 1, t_m(1004), 2, t_m(1005), 2, t_m(1006), 2));
select t_check((porra_partido(:'p') ->> 'abierta')::boolean, 'con equipos hechos, abierta');
select t_check(jsonb_array_length(porra_partido(:'p') -> 'cuotas') = 3 + 6 + 6 + 6, 'cuotas: 1X2, marca, no marca y MVP');
reset role;
select t_check((select bool_and(cuota between 1.02 and 25) from porra_cuotas where partido_id = :'p'), 'cuotas entre 1,05 y 25');
select t_check(abs((select sum(prob) from porra_cuotas where partido_id = :'p' and mercado = '1x2') - 1) < 0.01, '1X2 suma 100 %');
set role authenticated;

select t_como(1002);
select apostar(:'p', 'sencilla', '[{"mercado":"1x2","seleccion":"1"}]', 20);
select apostar(:'p', 'combinada', jsonb_build_array(jsonb_build_object('mercado', '1x2', 'seleccion', '1'),
                                                    jsonb_build_object('mercado', 'goleador', 'seleccion', t_m(1001))), 10, true);
select t_debe_fallar(format($$select apostar(%L, 'combinada', '[{"mercado":"1x2","seleccion":"1"},{"mercado":"1x2","seleccion":"X"}]', 5)$$, :'p'),
                     'un solo 1-X-2 por boleto');
select t_debe_fallar(format($$select apostar(%L, 'sencilla', '[{"mercado":"1x2","seleccion":"2"}]', 80)$$, :'p'),
                     'tope de 100 por partido');
select t_como(1003);
select apostar(:'p', 'multiple', jsonb_build_array(jsonb_build_object('mercado', '1x2', 'seleccion', '1'),
                                                   jsonb_build_object('mercado', 'goleador', 'seleccion', t_m(1001)),
                                                   jsonb_build_object('mercado', 'goleador', 'seleccion', t_m(1004))), 30);
select t_como(1004);
select apostar(:'p', 'sencilla', '[{"mercado":"1x2","seleccion":"2"}]', 15) ->> 'id' as ap4 \gset
select cancelar_apuesta(:'ap4');
select apostar(:'p', 'sencilla', '[{"mercado":"1x2","seleccion":"2"}]', 15, true);
select t_como(1005);
select t_check(jsonb_array_length(porra_partido(:'p') -> 'todas') = 0, 'antes del partido no se ven los boletos de otros');

-- Juega: gana el equipo 1 (2-1), marca 1001 (y 1005 para el equipo 2)
select t_como(1001);
select marcar_jugado(:'p');
select enviar_post_partido(:'p', t_res(2, 1),
  jsonb_build_array(t_jug(1001, 2), t_jug(1002, 0), t_jug(1003, 0), t_jug(1004, 0), t_jug(1005, 1), t_jug(1006, 0)));
select cerrar_post_partido(:'p');
reset role;
select t_check((select estado from partidos where id = :'p') = 'cerrado', 'partido cerrado');
select t_check((select estado from apuestas a where partido_id = :'p' and miembro_id = t_m(1002) and tipo = 'sencilla') = 'ganada',
               'sencilla al 1 ganada');
select t_check((select retorno = round(importe * cuota_total, 2) from apuestas where partido_id = :'p' and miembro_id = t_m(1002)
                  and tipo = 'sencilla'), 'retorno = importe × cuota');
select t_check((select estado from apuestas where partido_id = :'p' and miembro_id = t_m(1002) and tipo = 'combinada') = 'ganada',
               'combinada con seguro ganada');
select t_check((select abs(retorno - (10 + (10 * cuota_total - 10) * 0.7)) < 0.1 from apuestas
                 where partido_id = :'p' and miembro_id = t_m(1002) and tipo = 'combinada'), 'seguro recorta el beneficio');
select t_check((select estado from apuestas where partido_id = :'p' and miembro_id = t_m(1003)) = 'parcial', 'múltiple: parcial');
select t_check((select retorno from apuestas where partido_id = :'p' and miembro_id = t_m(1004)) = 7.5, 'pierde con seguro: recupera 7,5');
select t_check(jsonb_array_length(ranking_porra(:'lp')) = 3, 'ranking de pronosticadores');

-- Porra con dinero Fantasy
update ligas set porra_modo = 'dinero', fantasy_activo = true, porra_max = null where id = :'lp';
set role authenticated;
select t_como(1001);
select entrar_fantasy(current_setting('t.liga')::uuid);
select crear_partido(current_setting('t.liga')::uuid, '2027-08-08 20:00 Europe/Madrid', 0) as q \gset
select t_confirmar(:'q');
select guardar_equipos(:'q', jsonb_build_object(t_m(1001), 1, t_m(1002), 1, t_m(1003), 1, t_m(1004), 2, t_m(1005), 2, t_m(1006), 2));
reset role;
update fantasy_managers set saldo = 100 where miembro_id = t_m(1001);
set role authenticated;
select t_como(1001);
select (select saldo from fantasy_managers where miembro_id = t_m(1001)) as s0 \gset
select apostar(:'q', 'sencilla', '[{"mercado":"1x2","seleccion":"X"}]', 4);
select t_check((select saldo from fantasy_managers where miembro_id = t_m(1001)) = :'s0'::numeric - 4, 'dinero: se descuenta');
select t_debe_fallar(format($$select apostar(%L, 'sencilla', '[{"mercado":"1x2","seleccion":"1"}]', 2)$$, :'q'),
                     'dinero: tope = una décima parte del valor base (5 M)');
reset role;
update partidos set estado = 'cancelado' where id = :'q';
select t_check((select saldo from fantasy_managers where miembro_id = t_m(1001)) = :'s0'::numeric, 'cancelado: se devuelve');
select t_check((select estado from apuestas where partido_id = :'q') = 'anulada', 'boleto anulado');
\echo '══════ ESCENARIO FASE 3 COMPLETADO SIN ERRORES ══════'
