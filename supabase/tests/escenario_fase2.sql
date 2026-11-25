-- 0054 · Fase 2: escala 50 M, copias, reparto pagado, capitán/ariete/suplentes, jornadas especiales,
-- subastas, draft y herencia de temporada
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select t_check((select count(*) from ligas where valor_base <> 50) = 0, 'todas las ligas en escala 50 M');
select t_check((select count(*) from ligas where max_plantilla < jugadores_por_equipo + 1) = 0, 'plantilla ≥ alineación + 1');

insert into auth.users (id, email) select t_uid(i), 'u' || i || '@test' from generate_series(901, 912) i;
insert into perfiles (id, nombre, posicion)
select t_uid(i), 'F2 ' || i, (array['portero','defensa','defensa','medio','delantero','portero','defensa','medio','medio','delantero','medio','defensa'])[i - 900]::posicion_campo
  from generate_series(901, 912) i;
set role authenticated;
select t_como(901);
select crear_liga('{"nombre":"Liga Fase2","jugadores_por_equipo":5,"num_equipos":2}') as lf \gset
select set_config('t.liga', :'lf', false);
select codigo_invitacion as codf from ligas where id = :'lf' \gset
select set_config('t.codigo', :'codf', false);
do $$ begin
  for i in 902..911 loop perform t_como(i); perform unirse(current_setting('t.codigo')); end loop;
  perform t_como(901);
  for i in 902..910 loop perform cambiar_rango(t_m(i), 'fijo'); end loop;
end $$;
reset role;
update ligas set fantasy_activo = true where id = :'lf';
select t_check(presupuesto_liga(:'lf') = 260, 'presupuesto F5 = 260 M');
set role authenticated;

-- ═════════ Reparto pagado del presupuesto
do $$ begin
  for i in 901..904 loop perform t_como(i); perform entrar_fantasy(current_setting('t.liga')::uuid); end loop;
end $$;
reset role;
select t_check((select count(*) from fantasy_managers where liga_id = :'lf') = 4, '4 mánagers');
select t_check((select bool_and(n = 5) from (select count(*) n from fichas where liga_id = :'lf' and propietario_id is not null
                                              group by propietario_id) x), 'reparto: 5 jugadores cada uno');
select t_check((select bool_and(saldo >= 0 and saldo < 260) from fantasy_managers where liga_id = :'lf'),
               'el reparto se paga del presupuesto');
select t_check((select copias_por_jugador from ligas where id = :'lf') = ceil(4 * 6 / 11.0), 'copias = ⌈M·(N+1)/P⌉');
select t_check((select count(*) from fichas where liga_id = :'lf') >= 4 * 6, 'copias suficientes para alineación + 1');
select t_check((select bool_and(x.precio between 40 and 60) from mercado_jugador x where liga_id = :'lf'), 'precios ~50 M');

-- ═════════ Rareza e inflación
update ligas set modo_copias = 'rareza', inflacion_escasez = true where id = :'lf';
with f as (select f.id, mj.precio from fichas f join mercado_jugador mj on mj.miembro_id = f.jugador_id
            where f.liga_id = :'lf' and f.numero = 1 and f.propietario_id is null limit 1)
select t_check((select precio_ficha(id) between precio * 1.5 - 0.05 and precio * 1.5 * 1.4 from f), 'copia única ×1,5 (+ escasez)');
update ligas set modo_copias = 'clasico', inflacion_escasez = false where id = :'lf';

-- ═════════ Alineación: capitán ×2, ariete +3, suplente que entra
-- 901 tiene exactamente: 902 (POR), 903, 904, 905 (DEL), 911 (no juega) y 907 de suplente
update fichas set propietario_id = null, precio_compra = null, clausula = null where propietario_id = t_m(901);
update fichas f set propietario_id = t_m(901), precio_compra = 50, clausula = 75
 where f.liga_id = :'lf' and f.numero = 1
   and f.jugador_id in (t_m(902), t_m(903), t_m(904), t_m(905), t_m(911), t_m(907));
set role authenticated;
select t_como(901);
select crear_partido(current_setting('t.liga')::uuid, '2027-07-01 20:00 Europe/Madrid', 0) as p \gset
select set_config('t.p', :'p', false);
select t_debe_fallar(format($$select guardar_alineacion(%L, array[t_m(902), t_m(903), t_m(904), t_m(905)],
  array['POR','MED','MED','MED'])$$, :'p'), 'táctica: con 4 hace falta defensa y delantero');
select t_debe_fallar(format($$select guardar_alineacion(%L, array[t_m(902)], array['POR'], p_capitan => t_m(903))$$, :'p'),
                     'capitán fuera de los titulares');
select guardar_alineacion(:'p', array[t_m(902), t_m(903), t_m(904), t_m(905), t_m(911)],
                          array['POR', 'DEF', 'MED', 'DEL', 'DEL'], t_m(902), t_m(905), array[t_m(907)]);
select fijar_evento_especial(:'p', 'goles_dobles');
reset role;
update convocatorias set estado = 'baja' where partido_id = :'p' and miembro_id = t_m(911);
set role authenticated;
select t_como(901);
select t_confirmar(:'p');
reset role;
update convocatorias set estado = 'baja' where partido_id = :'p' and miembro_id = t_m(911);
set role authenticated;
select t_como(901);
select guardar_equipos(:'p', jsonb_build_object(t_m(901), 1, t_m(902), 1, t_m(903), 1, t_m(904), 1, t_m(905), 1,
                                                 t_m(906), 2, t_m(907), 2, t_m(908), 2, t_m(909), 2, t_m(910), 2));
select marcar_jugado(:'p');
select enviar_post_partido(:'p', t_res(2, 1),
  jsonb_build_array(t_jug(901, 0), t_jug(902, 0), t_jug(903, 0), t_jug(904, 0), t_jug(905, 2),
                    t_jug(906, 1), t_jug(907, 0), t_jug(908, 0), t_jug(909, 0), t_jug(910, 0)));
select cerrar_post_partido(:'p');
reset role;
select t_check((select estado from partidos where id = :'p') = 'cerrado', 'partido cerrado');
select t_check((select (desglose ->> 'goles')::numeric from puntos_fantasy where partido_id = :'p' and miembro_id = t_m(905))
               = 2 * 2 * regla(:'lf', 'gol'), 'goles dobles en la jornada especial');
select t_check((select jornada_liquidada from partidos where id = :'p'), 'jornada liquidada');
with d as (select x from puntos_manager pm, jsonb_array_elements(pm.desglose) x where pm.partido_id = :'p' and pm.manager_id = t_m(901))
select t_check((select (x ->> 'entra_por') from d where x ->> 'jugador_id' = t_m(907)::text) = t_m(911)::text, 'el suplente entra por el que no jugó');
with d as (select x from puntos_manager pm, jsonb_array_elements(pm.desglose) x where pm.partido_id = :'p' and pm.manager_id = t_m(901))
select t_check((select (x ->> 'total')::numeric from d where x ->> 'jugador_id' = t_m(902)::text)
               = 2 * ((select total from puntos_fantasy where partido_id = :'p' and miembro_id = t_m(902))
                      + (select bonus_rol from alineaciones where partido_id = :'p' and manager_id = t_m(901) and jugador_id = t_m(902))),
               'capitán ×2');
with d as (select x from puntos_manager pm, jsonb_array_elements(pm.desglose) x where pm.partido_id = :'p' and pm.manager_id = t_m(901))
select t_check((select (x ->> 'ariete')::boolean from d where x ->> 'jugador_id' = t_m(905)::text), 'ariete marcó: +3');
select t_check((select puntos from puntos_manager where partido_id = :'p' and manager_id = t_m(901))
               = (select sum((x ->> 'total')::numeric) from puntos_manager pm, jsonb_array_elements(pm.desglose) x
                   where pm.partido_id = :'p' and pm.manager_id = t_m(901) and (x ->> 'cuenta')::boolean),
               'puntos del mánager = suma de los que cuentan');

-- ═════════ Subasta abierta con anti-sniping
update ligas set modo_inicio = 'subasta', subasta_tipo = 'abierta' where id = :'lf';
set role authenticated;
select t_como(902);
select t_debe_fallar(format($$select lanzar_subasta(%L)$$, current_setting('t.liga')), 'solo el admin lanza subastas');
select t_como(901);
select t_check(lanzar_subasta(current_setting('t.liga')::uuid) = 1, 'sale 1 subasta');
select t_debe_fallar(format($$select comprar_ficha(%L, t_m(910))$$, current_setting('t.liga')), 'en modo subasta no se compra directo');
reset role;
select id as s, precio_salida as salida, jugador_id as sj from subastas where liga_id = :'lf' and estado = 'abierta' \gset
-- que nadie tenga ya a ese jugador entre los que pujan
update fichas set propietario_id = null where liga_id = :'lf' and jugador_id = :'sj' and propietario_id in (t_m(902), t_m(903));
update fantasy_managers set saldo = 500 where liga_id = :'lf' and miembro_id in (t_m(902), t_m(903));
update subastas set cierra_en = now() + interval '1 minute' where id = :'s';
set role authenticated;
select t_como(902);
select pujar(:'s', :'salida');
select t_debe_fallar(format($$select pujar(%L, %s)$$, :'s', :'salida'), 'el que va ganando no repuja');
select t_como(903);
select t_debe_fallar(format($$select pujar(%L, %s)$$, :'s', :'salida'), 'hay que superar la mejor puja');
select pujar(:'s', :'salida'::numeric + 5);
reset role;
select t_check((select cierra_en > now() + interval '90 seconds' from subastas where id = :'s'), 'anti-sniping: +2 min');
update subastas set cierra_en = now() - interval '1 second' where id = :'s';
select resolver_subastas(:'lf');
select t_check((select ganador_id from subastas where id = :'s') = t_m(903), 'gana la puja más alta');
select t_check(exists (select 1 from fichas where propietario_id = t_m(903) and jugador_id = :'sj'), 'la ficha pasa al ganador');
select t_check((select clausula from fichas where propietario_id = t_m(903) and jugador_id = :'sj')
               >= round((:'salida'::numeric + 5) * 1.5, 2), 'cláusula = 150 % de lo pagado');

-- Subasta ciega: no se ve la mejor puja
update ligas set subasta_tipo = 'ciega' where id = :'lf';
set role authenticated;
select t_como(901);
select lanzar_subasta(current_setting('t.liga')::uuid);
select t_check((select bool_and(x ->> 'mejor' is null) from jsonb_array_elements(subastas_liga(current_setting('t.liga')::uuid)) x
                where (x ->> 'abierta')::boolean and x ->> 'tipo' = 'ciega'), 'ciega: la mejor puja no se ve');

-- ═════════ Draft en otra liga
select t_como(905);
select crear_liga('{"nombre":"Liga Draft","jugadores_por_equipo":3,"num_equipos":2}') as ld \gset
select set_config('t.ld', :'ld', false);
select codigo_invitacion as codd from ligas where id = :'ld' \gset
select set_config('t.codd', :'codd', false);
do $$ begin
  for i in 906..911 loop perform t_como(i); perform unirse(current_setting('t.codd')); end loop;
end $$;
reset role;
update ligas set fantasy_activo = true, modo_inicio = 'draft' where id = :'ld';
update miembros set rango = 'fijo' where liga_id = :'ld';
set role authenticated;
select t_como(905);
select iniciar_draft(current_setting('t.ld')::uuid, 2) -> 'rondas' as rondas \gset
select t_check(:'rondas'::int = 2, 'draft de 2 rondas');
select t_check((select count(*) from fichas where liga_id = current_setting('t.ld')::uuid and propietario_id is not null) = 0,
               'en modo draft nadie empieza con jugadores');
do $$
declare v_turno uuid; v_j uuid; v_liga uuid := current_setting('t.ld')::uuid; k int := 0;
begin
  loop
    v_turno := turno_draft(v_liga);
    exit when v_turno is null;
    perform set_config('request.jwt.claim.sub', (select perfil_id::text from miembros where id = v_turno), false);
    select mj.miembro_id into v_j from mercado_jugador mj
     where mj.liga_id = v_liga and ficha_libre(v_liga, mj.miembro_id) is not null
       and not exists (select 1 from fichas f where f.propietario_id = v_turno and f.jugador_id = mj.miembro_id)
     order by mj.precio desc limit 1;
    perform draft_elegir(v_liga, v_j);
    k := k + 1;
  end loop;
  perform t_check(k = 2 * 7, 'todos eligen en serpiente (' || k || ' picks)');
end $$;
reset role;
select t_check((select estado from drafts where liga_id = :'ld') = 'terminado', 'draft terminado');
select t_check((select bool_and(n = 2) from (select count(*) n from fichas where liga_id = :'ld' and propietario_id is not null
                                              group by propietario_id) x), '2 jugadores por mánager');
select t_check((select manager_id from draft_picks where liga_id = :'ld' and pick = 7)
               = (select orden[7] from drafts where liga_id = :'ld'), 'serpiente: el último repite al cambiar de ronda');

-- ═════════ Herencia: bonus del 10 % del patrimonio
set role authenticated;
select t_como(901);
select cerrar_temporada(current_setting('t.liga')::uuid, 'T1', 'bonus');
reset role;
select t_check((select count(*) from transacciones_fantasy where liga_id = :'lf' and tipo = 'herencia_temporada') > 0,
               'herencia: bonus para la nueva temporada');
select t_check((select count(*) from puntos_manager pm join partidos p on p.id = pm.partido_id where p.liga_id = :'lf') = 0,
               'herencia: el Fantasy empieza de cero');

-- ═════════ Cambio de escala
set role authenticated;
select t_como(901);
select (select saldo from fantasy_managers where liga_id = current_setting('t.liga')::uuid and miembro_id = t_m(902)) as s0 \gset
select cambiar_escala(current_setting('t.liga')::uuid, 100);
select t_check((select saldo from fantasy_managers where liga_id = current_setting('t.liga')::uuid and miembro_id = t_m(902))
               = round(:'s0'::numeric * 2, 2), 'cambiar escala multiplica el dinero');
reset role;
\echo '══════ ESCENARIO FASE 2 COMPLETADO SIN ERRORES ══════'
