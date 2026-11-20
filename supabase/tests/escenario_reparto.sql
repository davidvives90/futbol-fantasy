-- Escenario 0027 · Reparto inicial compensado, dinero 1,5 × precio medio, protección de 7 días, reinicio
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select l.id as lf from ligas l where l.presupuesto_inicial is not null
   and (select count(*) from miembros m where m.liga_id = l.id and m.estado = 'activo' and m.perfil_id is not null) >= 4
 order by (select count(*) from mercado_jugador mj where mj.liga_id = l.id) desc limit 1 \gset
select t_check(:'lf' is not null, 'hay una liga con Fantasy');
update ligas set reparto_inicial = 5, factor_presupuesto = 1.5, proteccion_dias = 7, max_plantilla = 6 where id = :'lf';
select reiniciar_fantasy(:'lf') as managers \gset
select t_check(:managers >= 4, 'reinicio: un mánager por cada miembro registrado');
select t_check((select bool_and(n = least(l.reparto_inicial, l.max_plantilla))
                  from (select fm.miembro_id, count(f.id) n from fantasy_managers fm
                          left join fichas f on f.propietario_id = fm.miembro_id and f.liga_id = fm.liga_id
                         where fm.liga_id = :'lf' group by fm.miembro_id) t, ligas l where l.id = :'lf'),
               'cada mánager recibe 5 jugadores');
select t_check((select bool_and(saldo = presupuesto_liga(:'lf')) from fantasy_managers where liga_id = :'lf'),
               'dinero inicial = 1,5 × precio medio');
select t_check(presupuesto_liga(:'lf') < 4 * (select avg(precio) from mercado_jugador where liga_id = :'lf'),
               'el dinero inicial es bajo (antes 6,5 × precio medio)');
\echo 'Valor de cada equipo repartido:'
select fm.miembro_id, sum(mj.precio) valor, count(*) filter (where mj.no_habitual) invitados
  from fantasy_managers fm join fichas f on f.propietario_id = fm.miembro_id and f.liga_id = fm.liga_id
  join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
 where fm.liga_id = :'lf' group by fm.miembro_id;
select t_check((select max(v) - min(v) <= 0.35 * avg(v) from (select sum(mj.precio) v
                  from fichas f join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
                 where f.liga_id = :'lf' and f.propietario_id is not null group by f.propietario_id) t),
               'equipos compensados (diferencia de valor < 35 % de la media)');
select t_check((select coalesce(max(n), 0) <= 1 from (select count(*) n from fichas f join mercado_jugador mj
                  on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
                 where f.liga_id = :'lf' and f.propietario_id is not null and mj.no_habitual group by f.propietario_id) t),
               'como mucho un invitado por equipo');
select t_check((select count(*) from fichas where liga_id = :'lf' and propietario_id is null) > 0,
               'quedan fichas libres en el mercado');
select t_check((select bool_and(protegida_hasta between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour'
                                and protegida_jornadas = 1)
                  from fichas where liga_id = :'lf' and propietario_id is not null),
               'los jugadores repartidos quedan protegidos 7 días');
-- el cierre de jornada (decremento) no quita la protección antes de tiempo
update fichas set protegida_jornadas = protegida_jornadas - 1 where liga_id = :'lf' and protegida_jornadas > 0;
select t_check((select bool_and(protegida_jornadas = 1) from fichas where liga_id = :'lf' and propietario_id is not null),
               'la protección se mantiene aunque se cierre una jornada');
update fichas set protegida_hasta = now() - interval '1 minute' where liga_id = :'lf' and propietario_id is not null;
select t_check(caducar_protecciones() > 0, 'caducan las protecciones vencidas');
select t_check(not exists (select 1 from fichas where liga_id = :'lf' and protegida_jornadas > 0),
               'pasados los 7 días la protección caduca');
\echo '══════ ESCENARIO REPARTO COMPLETADO SIN ERRORES ══════'
