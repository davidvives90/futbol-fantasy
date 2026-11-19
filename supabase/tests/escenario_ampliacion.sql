-- Escenario de la ampliación 0.2 (0010–0014): migración de datos 0.1, fichas, cláusulas, ofertas, cesiones,
-- posiciones flexibles, roles y precios sin rendimiento hasta 3 partidos.
-- Se ejecuta DESPUÉS de escenario.sql y escenario_mercado.sql (con datos 0.1) y de aplicar 0010+.
\set ON_ERROR_STOP 1
\pset pager off

-- ═════════ 0. Migración de la liga creada con la 0.1 ═════════
reset role;
select id as lm from ligas where nombre = 'Liga Mercado' \gset
select set_config('t.liga', :'lm', false);

select t_check((select copias_por_jugador from ligas where id = :'lm') = 4, 'liga 0.1: C = ⌈12·6·0,8/15⌉ = 4 fichas por jugador');
select t_check((select count(*) from fichas where liga_id = :'lm') = 60, 'liga 0.1: 15 jugadores × 4 fichas');
select t_check((select count(*) from fichas where liga_id = :'lm' and propietario_id is not null) = 10,
               'las 10 plantillas de la 0.1 pasan a fichas con dueño');
select t_check((select count(*) from fichas where propietario_id = t_m(104)) = 6, 'u104 conserva sus 6 jugadores');
select t_check((select bool_and(f.clausula >= mj.precio) from fichas f
                  join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
                 where f.propietario_id is not null), 'cláusulas migradas ≥ valor de mercado');
select t_check(not exists (select 1 from reglas_puntuacion
                            where clave like 'gol\_%' or clave like 'porteria_cero%' or clave = 'goles_encajados_3'
                               or posicion is not null), 'sin reglas por posición en ninguna liga');
select t_check((select bool_and(puntos = 5) from reglas_puntuacion where clave = 'gol')
               and (select count(*) from reglas_puntuacion where clave = 'gol') = (select count(*) from ligas),
               'gol = 5 en todas las ligas');
select t_check((select count(*) from reglas_puntuacion where liga_id = :'lm' and clave like 'rol\_%') = 6,
               '6 reglas de bonus de rol');
select t_check(not exists (select 1 from aspectos_valoracion where (clave = 'porteria' and activo) or aplica_a <> 'todos'),
               'aspectos iguales para todos; Portería desactivada');
select t_check(not exists (select 1 from ligas where puntuar_por_posicion), 'puntuar_por_posicion desactivado');
select t_check(not exists (select partido_id, manager_id from alineaciones group by 1, 2
                            having count(*) filter (where rol = 'POR') <> 1),
               'cada alineación migrada tiene exactamente 1 POR');
select t_check((select general from valoracion_jugador where miembro_id = t_m(101)) = 99.23,
               'G sin posición: 0,9·100 + 0,1·92,31 = 99,23');

set role authenticated;
select t_como(106);
select t_check(mercado_abierto(:'lm'), 'el mercado de la liga 0.1 sigue abierto');
select t_check(comprar_jugador(:'lm', t_m(110)) is not null, 'comprar_jugador (firma de la app 0.1) sigue funcionando');
select t_check((select count(*) from v_mi_plantilla) = 2, 'u106: 2 jugadores en v_mi_plantilla');
select t_check((select count(*) from plantillas) = 11,
               'las plantillas ya son visibles para la liga (hace falta para clausular)');
select t_debe_fallar(format('select mover_saldo(%L, %L, 100, %L)', :'lm', t_m(106), 'ajuste'),
                     'mover_saldo no se puede llamar desde la app');
select t_debe_fallar(format('select transferir_ficha(%L, %L, 0)',
                            (select id from fichas where liga_id = :'lm' limit 1), t_m(106)),
                     'transferir_ficha no se puede llamar desde la app');
select t_debe_fallar('insert into fichas (liga_id, jugador_id, numero) values (gen_random_uuid(), gen_random_uuid(), 9)',
                     'nadie escribe en fichas directamente');
reset role;
set role anon;
select t_debe_fallar('select count(*) from fichas', 'anon no lee fichas');
select t_debe_fallar('select count(*) from v_mercado', 'anon no lee el mercado');
select t_debe_fallar('select count(*) from ofertas', 'anon no lee ofertas');
reset role;

-- ═════════ 1. Liga nueva: fútbol 3, plantillas de 3 ═════════
insert into auth.users (id, email) select t_uid(i), 'u' || i || '@test' from generate_series(201, 208) i;
insert into perfiles (id, nombre, posicion)
select t_uid(i), 'Fichas ' || i, case when i = 201 then 'portero'::posicion_campo end from generate_series(201, 208) i;

set role authenticated;
select t_como(201);
select crear_liga('{"nombre":"Liga Fichas","jugadores_por_equipo":3,"num_equipos":2}') as lf \gset
select set_config('t.liga', :'lf', false);
update ligas set max_plantilla = 3 where id = :'lf';
select codigo_invitacion as cod from ligas where id = :'lf' \gset
select set_config('t.codigo', :'cod', false);
do $$ begin
  for i in 202..206 loop perform t_como(i); perform unirse(current_setting('t.codigo')); end loop;
end $$;
select t_como(201);
select t_check((select puntos from reglas_puntuacion where liga_id = :'lf' and clave = 'gol') = 5
               and not exists (select 1 from reglas_puntuacion where liga_id = :'lf' and clave like 'gol\_%'),
               'liga nueva: gol = 5 y sin reglas por posición');
select t_check((select count(*) from aspectos_valoracion where liga_id = :'lf' and activo) = 5, 'liga nueva: 5 aspectos activos');
select t_check((select bonus_roles from ligas where id = :'lf'), 'liga nueva: bonus de rol activados');

select abrir_encuesta(:'lf') as enc \gset
select set_config('t.enc', :'enc', false);
do $$
declare e int; a text; ord uuid[];
begin
  ord := array(select t_m(i) from generate_series(201, 206) i);
  for e in 201..206 loop
    perform t_como(e);
    foreach a in array array['calidad','velocidad','resistencia','defensa','regate','portero'] loop
      perform enviar_ranking(current_setting('t.enc')::uuid, a, ord);
    end loop;
  end loop;
end $$;
select t_como(201);
select cerrar_encuesta(:'enc');
select t_check((select general from valoracion_jugador where miembro_id = t_m(201)) = 100, 'u201 (portero de perfil): G = 100 con la media única');
select t_check((select general from valoracion_jugador where miembro_id = t_m(202)) = 80, 'u202: G = 80');
select t_check((select precio from mercado_jugador where miembro_id = t_m(201)) = 12.00, 'precio u201 = 12,00');
select t_check((select precio from mercado_jugador where miembro_id = t_m(202)) = 8.05, 'precio u202 = 8,04 → 8,05');
-- media de precios (12 + 8,05 + 4,95 + 2,75 + 1,45 + 1) / 6 = 5,033 → × 6,5 = 32,72 → 32,5
select t_check((select presupuesto_inicial from ligas where id = :'lf') = 32.5, 'presupuesto inicial 32,5 M');
select t_check((select copias_por_jugador from ligas where id = :'lf') = 3, 'C = ⌈6·3·0,8/6⌉ = 3');
select t_check((select count(*) from fichas where liga_id = :'lf') = 18, '6 jugadores × 3 fichas');

-- ═════════ 2. Fichas agotadas y protección ═════════
do $$ begin
  for i in 202..204 loop perform t_como(i); perform comprar_ficha(current_setting('t.liga')::uuid, t_m(201)); end loop;
end $$;
select t_como(205);
select t_debe_fallar(format('select comprar_ficha(%L, %L)', :'lf', t_m(201)), 'fichas de u201 agotadas (3 de 3)');
select t_check((select fichas_libres from v_mercado where miembro_id = t_m(201)) = 0, 'v_mercado: 0 fichas libres de u201');
select t_check((select clausula_minima from v_mercado where miembro_id = t_m(201)) is null,
               'ninguna ficha de u201 clausulable todavía (todas protegidas)');
select id as f202 from fichas where propietario_id = t_m(202) and jugador_id = t_m(201) \gset
select id as f203 from fichas where propietario_id = t_m(203) and jugador_id = t_m(201) \gset
select id as f204 from fichas where propietario_id = t_m(204) and jugador_id = t_m(201) \gset
select t_debe_fallar(format('select pagar_clausula(%L)', :'f202'), 'ficha recién comprada: protegida contra la cláusula');

-- ═════════ 3. Cláusulas ═════════
select t_como(202);
select t_check(fijar_clausula(:'f202', 20) = 20, 'u202 sube su cláusula de 12 a 20');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(202)) = 19.70, 'subir 8 M cuesta el 10 %: 20,50 − 0,80');
select t_debe_fallar(format('select fijar_clausula(%L, 10)', :'f202'), 'la cláusula no baja del valor de mercado');
select t_check(fijar_clausula(:'f202', 15) = 15, 'bajarla a 15 es gratis');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(202)) = 19.70, 'bajar la cláusula no cuesta');
select t_como(203);
select t_debe_fallar(format('select fijar_clausula(%L, 30)', :'f202'), 'solo el dueño fija la cláusula');

-- ═════════ 4. Ofertas ═════════
select t_como(205);
select hacer_oferta(:'f203', 10) as o1 \gset
select t_como(203);
select t_check(responder_oferta(:'o1', false) = 'rechazada', 'u203 rechaza la oferta de 10 M');
select t_como(205);
select hacer_oferta(:'f203', 14) as o2 \gset
select cancelar_oferta(:'o2');
select t_check((select estado from ofertas where id = :'o2') = 'cancelada', 'u205 cancela su oferta');
select hacer_oferta(:'f203', 13) as o3 \gset
select t_como(201);
select t_check((select count(*) from ofertas) = 0, 'un tercero no ve ofertas ajenas');
reset role;
update ofertas set expira_en = now() - interval '1 minute' where id = :'o3';
set role authenticated;
select t_como(203);
select t_check(responder_oferta(:'o3', true) = 'caducada', 'aceptar una oferta vencida → caducada, sin traspaso');
select t_check((select propietario_id from fichas where id = :'f203') = t_m(203), 'la ficha sigue siendo de u203');

-- Revalidación al aceptar
select t_como(206);
select comprar_ficha(:'lf', t_m(202));
select comprar_ficha(:'lf', t_m(203));
select hacer_oferta(:'f204', 15) as o4 \gset
select comprar_ficha(:'lf', t_m(204));
select t_check((select saldo from fantasy_managers where miembro_id = t_m(206)) = 16.75, 'u206: 32,5 − 8,05 − 4,95 − 2,75');
select t_como(204);
select t_debe_fallar(format('select responder_oferta(%L, true)', :'o4'), 'al aceptar se revalida: la plantilla de u206 está llena');
select t_check((select estado from ofertas where id = :'o4') = 'pendiente', 'la oferta sigue pendiente');
select t_como(206);
select id as f206_204 from fichas where propietario_id = t_m(206) and jugador_id = t_m(204) \gset
select t_check(vender_ficha(:'f206_204') = 19.36, 'u206 vende a u204: 2,75 − 5 % = 2,61 → 19,36');
select t_como(204);
select t_check(responder_oferta(:'o4', true) = 'aceptada', 'u204 acepta los 15 M');
select t_check((select propietario_id from fichas where id = :'f204') = t_m(206), 'la ficha pasa a u206');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(204)) = 35.50, 'u204 cobra 15 → 35,50');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(206)) = 4.36, 'u206 paga 15 → 4,36');
select t_check((select protegida from v_fichas_jugador where ficha_id = :'f204'), 'la ficha adquirida por oferta queda protegida');

-- ═════════ 5. Cesiones ═════════
select t_como(201);
select crear_partido(:'lf', now() + interval '5 hours', 0) as p1 \gset
select set_config('t.p1', :'p1', false);
select t_como(202);
select comprar_ficha(:'lf', t_m(205));
select t_debe_fallar(format('select ofrecer_cesion(%L, 0.40)', :'f202'), 'cesión al 40 %: fuera del rango 5–30 %');
select t_debe_fallar(format('select ofrecer_cesion(%L, 0.01)', :'f202'), 'cesión al 1 %: fuera del rango 5–30 %');
select ofrecer_cesion(:'f202', 0.15) as c1 \gset
select id as f202_205 from fichas where propietario_id = t_m(202) and jugador_id = t_m(205) \gset
select t_debe_fallar(format('select ofrecer_cesion(%L, 0.10)', :'f202_205'), 'solo se cede un jugador por jornada');
select t_como(205);
select comprar_ficha(:'lf', t_m(206));
select t_check((select count(*) from v_cesiones_disponibles where cesion_id = :'c1') = 1, 'la cesión ofrecida es visible para la liga');
select t_check(aceptar_cesion(:'c1') = 29.70, 'u205 acepta la cesión: 15 % de 12 = 1,80 M → 29,70');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(202)) = 20.05, 'u202 cobra 1,80 → 20,05');
select t_check((select count(*) from v_mi_plantilla where cedida_a_mi) = 1, 'u201 aparece en la plantilla de u205 como cedido');
select t_como(203);
select ofrecer_cesion(:'f203', 0.10) as c2 \gset
select t_como(205);
select t_debe_fallar(format('select aceptar_cesion(%L)', :'c2'), 'solo se recibe un cedido por jornada');
select t_como(203);
select cancelar_cesion(:'c2');
select t_check((select estado from cesiones where id = :'c2') = 'cancelada', 'u203 retira su cesión');

select t_como(202);
select t_debe_fallar(format('select vender_ficha(%L)', :'f202'), 'no se vende una ficha cedida');
select t_debe_fallar(format('select guardar_alineacion(%L, array[%L]::uuid[])', :'p1', t_m(201)),
                     'el dueño no puede alinear al jugador que ha cedido');
select t_como(204);
select t_debe_fallar(format('select hacer_oferta(%L, 20)', :'f202'), 'no se oferta por una ficha cedida');

-- ═════════ 6. Alineaciones con roles ═════════
select t_como(205);
select t_debe_fallar(format('select guardar_alineacion(%L, array[%L,%L]::uuid[], array[''DEL'',''DEF''])', :'p1', t_m(201), t_m(206)),
                     'alineación sin portero');
select t_debe_fallar(format('select guardar_alineacion(%L, array[%L,%L]::uuid[], array[''POR'',''POR''])', :'p1', t_m(201), t_m(206)),
                     'alineación con dos porteros');
select t_debe_fallar(format('select guardar_alineacion(%L, array[%L,%L]::uuid[], array[''POR'',''XXX''])', :'p1', t_m(201), t_m(206)),
                     'rol inexistente');
select t_check(guardar_alineacion(:'p1', array[t_m(201), t_m(206)], array['DEL', 'POR']) = 2,
               'u205 alinea al cedido de DEL y a u206 de POR');
select t_como(202);
select t_check(guardar_alineacion(:'p1', array[t_m(205)]) = 1, 'u202 alinea a u205 sin indicar roles (firma 0.1)');
select t_check((select rol from alineaciones where partido_id = :'p1' and manager_id = t_m(202)) = 'POR', 'rol por defecto: POR');
select t_como(203);
select comprar_ficha(:'lf', t_m(202));
select comprar_ficha(:'lf', t_m(204));
select t_check((select saldo from fantasy_managers where miembro_id = t_m(203)) = 9.70, 'u203: 20,50 − 8,05 − 2,75');
select t_check(guardar_alineacion(:'p1', array[t_m(202), t_m(201), t_m(204)], array['POR', 'MED', 'DEL']) = 3,
               'u203: POR, MED y DEL');
select t_debe_fallar(format('select guardar_alineacion(%L, array[%L,%L,%L,%L]::uuid[])', :'p1', t_m(202), t_m(201), t_m(204), t_m(203)),
                     'como máximo media plantilla del partido (3)');
select t_como(206);
select t_check(guardar_alineacion(:'p1', array[t_m(202), t_m(201), t_m(203)], array['POR', 'DEF', 'MED']) = 3,
               'u206: POR, DEF y MED');

-- ═════════ 7. Partido 3-0 y liquidación ═════════
select t_como(201);
do $$ begin
  for i in 201..206 loop
    perform t_como(i);
    insert into convocatorias (partido_id, miembro_id) values (current_setting('t.p1')::uuid, t_m(i));
  end loop;
end $$;
select t_como(201);
select guardar_equipos(:'p1', jsonb_build_object(t_m(201), 1, t_m(203), 1, t_m(205), 1, t_m(202), 2, t_m(204), 2, t_m(206), 2));
reset role;
update partidos set fecha_hora = now() + interval '1 hour' where id = :'p1';
select t_check(congelar_alineaciones_vencidas() >= 1, 'cierre: alineaciones congeladas');
select t_check((select estado from cesiones where id = :'c1') = 'aceptada', 'la cesión aceptada sigue en vigor durante el partido');
set role authenticated;
select t_como(201);
select marcar_jugado(:'p1');
-- Equipo 1 (u201, u203, u205) gana 3-0: u201 2 goles, u205 1; u203 1 asistencia
do $$
declare r int; s uuid;
begin
  for r in 201..206 loop
    perform t_como(r);
    insert into reportes_encuentro (partido_id, n, reportero_id, goles_local, goles_visitante)
    values (current_setting('t.p1')::uuid, 1, t_m(r), 3, 0);
    for s in select miembro_id from convocatorias where partido_id = current_setting('t.p1')::uuid and equipo is not null loop
      insert into reportes_jugador (partido_id, reportero_id, sujeto_id, goles, asistencias, autogoles)
      values (current_setting('t.p1')::uuid, t_m(r), s,
              case when s = t_m(201) then 2 when s = t_m(205) then 1 else 0 end,
              case when s = t_m(203) then 1 else 0 end, 0);
    end loop;
  end loop;
end $$;
select t_como(201);
select t_check(cerrar_post_partido(:'p1') = 'cerrado', 'acta sin disputas: puntos calculados y jornada liquidada');

select t_check((select total from puntos_fantasy where partido_id = :'p1' and miembro_id = t_m(201)) = 15,
               'u201 (portero de perfil): 2 + 3 + 2×5 = 15 — el gol vale 5 para todos');
select t_check(not (select desglose ? 'porteria_cero' from puntos_fantasy where partido_id = :'p1' and miembro_id = t_m(201)),
               'sin puntos de portería a cero por posición');
select t_check((select total from puntos_fantasy where partido_id = :'p1' and miembro_id = t_m(203)) = 8, 'u203: 2 + 3 + asistencia 3 = 8');

\echo 'Jornada de mánagers (liga Fichas):'
select nombre, puntos, ingreso, posicion from v_jornada_managers where partido_id = :'p1' order by posicion, nombre;
select t_check((select puntos from puntos_manager where partido_id = :'p1' and manager_id = t_m(205)) = 18,
               'u205: cedido u201 DEL 15 + 2 + u206 POR 2 − 1 = 18');
select t_check((select puntos from puntos_manager where partido_id = :'p1' and manager_id = t_m(202)) = 15,
               'u202: u205 POR 10 + 3 (portería a cero) + 2 (menos goleado) = 15');
select t_check((select puntos from puntos_manager where partido_id = :'p1' and manager_id = t_m(203)) = 18,
               'u203: u202 POR 2 − 1 + u201 MED 15 + u204 DEL 2 = 18');
select t_check((select puntos from puntos_manager where partido_id = :'p1' and manager_id = t_m(206)) = 26,
               'u206: u202 POR 1 + u201 DEF 15 + 1 + u203 MED 8 + 1 = 26');
select t_check((select bonus_rol from alineaciones where partido_id = :'p1' and manager_id = t_m(206) and jugador_id = t_m(201)) = 1,
               'bonus DEF: equipo menos goleado +1');
select t_check((select bonus_rol from alineaciones where partido_id = :'p1' and manager_id = t_m(206) and jugador_id = t_m(203)) = 1,
               'bonus MED: +1 por asistencia');
select t_check((select bonus_rol from alineaciones where partido_id = :'p1' and manager_id = t_m(205) and jugador_id = t_m(201)) = 2,
               'bonus DEL: +1 por gol');
select t_check((select bonus_rol from alineaciones where partido_id = :'p1' and manager_id = t_m(203) and jugador_id = t_m(202)) = -1,
               'bonus POR: −1 por cada 3 encajados');
select t_check((select (d ->> 'cedido')::boolean from puntos_manager pm, jsonb_array_elements(pm.desglose) d
                 where pm.partido_id = :'p1' and pm.manager_id = t_m(205) and d ->> 'jugador_id' = t_m(201)::text),
               'el desglose de u205 marca a u201 como cedido');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(205)) = 31.50, 'u205 cobra 1,80 M → 31,50');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(206)) = 6.96, 'u206 cobra 2,60 M → 6,96');

reset role;
update ligas set bonus_roles = false where id = :'lf';
select t_check(bonus_rol(:'p1', t_m(205), 'POR') = 0, 'con bonus_roles = false el rol es solo estético');
update ligas set bonus_roles = true where id = :'lf';
select t_check(bonus_rol(:'p1', t_m(205), 'POR') = 5, 'bonus POR del equipo imbatido: 3 + 2');
set role authenticated;

-- ═════════ 8. Después de la jornada ═════════
select t_check((select estado from cesiones where id = :'c1') = 'finalizada', 'tras liquidar la cesión termina');
select t_como(205);
select t_check((select count(*) from v_mi_plantilla where cedida_a_mi) = 0, 'u201 vuelve a su dueño');
select t_check((select protegida_jornadas from fichas where id = :'f204') = 0, 'la protección se consume al cerrar la jornada');
\echo 'Precios tras la jornada (liga Fichas):'
select nombre, precio, rating, fichas_totales, fichas_libres from v_mercado where liga_id = :'lf' order by precio desc;
select t_check((select rating from mercado_jugador where miembro_id = t_m(206)) = 0,
               'u206 jugó, pero con menos de 3 partidos el rendimiento no cuenta: rating = G = 0');
select t_check((select rating from mercado_jugador where miembro_id = t_m(201)) = 100, 'u201: rating = G = 100');
-- Demanda: fichas con dueño / C → u201 3/3 = 1; media 0,5 → ×1,2 → 14,40, pero el precio máximo de la liga es 12
select t_check((select precio from mercado_jugador where miembro_id = t_m(201)) = 12.00, 'u201: la demanda lo subiría, pero el máximo es 12 M');
-- u202: 2/3 → ×1,0667 → 8,04 × 1,0667 = 8,58 → 8,60
select t_check((select precio from mercado_jugador where miembro_id = t_m(202)) = 8.60, 'u202: 8,05 → 8,60');
select t_check((select precio from mercado_jugador where miembro_id = t_m(206)) = 1.00, 'u206 no baja del precio mínimo');

-- ═════════ 9. Cláusula sin protección ═════════
select t_como(201);
select crear_partido(:'lf', now() + interval '5 hours', 0) as p2 \gset
select t_como(202);
select t_check(guardar_alineacion(:'p2', array[t_m(201), t_m(205)], array['DEL', 'POR']) = 2,
               'tras volver, el dueño ya puede alinear a u201');
select t_como(205);
select t_check(pagar_clausula(:'f202') = 16.50, 'u205 paga la cláusula de 15 M (sin protección; > valor 12): 31,50 → 16,50');
select t_check((select propietario_id from fichas where id = :'f202') = t_m(205), 'la ficha es ahora de u205');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(202)) = 36.55, 'u202 cobra la cláusula íntegra: 21,55 + 15');
select t_check(not exists (select 1 from alineaciones where partido_id = :'p2' and manager_id = t_m(202) and jugador_id = t_m(201)),
               'u201 sale de la alineación de su antiguo dueño');
select t_check((select protegida from v_fichas_jugador where ficha_id = :'f202'), 'la ficha clausulada queda protegida');
select t_como(204);
select t_debe_fallar(format('select pagar_clausula(%L)', :'f202'), 'no se puede re-clausular de inmediato');

-- ═════════ 10. C solo crece ═════════
select t_como(201);
update ligas set max_plantilla = 5 where id = :'lf';
select t_como(207);
select unirse(:'cod');
select t_check((select copias_por_jugador from ligas where id = :'lf') = 4, 'C sube: ⌈6·5·0,8/7⌉ = 4');
select t_check((select count(*) from fichas where liga_id = :'lf') = 28, '7 jugadores × 4 fichas');
select t_check(comprar_ficha(:'lf', t_m(201)) is not null, 'con C = 4 vuelve a haber una ficha libre de u201');
select t_como(201);
update ligas set max_plantilla = 3 where id = :'lf';
select t_como(208);
select unirse(:'cod');
select t_check((select copias_por_jugador from ligas where id = :'lf') = 4, 'C nunca baja (la fórmula daría 3)');
select t_check((select count(*) from fichas where liga_id = :'lf') = 32, '8 jugadores × 4 fichas');

reset role;
\echo '══════ ESCENARIO AMPLIACIÓN COMPLETADO SIN ERRORES ══════'
