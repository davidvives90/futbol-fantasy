-- 0060 · Alineación sin roles, rendimiento en todas las ligas, cara a cara, equipo ideal, resumen y último aviso
\set ON_ERROR_STOP 1
\pset pager off
reset role;
-- Liga con más partidos cerrados y un jugador que haya jugado allí
select p.liga_id as lg from partidos p where p.estado = 'cerrado' group by p.liga_id order by count(*) desc limit 1 \gset
select pf.miembro_id as mj from puntos_fantasy pf join partidos p on p.id = pf.partido_id
 join miembros m on m.id = pf.miembro_id
 where p.liga_id = :'lg' and m.perfil_id is not null group by pf.miembro_id order by count(*) desc limit 1 \gset
select perfil_id as pj from miembros where id = :'mj' \gset
select set_config('request.jwt.claim.sub', :'pj', false);

-- Alineación libre cuando los roles no puntúan
update ligas set bonus_roles = true, modo_alineacion = 'tactico' where id = :'lg';
update ligas set bonus_roles = false where id = :'lg';
select t_check((select modo_alineacion from ligas where id = :'lg') = 'libre', 'sin roles: alineación libre');
update ligas set modo_alineacion = 'tactico' where id = :'lg';
select t_check((select modo_alineacion from ligas where id = :'lg') = 'libre', 'sin roles no se puede poner táctica');
update ligas set bonus_roles = true, modo_alineacion = 'tactico' where id = :'lg';
select t_check((select modo_alineacion from ligas where id = :'lg') = 'tactico', 'con roles sí táctica');

set role authenticated;
select rendimiento_perfil(:'mj') as rp \gset
select t_check(jsonb_array_length(:'rp'::jsonb -> 'ligas') >= 1, 'rendimiento: ligas');
select t_check((:'rp'::jsonb -> 'total' ->> 'partidos')::int
               = (select sum((x ->> 'partidos')::int) from jsonb_array_elements(:'rp'::jsonb -> 'ligas') x), 'rendimiento: total suma');

select cara_a_cara(:'mj') as cc \gset
select t_check(jsonb_array_length(:'cc'::jsonb) >= 1, 'cara a cara con datos');
select t_check((select bool_and((x ->> 'contra')::int = (x ->> 'v')::int + (x ->> 'e')::int + (x ->> 'd')::int)
                  from jsonb_array_elements(:'cc'::jsonb) x), 'cara a cara: V+E+D = partidos contra');

select equipo_ideal(:'lg', 'jornada') as ej \gset
select t_check(jsonb_array_length(:'ej'::jsonb -> 'jugadores') >= 1, 'equipo ideal de la jornada');
select t_check(jsonb_typeof(equipo_ideal(:'lg', 'mes') -> 'jugadores') = 'array', 'equipo ideal del mes');

select id as pc from partidos where liga_id = :'lg' and estado = 'cerrado' order by fecha_hora desc limit 1 \gset
select t_check(resumen_compartir(:'pc') ? 'mejor_nota', 'resumen con mejor nota');
reset role;

-- Último aviso: un partido en 3 horas con un dudoso
select set_config('request.jwt.claim.sub', :'pj', false);
insert into partidos (liga_id, fecha_hora, plazas, estado) values (:'lg', now() + interval '3 hours', 10, 'abierto')
returning id as pu \gset
insert into convocatorias (partido_id, miembro_id, estado) values (:'pu', :'mj', 'duda') on conflict (partido_id, miembro_id) do update set estado = 'duda';
select recordatorio_ultimo_aviso() as k \gset
select t_check(exists (select 1 from recordatorios_enviados where partido_id = :'pu' and tipo = 'ultimo_aviso'), 'último aviso enviado');
select t_check((select count(*) from notificaciones where perfil_id = :'pj' and cuerpo like 'El partido es a las%') >= 1, 'el dudoso recibe el aviso');
select recordatorio_ultimo_aviso() as k2 \gset
select t_check((select count(*) from recordatorios_enviados where partido_id = :'pu' and tipo = 'ultimo_aviso') = 1, 'solo una vez');
update partidos set estado = 'cancelado' where id = :'pu';
