-- 0063 · Porra por módulos, actividad, participación del parte y resumen de la jornada
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Porra'), false);
select current_setting('t.liga') as lp \gset
select perfil_id as adm from miembros where liga_id = :'lp' and rol = 'admin' limit 1 \gset

-- Módulos: solo el admin; quitar el seguro y las combinadas
set role authenticated;
select t_como(1002);
select t_debe_fallar(format($$select porra_modulos_liga(%L, '{"seguro": false}')$$, :'lp'), 'solo el admin cambia los módulos');
reset role;
select set_config('request.jwt.claim.sub', :'adm', false);
set role authenticated;
select porra_modulos_liga(:'lp', '{"seguro": false, "combinadas": false, "inventado": true}');
reset role;
select t_check((select not (porra_modulos ->> 'seguro')::boolean and not (porra_modulos ->> 'combinadas')::boolean
                       and (porra_modulos ->> '1x2')::boolean and not porra_modulos ? 'inventado' from ligas where id = :'lp'),
               'módulos guardados');
-- Un partido con porra abierta
update partidos set estado = 'cancelado' where liga_id = :'lp' and estado not in ('cerrado', 'cancelado');
update perfiles set fecha_nacimiento = null where id in (select perfil_id from miembros where liga_id = :'lp');
update ligas set porra_activa = true, porra_modo = 'dinero' where id = :'lp';
set role authenticated;
select t_como(1001);
select crear_partido(:'lp'::uuid, now() + interval '2 days', 0) as pm \gset
reset role;
insert into convocatorias (partido_id, miembro_id, estado, equipo)
select :'pm', m.id, 'confirmado', case when row_number() over (order by m.id) % 2 = 0 then 1 else 2 end
  from miembros m where m.liga_id = :'lp' and m.estado = 'activo'
on conflict (partido_id, miembro_id) do update set estado = 'confirmado', equipo = excluded.equipo;
update partidos set estado = 'equipos_hechos' where id = :'pm';
update fantasy_managers set saldo = 100 where liga_id = :'lp' and miembro_id = t_m(1001);
set role authenticated;
select t_como(1001);
select porra_partido(:'pm') is not null;
select t_debe_fallar(format($$select apostar(%L, 'sencilla', '[{"mercado":"1x2","seleccion":"1"}]', 1, true)$$, :'pm'),
                     'seguro desactivado');
select apostar(:'pm', 'sencilla', '[{"mercado":"1x2","seleccion":"1"}]', 1, false);
reset role;
select set_config('request.jwt.claim.sub', :'adm', false);
set role authenticated;
select porra_modulos_liga(:'lp', '{"goleador": false}');
select t_como(1001);
select t_debe_fallar(format($$select apostar(%L, 'sencilla', (select jsonb_build_array(jsonb_build_object('mercado','goleador','seleccion',seleccion)) from porra_cuotas where partido_id = %L and mercado = 'goleador' limit 1), 1, false)$$, :'pm', :'pm'),
                     'goleador desactivado');
select t_check(jsonb_typeof(actividad_fantasy(:'lp')) = 'array', 'actividad del Fantasy');
reset role;
select set_config('request.jwt.claim.sub', :'adm', false);
set role authenticated;
select porra_modulos_liga(:'lp', '{"seguro": true, "combinadas": true, "goleador": true}');
reset role;

-- Participación y resumen en un partido cerrado
select p.id as pc from partidos p where p.estado = 'cerrado' order by fecha_hora desc limit 1 \gset
select l.perfil_id as uj from partidos p join miembros l on l.liga_id = p.liga_id and l.perfil_id is not null where p.id = :'pc' limit 1 \gset
select set_config('request.jwt.claim.sub', :'uj', false);
set role authenticated;
select t_check((participacion_post_partido(:'pc') ->> 'jugadores')::int >= 0, 'participación');
select t_check(jsonb_typeof(resumen_jornada(:'pc') -> 'jugadores') = 'array', 'resumen de la jornada');
select t_debe_fallar(format($$select recordar_votar(%L)$$, :'pc'), 'no se recuerda con la votación cerrada');
reset role;
