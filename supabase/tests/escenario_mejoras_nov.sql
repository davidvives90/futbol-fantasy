-- 0059 · Subasta de un jugador propio, Fantasy sencillo, porra y menores, versión mínima y exportar datos
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Porra'), false);
select current_setting('t.liga') as lp \gset

-- Mercado abierto: sin partidos pendientes en la liga
update partidos set estado = 'cancelado' where liga_id = :'lp' and estado not in ('cerrado', 'cancelado');
select t_check(mercado_abierto(:'lp'), 'mercado abierto');

-- 1002 entra en el Fantasy; 1001 tiene un jugador (1005) con ficha propia
set role authenticated;
select t_como(1002);
select entrar_fantasy(:'lp'::uuid);
reset role;
select asegurar_fichas(:'lp'::uuid);
update fichas set propietario_id = null where liga_id = :'lp' and propietario_id = t_m(1002) and jugador_id = t_m(1005);
update fantasy_managers set saldo = 200 where liga_id = :'lp' and miembro_id in (t_m(1001), t_m(1002));
select f.id as fid from fichas f where f.liga_id = :'lp' and f.jugador_id = t_m(1005)
   and (f.propietario_id is null or f.propietario_id = t_m(1001)) order by f.propietario_id nulls last limit 1 \gset
select transferir_ficha(:'fid', t_m(1001), 10);
select t_check((select propietario_id from fichas where id = :'fid') = t_m(1001), '1001 tiene a 1005');

set role authenticated;
select t_como(1002);
select t_debe_fallar(format($$select poner_en_subasta(%L, 10, 24)$$, :'fid'), 'no puedes subastar un jugador ajeno');
select t_como(1001);
select t_debe_fallar(format($$select poner_en_subasta(%L, 10, 5)$$, :'fid'), 'duración 12, 24 o 48 h');
select poner_en_subasta(:'fid', 20, 24) as sid \gset
select t_check((select vendedor_id from subastas where id = :'sid') = t_m(1001), 'subasta con vendedor');
select t_debe_fallar(format($$select poner_en_subasta(%L, 20, 24)$$, :'fid'), 'no dos subastas a la vez');
select t_debe_fallar(format($$select pujar(%L, 25)$$, :'sid'), 'el vendedor no puja');
select t_check((select bool_or((x ->> 'vendedor_id')::uuid = t_m(1001)) from jsonb_array_elements(subastas_liga(:'lp')) x),
               'la lista de subastas trae el vendedor');
select t_como(1002);
select t_debe_fallar(format($$select pujar(%L, 15)$$, :'sid'), 'puja mínima = precio de salida');
select pujar(:'sid', 30);
select t_como(1001);
select t_debe_fallar(format($$select cancelar_mi_subasta(%L)$$, :'sid'), 'con pujas no se cancela');
reset role;
select saldo as s1 from fantasy_managers where liga_id = :'lp' and miembro_id = t_m(1001) \gset
update subastas set cierra_en = now() - interval '1 minute' where id = :'sid';
select resolver_subastas(:'lp');
select t_check((select estado from subastas where id = :'sid') = 'adjudicada', 'subasta adjudicada');
select t_check((select propietario_id from fichas where id = :'fid') = t_m(1002), 'el jugador pasa al comprador');
select t_check((select saldo from fantasy_managers where liga_id = :'lp' and miembro_id = t_m(1001)) = :'s1'::numeric + 30,
               'el vendedor cobra la puja');
select t_check((select saldo from fantasy_managers where liga_id = :'lp' and miembro_id = t_m(1002)) = 170, 'el comprador paga');

-- Sin pujas: queda desierta y sigue siendo suyo; cancelar sin pujas
set role authenticated;
select t_como(1002);
select poner_en_subasta(:'fid', 50, 12) as sid2 \gset
select cancelar_mi_subasta(:'sid2');
select t_check((select estado from subastas where id = :'sid2') = 'cancelada', 'cancelar sin pujas');
select poner_en_subasta(:'fid', 50, 12) as sid3 \gset
reset role;
update subastas set cierra_en = now() - interval '1 minute' where id = :'sid3';
select resolver_subastas(:'lp');
select t_check((select estado from subastas where id = :'sid3') = 'desierta', 'sin pujas: desierta');
select t_check((select propietario_id from fichas where id = :'fid') = t_m(1002), 'sin pujas: sigue siendo suyo');
-- Vender al mercado con una subasta abierta la cancela
set role authenticated;
select t_como(1002);
select poner_en_subasta(:'fid', 50, 12) as sid4 \gset
select vender_ficha(:'fid');
select t_check((select estado from subastas where id = :'sid4') = 'cancelada', 'vender cancela la subasta');

-- Fantasy sencillo
select t_como(1002);
select t_debe_fallar(format($$select fantasy_modo_sencillo(%L, true)$$, :'lp'), 'solo el admin');
reset role;
select perfil_id as admin from miembros where liga_id = :'lp' and rol = 'admin' limit 1 \gset
select set_config('request.jwt.claim.sub', :'admin', false);
set role authenticated;
select fantasy_modo_sencillo(:'lp', true);
reset role;
select t_check((select fantasy_sencillo and modo_alineacion = 'libre' and not bonus_roles and not ariete_activo
                       and not cesiones_activas and suplentes >= 1 from ligas where id = :'lp'), 'modo sencillo aplicado');

-- Porra: interruptor general y menores
update ligas set porra_activa = false where id = :'lp';
update config_app set porra_global = false;
select t_debe_fallar(format($$update ligas set porra_activa = true where id = %L$$, :'lp'), 'interruptor general apagado');
update config_app set porra_global = true;
update perfiles set fecha_nacimiento = current_date - interval '16 years' where id = t_uid(1006);
select t_check(liga_con_menores(:'lp'), 'liga con un menor');
select t_debe_fallar(format($$update ligas set porra_activa = true where id = %L$$, :'lp'), 'con menores no se activa');
update perfiles set fecha_nacimiento = current_date - interval '30 years' where id = t_uid(1006);
update ligas set porra_activa = true where id = :'lp';
select t_check((select porra_activa from ligas where id = :'lp'), 'sin menores sí se activa');
update perfiles set fecha_nacimiento = current_date - interval '16 years' where id = t_uid(1006);
set role authenticated;
select t_como(1001);
select crear_partido(:'lp'::uuid, now() + interval '3 days', 0) as q2 \gset
reset role;
select t_check(not porra_abierta(:'q2'), 'si entra un menor, la porra se cierra');
set role authenticated;
select t_como(1001);
select t_check(porra_partido(:'q2') ->> 'motivo' = 'menores', 'motivo: menores');
reset role;
update perfiles set fecha_nacimiento = null where id = t_uid(1006);

-- Configuración pública (también sin sesión)
set role anon;
select t_check((config_app_publica() ->> 'version_minima_android')::int >= 0, 'versión mínima accesible sin sesión');
reset role;

-- Exportar mis datos
set role authenticated;
select t_como(1001);
select exportar_mis_datos() as datos \gset
select t_check((:'datos'::jsonb -> 'perfil' ->> 'id') = t_uid(1001)::text, 'exportar: perfil');
select t_check(jsonb_array_length(:'datos'::jsonb -> 'ligas') >= 1, 'exportar: ligas');
reset role;
select t_check((select count(*) from politicas where version = '2026-11-26') = 1, 'nueva política publicada');
