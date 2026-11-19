-- Escenario del mercado Fantasy (0008/0009). Se ejecuta tras escenario.sql (reutiliza sus utilidades t_*).
-- Liga nueva de 12 mánagers (u101–u112) + 2 jugadores pre-creados sin cuenta (Luis y Marta).
\set ON_ERROR_STOP 1
\pset pager off

reset role;
create or replace function t_pm(p_nombre text) returns uuid language sql stable security definer as $$
  select id from miembros where nombre_provisional = p_nombre and liga_id = current_setting('t.liga')::uuid $$;
grant execute on function t_pm to authenticated;

insert into auth.users (id, email) select t_uid(i), 'u' || i || '@test' from generate_series(101, 112) i;
insert into perfiles (id, nombre, posicion)
select t_uid(i), 'Mánager ' || i,
       (case i when 102 then 'portero' when 103 then 'defensa' when 104 then 'defensa' when 107 then 'defensa'
               when 112 then 'defensa' when 105 then 'delantero' when 109 then 'delantero' when 111 then 'delantero'
               else 'medio' end)::posicion_campo
  from generate_series(101, 112) i;

set role authenticated;

-- ═════════ 1. Liga, miembros y encuesta ═════════
select t_como(101);
select crear_liga('{"nombre":"Liga Mercado","jugadores_por_equipo":5,"num_equipos":2}') as liga \gset
select set_config('t.liga', :'liga', false);
select codigo_invitacion as codigo from ligas where id = :'liga' \gset
select set_config('t.codigo', :'codigo', false);
select count(*) from precrear_jugadores(:'liga', array['Luis', 'Marta']);
do $$ begin
  for i in 102..112 loop perform t_como(i); perform unirse(current_setting('t.codigo')); end loop;
end $$;
select t_como(101);
select t_check((select count(*) from jugadores_liga(:'liga')) = 14, '14 jugadores en la liga (12 + 2 pre-creados)');
select t_check(not mercado_abierto(:'liga'), 'sin encuesta cerrada el mercado no abre');

select t_como(103);
select t_debe_fallar(format('select comprar_jugador(%L, %L)', :'liga', t_m(101)), 'no se compra antes de la encuesta');
select t_debe_fallar(format('select abrir_encuesta(%L)', :'liga'), 'un jugador no abre la encuesta');

select t_como(101);
select abrir_encuesta(:'liga') as enc \gset
select set_config('t.enc', :'enc', false);

-- Orden "real": u101 > u102 > … > u112 > Luis > Marta. En portería, u102 primero.
-- u105 invierte el ranking de calidad (voto atípico): la media recortada lo neutraliza.
do $$
declare e int; a text; base uuid[]; ord uuid[];
begin
  base := array(select t_m(i) from generate_series(101, 112) i) || t_pm('Luis') || t_pm('Marta');
  for e in 101..112 loop
    perform t_como(e);
    foreach a in array array['calidad','velocidad','resistencia','defensa','regate','portero'] loop
      ord := base;
      if a = 'portero' then
        ord := array[t_m(102), t_m(101)] || base[3:14];
      elsif a = 'calidad' and e = 105 then
        ord := array(select x from unnest(base) with ordinality t(x, k) order by k desc);
      end if;
      perform enviar_ranking(current_setting('t.enc')::uuid, a, ord);
    end loop;
  end loop;
end $$;

select t_como(106);
select t_debe_fallar(format('select enviar_ranking(%L, ''calidad'', array[%L]::uuid[])', :'enc', t_m(101)),
                     'el ranking debe incluir a todos los jugadores');
select t_debe_fallar(format('select enviar_ranking(%L, ''calidad'', array[%s]::uuid[])', :'enc',
                            (select string_agg(quote_literal(t_m(101)), ',') from generate_series(1, 14))),
                     'el ranking no admite repetidos');
select t_debe_fallar(format('select enviar_ranking(%L, ''altura'', array[]::uuid[])', :'enc'), 'atributo inexistente');
select t_check((select count(*) from respuestas_ranking where evaluador_id <> t_m(106)) = 0, 'las respuestas ajenas son privadas');
select t_check((select count(*) from respuestas_ranking) = 6 * 14, 'u106 ve sus 6 rankings');
select t_check((select completadas from v_progreso_encuesta where encuesta_id = :'enc') = 12, 'progreso: 12/12 encuestas completas');
select t_debe_fallar(format('select cerrar_encuesta(%L)', :'enc'), 'un jugador no cierra la encuesta');

select t_como(101);
select t_check(cerrar_encuesta(:'enc') = 14, 'encuesta cerrada: 14 jugadores valorados');
select t_debe_fallar(format('select abrir_encuesta(%L)', :'liga'), 'la encuesta general solo se hace una vez');

\echo 'Valoraciones y precios iniciales:'
select coalesce(pe.nombre, m.nombre_provisional) as jugador, vj.calidad, vj.portero, vj.general, mj.precio, mj.no_habitual
  from valoracion_jugador vj join mercado_jugador mj using (liga_id, miembro_id)
  join miembros m on m.id = vj.miembro_id left join perfiles pe on pe.id = m.perfil_id
 where vj.liga_id = :'liga' order by mj.precio desc;

select t_check((select calidad from valoracion_jugador where miembro_id = t_m(101)) = 100,
               'media recortada: el voto invertido de u105 no baja la calidad de u101');
select t_check((select general from valoracion_jugador where miembro_id = t_m(101)) = 100, 'u101: G = 100');
-- u102 portero: 0,6·100 + 0,2·92,31 + 0,2·92,31 = 96,92
select t_check((select general from valoracion_jugador where miembro_id = t_m(102)) = 96.92, 'u102 (portero): G = 96,92');
-- Precios a mano: base(R) = 1 + 11·(R/100)², redondeado a 0,05
select t_check((select precio from mercado_jugador where miembro_id = t_m(101)) = 12.00, 'precio u101 = 12,00 M (R 100)');
select t_check((select precio from mercado_jugador where miembro_id = t_m(102)) = 11.35, 'precio u102 = 11,35 M (R 96,92)');
select t_check((select precio from mercado_jugador where miembro_id = t_m(107)) = 4.20, 'precio u107 = 4,20 M (R 53,85)');
select t_check((select precio from mercado_jugador where miembro_id = t_pm('Marta')) = 1.00, 'precio Marta = 1,00 M (R 0)');
-- Presupuesto = 6,5 × media (68,30 / 14 = 4,879) = 31,71 → 31,5
select t_check((select presupuesto_inicial from ligas where id = :'liga') = 31.5, 'presupuesto inicial 31,5 M');
select t_check((select count(*) from fantasy_managers where liga_id = :'liga' and saldo = 31.5) = 12, '12 mánagers con 31,5 M');
select t_como(106);
select t_check((select count(*) from transacciones_fantasy) = 1, 'un mánager solo ve sus transacciones');
select t_como(101);
select t_check(mercado_abierto(:'liga'), 'mercado abierto tras la encuesta');
select t_check((select no_habitual from mercado_jugador where miembro_id = t_pm('Luis')), 'Luis (pre-creado) es no habitual');
select t_check(not (select no_habitual from mercado_jugador where miembro_id = t_m(110)), 'u110 es habitual (liga sin historial)');

-- ═════════ 2. Mercado ═════════
select t_como(103);
select t_check(comprar_jugador(:'liga', t_m(101)) = 19.50, 'u103 compra a u101 por 12 → 19,50');
select t_check(comprar_jugador(:'liga', t_m(102)) = 8.15, 'u103 compra a u102 por 11,35 → 8,15');
select t_debe_fallar(format('select comprar_jugador(%L, %L)', :'liga', t_m(103)), 'sin saldo (8,90 > 8,15)');
select t_check((select count(*) from plantillas) = 2, 'u103 solo ve su plantilla');

select t_como(104);
select comprar_jugador(:'liga', t_pm('Luis'));
select t_debe_fallar(format('select comprar_jugador(%L, %L)', :'liga', t_pm('Marta')), 'solo 1 no habitual por plantilla');
select t_debe_fallar(format('select comprar_jugador(%L, %L)', :'liga', t_pm('Luis')), 'no se compra dos veces al mismo');
do $$ begin
  for i in 108..112 loop perform comprar_jugador(current_setting('t.liga')::uuid, t_m(i)); end loop;
end $$;
select t_check((select saldo from fantasy_managers where miembro_id = t_m(104)) = 19.55, 'u104: 6 jugadores por 11,95 → 19,55');
select t_debe_fallar(format('select comprar_jugador(%L, %L)', :'liga', t_m(107)), 'plantilla llena (6)');
select t_check(vender_jugador(:'liga', t_m(108)) = 22.73, 'venta de u108: 3,35 − 5 % = 3,18 → 22,73');
select t_check(comprar_jugador(:'liga', t_m(108)) = 19.38, 'recompra de u108 → 19,38');

select t_como(105);
select t_check(comprar_jugador(:'liga', t_m(105)) = 25.25, 'autofichaje permitido: u105 se compra a sí mismo');
select t_check((select count(*) from v_mi_plantilla) = 1, 'v_mi_plantilla de u105');
select t_check((select num_plantillas from v_mercado where miembro_id = t_m(101)) = 1, 'v_mercado agrega plantillas ajenas');
select t_check((select en_mi_plantilla from v_mercado where miembro_id = t_m(105)), 'v_mercado marca los propios');

-- ═════════ 3. Partido y alineaciones ═════════
select t_como(101);
select crear_partido(:'liga', now() + interval '3 hours', 0) as p1 \gset
select set_config('t.p1', :'p1', false);
do $$ begin
  for i in 101..109 loop
    perform t_como(i);
    insert into convocatorias (partido_id, miembro_id) values (current_setting('t.p1')::uuid, t_m(i));
  end loop;
  perform t_como(101);
  insert into convocatorias (partido_id, miembro_id) values (current_setting('t.p1')::uuid, t_pm('Luis'));
end $$;
select guardar_equipos(:'p1', jsonb_build_object(
  t_m(101), 1, t_m(102), 1, t_m(103), 1, t_m(104), 1, t_pm('Luis'), 1,
  t_m(105), 2, t_m(106), 2, t_m(107), 2, t_m(108), 2, t_m(109), 2));

select t_como(104);
select t_debe_fallar(format('select guardar_alineacion(%L, array[%L,%L,%L,%L,%L,%L]::uuid[])', :'p1',
                            t_pm('Luis'), t_m(108), t_m(109), t_m(110), t_m(111), t_m(112)),
                     'alineación de 6 en un 5 contra 5');
select t_debe_fallar(format('select guardar_alineacion(%L, array[%L]::uuid[])', :'p1', t_m(101)),
                     'no se alinea a quien no está en la plantilla');
select t_check(guardar_alineacion(:'p1', array[t_pm('Luis'), t_m(109), t_m(108), t_m(111), t_m(112)]) = 5,
               'u104 alinea 5');
select t_como(103);
select t_check(guardar_alineacion(:'p1', array[t_m(101), t_m(102)]) = 2, 'u103 alinea 2 (se permite menos de 5)');
select t_check((select count(*) from alineaciones where partido_id = :'p1') = 2, 'antes del cierre solo ve la suya');
select t_como(105);
select guardar_alineacion(:'p1', array[t_m(105)]);

-- Faltan menos de 2 h: alineaciones y mercado cerrados
reset role;
update partidos set fecha_hora = now() + interval '1 hour' where id = :'p1';
set role authenticated;
select t_como(104);
select t_debe_fallar(format('select guardar_alineacion(%L, array[%L]::uuid[])', :'p1', t_pm('Luis')),
                     'alineación fuera de plazo');
select t_check(not mercado_abierto(:'liga'), 'mercado cerrado 2 h antes');
select t_como(106);
select t_debe_fallar(format('select comprar_jugador(%L, %L)', :'liga', t_m(107)), 'no se compra con el mercado cerrado');
select t_check((select count(*) from alineaciones where partido_id = :'p1') = 8, 'tras el cierre se ven las alineaciones rivales');
select t_check((select bool_and(multiplicador is null) from alineaciones where partido_id = :'p1'),
               'aún sin congelar (lo hace la tarea programada o la liquidación)');
reset role;
select t_check(congelar_alineaciones_vencidas() = 1, 'pg_cron: congela las alineaciones del partido 1');
select t_check(congelar_alineaciones(:'p1') = false, 'congelar es idempotente');
set role authenticated;
select t_check((select multiplicador from alineaciones where partido_id = :'p1' and jugador_id = t_pm('Luis')) = 1.5,
               'Luis congelado como no habitual ×1,5');

-- Partido 3-1: Luis 2 goles, u101 1; u105 marca para el equipo 2
select t_como(101);
select marcar_jugado(:'p1');
do $$
declare r int; s uuid;
begin
  for r in 101..109 loop
    perform t_como(r);
    insert into reportes_encuentro (partido_id, n, reportero_id, goles_local, goles_visitante)
    values (current_setting('t.p1')::uuid, 1, t_m(r), 3, 1);
    for s in select miembro_id from convocatorias where partido_id = current_setting('t.p1')::uuid and equipo is not null loop
      insert into reportes_jugador (partido_id, reportero_id, sujeto_id, goles, asistencias, autogoles)
      values (current_setting('t.p1')::uuid, t_m(r), s,
              case when s = t_pm('Luis') then 2 when s in (t_m(101), t_m(105)) then 1 else 0 end, 0, 0);
    end loop;
  end loop;
end $$;
select t_como(101);
select t_check(cerrar_post_partido(:'p1') = 'cerrado', 'sin disputas: puntos calculados y partido cerrado');

\echo 'Puntos de jugadores:'
select coalesce(pe.nombre, m.nombre_provisional) as jugador, pf.total
  from puntos_fantasy pf join miembros m on m.id = pf.miembro_id left join perfiles pe on pe.id = m.perfil_id
 where pf.partido_id = :'p1' order by pf.total desc;
select t_check((select total from puntos_fantasy where partido_id = :'p1' and miembro_id = t_pm('Luis')) = 13,
               'Luis: 2 jugado + 3 victoria + 2×4 goles = 13');

-- ═════════ 4. Liquidación de la jornada ═════════
\echo 'Jornada de mánagers:'
select nombre, puntos, ingreso, posicion from v_jornada_managers where partido_id = :'p1' and puntos <> 0 order by posicion;
select t_check((select jornada_liquidada from partidos where id = :'p1'), 'jornada liquidada al cerrar el partido');
select t_check((select puntos from puntos_manager where partido_id = :'p1' and manager_id = t_m(104)) = 23.5,
               'u104: Luis 13×1,5 + 2 + 2 + 0 + 0 = 23,5');
select t_check((select puntos from puntos_manager where partido_id = :'p1' and manager_id = t_m(103)) = 15, 'u103: 10 + 5 = 15');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(104)) = 21.73, 'u104 cobra 2,35 M → 21,73');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(105)) = 25.85, 'u105 cobra 0,60 M → 25,85');
select t_check((select count(*) from puntos_manager where partido_id = :'p1') = 12, 'los 12 mánagers tienen fila de jornada');

\echo 'Precios tras la jornada:'
select nombre, precio, variacion, variacion_pct, rating, num_plantillas from v_mercado
 where liga_id = :'liga' order by precio desc;
-- Luis: R = 5/6·7,69 + 1/6·100 = 23,08 → base 1,59 × demanda 1,012 = 1,60, pero tope +15 % sobre 1,05 → 1,20
select t_check((select precio from mercado_jugador where miembro_id = t_pm('Luis')) = 1.20, 'Luis sube con tope del 15 %: 1,05 → 1,20');
-- u101: R = 5/6·100 + 1/6·88,9 = 98,15 → base 11,60 × 1,012 = 11,73 → 11,75
select t_check((select precio from mercado_jugador where miembro_id = t_m(101)) = 11.75, 'u101: 12,00 → 11,75');
select t_check((select bool_and(h.precio <= p0.precio * 1.15 and h.precio >= p0.precio * 0.85)
                  from historial_precios h
                  join historial_precios p0 on p0.miembro_id = h.miembro_id and p0.partido_id is null
                 where h.partido_id = :'p1'), 'ningún precio varía más del 15 %');
select t_check((select count(*) from historial_precios where partido_id = :'p1') = 14, 'historial: 14 precios de la jornada');
select t_check((select rating from v_rating_balanceo where miembro_id = t_m(101)) = 98.15, 'v_rating_balanceo usa el rating dinámico');

-- Idempotencia
select t_check(liquidar_jornada(:'p1') = false, 'liquidar dos veces no hace nada');
select t_check(recalcular_precios(:'liga', :'p1') = 0, 'recalcular precios dos veces no hace nada');
select t_check((select saldo from fantasy_managers where miembro_id = t_m(104)) = 21.73, 'saldo sin cambios');
select t_check((select count(*) from puntos_manager where partido_id = :'p1') = 12, 'sin filas duplicadas');
select t_check((select count(*) from transacciones_fantasy where manager_id = t_m(104) and tipo = 'ingreso_puntos') = 1,
               'el admin ve las transacciones: un solo ingreso de u104');

select t_check((select manager_id from v_clasificacion_managers where liga_id = :'liga' and posicion = 1) = t_m(104),
               'u104 lidera la clasificación de mánagers');
select t_check(mercado_abierto(:'liga'), 'el mercado reabre tras liquidar');
select t_como(106);
select comprar_jugador(:'liga', t_m(107));

-- ═════════ 5. Jugador nuevo y mini-encuesta ═════════
select t_como(101);
select count(*) from precrear_jugadores(:'liga', array['Nuevo']);
select t_check((select precio from mercado_jugador where miembro_id = t_pm('Nuevo')) = 3.75, 'jugador nuevo entra con G = 50 → 3,75');
select abrir_encuesta(:'liga', t_pm('Nuevo')) as mini \gset
select set_config('t.mini', :'mini', false);
do $$
declare e int; base uuid[];
begin
  base := array[t_pm('Nuevo')] || array(select t_m(i) from generate_series(101, 112) i) || t_pm('Luis') || t_pm('Marta');
  foreach e in array array[102, 103, 104] loop
    perform t_como(e);
    perform enviar_ranking(current_setting('t.mini')::uuid, 'calidad', base);
  end loop;
end $$;
select t_como(101);
select cerrar_encuesta(:'mini');
-- calidad 100 (3 evaluadores), el resto 50 → G = 0,35·100 + 0,65·50 = 67,5 → 1 + 11·0,4556 = 6,01 → 6,00
select t_check((select precio from mercado_jugador where miembro_id = t_pm('Nuevo')) = 6.00, 'mini-encuesta: Nuevo vale 6,00 M');

-- ═════════ 6. Alineación copiada de la jornada anterior ═════════
select crear_partido(:'liga', now() + interval '3 hours', 0) as p2 \gset
reset role;
update partidos set fecha_hora = now() + interval '1 hour' where id = :'p2';
select t_check(congelar_alineaciones_vencidas() = 1, 'la tarea programada congela el partido 2');
select t_check((select count(*) from alineaciones where partido_id = :'p2' and manager_id = t_m(104) and copiada) = 5,
               'u104 no guardó: se copia su alineación anterior (5)');
select t_check((select multiplicador from alineaciones where partido_id = :'p2' and jugador_id = t_pm('Luis')) = 1.5,
               'la copia mantiene el ×1,5 de Luis');
select t_check((select count(*) from alineaciones where partido_id = :'p2' and manager_id = t_m(103)) = 2, 'u103: copia de 2');
update partidos set estado = 'cancelado' where id = :'p2';

\echo '══════ ESCENARIO MERCADO COMPLETADO SIN ERRORES ══════'
