-- Escenario v0.3 (0015–0019): rangos, lista de espera por prioridad, temporada, factura mensual,
-- invitado del Fantasy por rango, verificación de goles (enviar_parte y descuadres) y MVP.
-- Se ejecuta DESPUÉS de los escenarios 0.1 y 0.2 y de aplicar 0015+, sobre sus datos.
\set ON_ERROR_STOP 1
\pset pager off

-- ═════════ 0. Migración de los datos existentes ═════════
reset role;
select t_check(not exists (select 1 from miembros where estado in ('activo', 'pendiente_registro') and rango <> 'fijo'),
               'miembros existentes (activos y pre-creados) → fijo');
select t_check(not exists (select 1 from ligas where orden_espera <> 'prioridad' or modo_cobro <> 'por_partido'
                                                  or plazas_fijas is distinct from plazas),
               'ligas existentes: espera por prioridad, cobro por partido, plazas_fijas = plazas');
select t_check(not exists (select 1 from mercado_jugador where no_habitual), 'nadie es invitado tras migrar (todos fijos)');
select t_check(not exists (select 1 from convocatorias where rango is null), 'inscripciones existentes con rango copiado');

-- Utilidades de este escenario
create or replace function t_jug(i int, g int, a int default 0, ag int default 0) returns jsonb language sql stable as $$
  select jsonb_build_object('sujeto_id', t_m(i), 'goles', g, 'asistencias', a, 'autogoles', ag) $$;
create or replace function t_res(gl int, gv int) returns jsonb language sql immutable as $$
  select jsonb_build_array(jsonb_build_object('n', 1, 'goles_local', gl, 'goles_visitante', gv)) $$;
-- vota con la misma nota todos los aspectos activos
create or replace function t_votar(p uuid, votante int, votado int, nota int) returns void language plpgsql as $$
declare a text;
begin
  perform t_como(votante);
  for a in select clave from aspectos_valoracion where liga_id = current_setting('t.liga')::uuid and activo loop
    insert into valoraciones (partido_id, votante_id, votado_id, aspecto, nota) values (p, t_m(votante), t_m(votado), a, nota);
  end loop;
end $$;
-- partido jugado de 3 contra 3: equipo 1 = u301, u302, u303; equipo 2 = u304, u305, u306
create or replace function t_jugar(f timestamptz) returns uuid language plpgsql as $$
declare p uuid;
begin
  perform t_como(301);
  p := crear_partido(current_setting('t.liga')::uuid, f, 0);
  perform guardar_equipos(p, jsonb_build_object(t_m(301), 1, t_m(302), 1, t_m(303), 1, t_m(304), 2, t_m(305), 2, t_m(306), 2));
  perform marcar_jugado(p);
  return p;
end $$;
grant execute on function t_jug, t_res, t_votar, t_jugar to authenticated;

set role authenticated;
select t_como(1);
select t_check((select count(*) from (select id, rango from miembros) t) > 0, 'la app puede leer miembros.rango');
reset role;

-- ═════════ 1. Liga v0.3: rangos ═════════
insert into auth.users (id, email) select t_uid(i), 'u' || i || '@test' from generate_series(301, 312) i;
insert into perfiles (id, nombre) select t_uid(i), 'V3 ' || i from generate_series(301, 312) i;

set role authenticated;
select t_como(301);
select crear_liga('{"nombre":"Liga Lunes","jugadores_por_equipo":3,"num_equipos":2}') as lv \gset
select set_config('t.liga', :'lv', false);
select codigo_invitacion as codv from ligas where id = :'lv' \gset
select set_config('t.codigo', :'codv', false);
select t_check((select rango from miembros where id = t_m(301)) = 'fijo', 'el creador de la liga es fijo');
do $$ begin
  for i in 302..309 loop perform t_como(i); perform unirse(current_setting('t.codigo')); end loop;
end $$;
select t_check((select bool_and(rango = 'reserva') from miembros where liga_id = :'lv' and perfil_id <> t_uid(301)),
               'las altas nuevas entran como reserva');

select t_como(302);
select t_debe_fallar(format('select cambiar_rango(%L, %L)', t_m(303), 'fijo'), 'solo un admin cambia rangos');
select t_como(301);
select t_debe_fallar(format('select cambiar_rango(%L, %L)', t_m(303), 'capitan'), 'rango inexistente');
do $$ begin
  for i in 302..306 loop perform cambiar_rango(t_m(i), 'fijo'); end loop;
end $$;
select cambiar_rango(t_m(309), 'invitado');
select t_check((select count(*) from miembros where liga_id = :'lv' and rango = 'fijo') = 6, '6 fijos');
select t_check((select rango from miembros where id = t_m(309)) = 'invitado', 'u309 es invitado');
select miembro_id as pre_inv from precrear_jugadores(:'lv', array['Primo de Luis'], null, 'invitado') \gset
select t_check((select rango from miembros where id = :'pre_inv') = 'invitado', 'precrear_jugadores con rango');

-- ═════════ 2. Fijos autoinscritos y lista de espera ═════════
select crear_partido(:'lv', '2027-03-01 21:00 Europe/Madrid', 0) as p1 \gset
select t_check((select count(*) from convocatorias c join miembros m on m.id = c.miembro_id
                 where c.partido_id = :'p1' and c.estado = 'confirmado' and m.rango = 'fijo') = 6,
               'al crear el partido los 6 fijos quedan convocados');
select t_check((select estado from partidos where id = :'p1') = 'completo', 'partido completo con los fijos');
select t_check((select bool_and(rango = 'fijo') from convocatorias where partido_id = :'p1'), 'inscripción con rango fijo');

select t_como(309);
insert into convocatorias (partido_id, miembro_id) values (:'p1', t_m(309));
select t_como(307);
insert into convocatorias (partido_id, miembro_id) values (:'p1', t_m(307));
select t_check((select count(*) from convocatorias where partido_id = :'p1' and estado = 'espera') = 2,
               'invitado y reserva quedan en espera');
update convocatorias set rango = 'fijo' where partido_id = :'p1' and miembro_id = t_m(307);
select t_check((select rango from convocatorias where partido_id = :'p1' and miembro_id = t_m(307)) = 'reserva',
               'un jugador no puede cambiar el rango de su inscripción');

select t_como(306);
update convocatorias set estado = 'baja' where partido_id = :'p1' and miembro_id = t_m(306);
select t_check((select estado from convocatorias where partido_id = :'p1' and miembro_id = t_m(307)) = 'confirmado',
               'baja de un fijo → entra el reserva aunque el invitado se apuntó antes (prioridad)');
select t_check((select estado from convocatorias where partido_id = :'p1' and miembro_id = t_m(309)) = 'espera',
               'el invitado sigue en espera');
update convocatorias set estado = 'confirmado' where partido_id = :'p1' and miembro_id = t_m(306);
select t_check((select estado from convocatorias where partido_id = :'p1' and miembro_id = t_m(306)) = 'espera',
               'el fijo que vuelve con el partido lleno queda en espera (no desplaza a nadie)');
select t_como(305);
update convocatorias set estado = 'baja' where partido_id = :'p1' and miembro_id = t_m(305);
select t_check((select estado from convocatorias where partido_id = :'p1' and miembro_id = t_m(306)) = 'confirmado',
               'el fijo que volvió es el primero de la espera (antes que el invitado)');
select t_check((select estado from convocatorias where partido_id = :'p1' and miembro_id = t_m(309)) = 'espera',
               'el invitado sigue esperando');

-- Modo por orden de anotación
select t_como(301);
update ligas set orden_espera = 'anotacion' where id = :'lv';
select crear_partido(:'lv', '2027-03-03 21:00 Europe/Madrid', 0) as p1b \gset
select t_como(309);
insert into convocatorias (partido_id, miembro_id) values (:'p1b', t_m(309));
select t_como(307);
insert into convocatorias (partido_id, miembro_id) values (:'p1b', t_m(307));
select t_como(304);
update convocatorias set estado = 'baja' where partido_id = :'p1b' and miembro_id = t_m(304);
select t_check((select estado from convocatorias where partido_id = :'p1b' and miembro_id = t_m(309)) = 'confirmado',
               'por anotación: entra el invitado, que se apuntó antes que el reserva');
select t_como(301);
update ligas set orden_espera = 'prioridad' where id = :'lv';
update partidos set estado = 'cancelado' where id = :'p1b';

-- ═════════ 3. Cobro por factura mensual ═════════
update ligas set modo_cobro = 'factura_mensual', precio_invitado = 5 where id = :'lv';
select crear_partido(:'lv', '2027-03-08 21:00 Europe/Madrid', 0) as p2 \gset
select guardar_equipos(:'p1', jsonb_build_object(t_m(301), 1, t_m(302), 1, t_m(303), 1, t_m(304), 2, t_m(306), 2, t_m(307), 2));
select marcar_jugado(:'p1');
select t_check((select count(*) from movimientos where partido_id = :'p1') = 1
               and (select importe from movimientos where partido_id = :'p1' and miembro_id = t_m(307)) = -5,
               'al jugar: el reserva paga 5 € y los fijos nada');
select guardar_equipos(:'p2', jsonb_build_object(t_m(301), 1, t_m(302), 1, t_m(303), 1, t_m(304), 2, t_m(305), 2, t_m(306), 2));
select marcar_jugado(:'p2');
select t_check(not exists (select 1 from movimientos where partido_id = :'p2'), 'partido solo de fijos: sin cargos');

-- El rango que cuenta es el del día del partido
select cambiar_rango(t_m(307), 'fijo');
select t_check((select rango from convocatorias where partido_id = :'p1' and miembro_id = t_m(307)) = 'reserva',
               'cambiar el rango después no cambia el de la inscripción jugada');

insert into facturas (liga_id, archivo_path, importe, periodo_desde, periodo_hasta)
values (:'lv', :'lv' || '/marzo.pdf', 100, '2027-03-01', '2027-03-31') returning id as fmar \gset
select simular_factura(:'fmar') as sim \gset
\echo :sim
select t_check((:'sim'::jsonb ->> 'pagado_invitados')::numeric = 5 and (:'sim'::jsonb ->> 'resto')::numeric = 95
               and (:'sim'::jsonb ->> 'partidos')::int = 11,
               'marzo: 100 − 5 del reserva = 95 entre 11 partidos de fijos');
select t_check((select (c ->> 'importe')::numeric from jsonb_array_elements(:'sim'::jsonb -> 'cargos') c
                 where c ->> 'miembro_id' = t_m(301)::text) = 17.28, 'u301 (2 partidos, el más antiguo): 17,27 + 0,01 de redondeo');
select t_check((select (c ->> 'importe')::numeric from jsonb_array_elements(:'sim'::jsonb -> 'cargos') c
                 where c ->> 'miembro_id' = t_m(302)::text) = 17.27, 'u302 (2 partidos): 95/11 × 2 = 17,27');
select t_check((select (c ->> 'importe')::numeric from jsonb_array_elements(:'sim'::jsonb -> 'cargos') c
                 where c ->> 'miembro_id' = t_m(305)::text) = 8.64, 'u305 (1 partido): 8,64');
select t_check(not exists (select 1 from jsonb_array_elements(:'sim'::jsonb -> 'cargos') c
                            where c ->> 'miembro_id' = t_m(307)::text), 'el reserva no entra en el reparto');
select t_check((select sum((c ->> 'importe')::numeric) from jsonb_array_elements(:'sim'::jsonb -> 'cargos') c) = 95,
               'el reparto suma exactamente 95,00');
select t_check(not exists (select 1 from movimientos where factura_id = :'fmar'), 'simular no escribe nada');
select t_como(302);
select t_debe_fallar(format('select simular_factura(%L)', :'fmar'), 'solo un admin simula la factura');
select t_como(301);
select liquidar_factura(:'fmar');
select t_check((select count(*) from movimientos where factura_id = :'fmar') = 6
               and (select sum(importe) from movimientos where factura_id = :'fmar') = -95, 'liquidada: 6 cargos por 95 €');
select t_check((select liquidada from facturas where id = :'fmar'), 'factura marcada como liquidada');
select t_debe_fallar(format('select liquidar_factura(%L)', :'fmar'), 'no se liquida dos veces');
select t_check((select saldo from v_saldos where miembro_id = t_m(301)) = -17.28, 'saldo de u301: −17,28');
select t_check((select saldo from v_saldos where miembro_id = t_m(307)) = -5, 'saldo del reserva: −5');
insert into facturas (liga_id, archivo_path, importe) values (:'lv', :'lv' || '/sin.pdf', 50) returning id as fsin \gset
select t_debe_fallar(format('select simular_factura(%L)', :'fsin'), 'factura sin periodo: no se puede repartir');

-- Precio variable (null): los no fijos entran en el reparto
select cambiar_rango(t_m(307), 'reserva');
update ligas set precio_invitado = null where id = :'lv';
select crear_partido(:'lv', '2027-04-05 21:00 Europe/Madrid', 0) as p3 \gset
select t_como(309);
insert into convocatorias (partido_id, miembro_id) values (:'p3', t_m(309));
select t_como(301);
update convocatorias set estado = 'baja' where partido_id = :'p3' and miembro_id = t_m(301);
select t_check((select estado from convocatorias where partido_id = :'p3' and miembro_id = t_m(309)) = 'confirmado',
               'abril: entra el invitado por la baja de u301');
select guardar_equipos(:'p3', jsonb_build_object(t_m(309), 1, t_m(302), 1, t_m(303), 1, t_m(304), 2, t_m(305), 2, t_m(306), 2));
select marcar_jugado(:'p3');
select t_check(not exists (select 1 from movimientos where partido_id = :'p3'), 'precio variable: nadie paga al jugar');
insert into facturas (liga_id, archivo_path, importe, periodo_desde, periodo_hasta)
values (:'lv', :'lv' || '/abril.pdf', 60, '2027-04-01', '2027-04-30') returning id as fabr \gset
select liquidar_factura(:'fabr') as liq \gset
select t_check((:'liq'::jsonb ->> 'cuota')::numeric = 10 and (:'liq'::jsonb ->> 'pagado_invitados')::numeric = 0,
               'abril: 60 € entre 6 asistencias = 10 € por partido');
select t_check((select importe from movimientos where factura_id = :'fabr' and miembro_id = t_m(309)) = -10,
               'el invitado paga la misma cuota que los fijos');
select t_check(not exists (select 1 from movimientos where factura_id = :'fabr' and miembro_id = t_m(301)),
               'u301 no jugó en abril: no paga');

-- ═════════ 4. Temporada: todos los lunes de septiembre a junio a las 21:00 ═════════
select t_como(302);
select t_debe_fallar(format('select programar_temporada(%L, %L, %L, array[1]::smallint[], %L)', :'lv', '2026-09-01', '2027-06-30', '21:00'),
                     'solo un admin programa la temporada');
select t_como(301);
select count(*) as esperado
  from generate_series('2026-09-01'::timestamp, '2027-06-30'::timestamp, interval '1 day') g
 where extract(isodow from g) = 1 and g::date not in ('2026-12-21', '2026-12-28')
   and ((g::date + time '21:00') at time zone 'Europe/Madrid') > now()
   and not exists (select 1 from partidos pa where pa.liga_id = :'lv' and pa.estado <> 'cancelado'
                    and (pa.fecha_hora at time zone 'Europe/Madrid')::date = g::date) \gset
select t_check(programar_temporada(:'lv', '2026-09-01', '2027-06-30', array[1]::smallint[], '21:00', true, 0,
                                   array['2026-12-21', '2026-12-28']::date[], 'Temporada 26/27') = :esperado,
               format('temporada: %s lunes futuros (sin los 2 excluidos ni los 3 que ya tenían partido)', :esperado));
select id as t1 from temporadas where liga_id = :'lv' and nombre = 'Temporada 26/27' \gset
select t_check((select count(*) from partidos where temporada_id = :'t1') = :esperado, 'partidos enlazados a la temporada');
select t_check(not exists (select 1 from partidos where temporada_id = :'t1'
                            and extract(isodow from fecha_hora at time zone 'Europe/Madrid') <> 1), 'todos en lunes');
select t_check((select (fecha_hora at time zone 'Europe/Madrid')::time = '21:00' and extract(hour from fecha_hora at time zone 'UTC') = 20
                  from partidos where temporada_id = :'t1' and (fecha_hora at time zone 'Europe/Madrid')::date = '2027-01-11'),
               'invierno: 21:00 en Madrid = 20:00 UTC');
select t_check((select (fecha_hora at time zone 'Europe/Madrid')::time = '21:00' and extract(hour from fecha_hora at time zone 'UTC') = 19
                  from partidos where temporada_id = :'t1' and (fecha_hora at time zone 'Europe/Madrid')::date = '2027-06-07'),
               'verano: 21:00 en Madrid = 19:00 UTC');
select t_check(not exists (select 1 from partidos where liga_id = :'lv'
                            and (fecha_hora at time zone 'Europe/Madrid')::date in ('2026-12-21', '2026-12-28')),
               'los lunes excluidos no tienen partido');
select t_check((select count(*) from partidos where liga_id = :'lv' and estado <> 'cancelado'
                 and (fecha_hora at time zone 'Europe/Madrid')::date = '2027-03-01') = 1, 'sin duplicar el lunes que ya tenía partido');
select t_check((select count(*) from convocatorias c join partidos p on p.id = c.partido_id
                 where p.temporada_id = :'t1' and (p.fecha_hora at time zone 'Europe/Madrid')::date = '2027-01-11'
                   and c.estado = 'confirmado') = 6, 'cada partido de la temporada nace con los 6 fijos convocados');
select t_check(programar_temporada(:'lv', '2026-09-01', '2027-06-30', array[1]::smallint[], '21:00', true, 0,
                                   array['2026-12-21', '2026-12-28']::date[]) = 0,
               'programar otra vez lo mismo no duplica nada');
select t_check(programar_temporada(:'lv', '2027-05-01', '2027-05-31', array[4]::smallint[], '20:00', false) = 4,
               'hora variable: 4 jueves de mayo de 2027');
select id as t2 from temporadas where liga_id = :'lv' and not hora_fija \gset
select t_check(not exists (select 1 from partidos where temporada_id = :'t2' and hora_confirmada),
               'hora variable: hora sin confirmar');
select t_debe_fallar(format('select programar_temporada(%L, %L, %L, array[1,2,3,4,5,6,7]::smallint[], %L)',
                            :'lv', '2027-01-01', '2027-12-31', '21:00'), 'más de 120 partidos de golpe');
select t_check(cancelar_temporada(:'t1', '2027-06-01') = 4, 'cancelar desde el 1 de junio: los 4 lunes de junio');
select t_check((select count(*) from partidos where temporada_id = :'t1' and estado = 'cancelado') = 4, '4 partidos cancelados');
select id as pjue from partidos where temporada_id = :'t2' order by fecha_hora limit 1 \gset
select cambiar_hora_partido(:'pjue', '2027-05-06 21:30 Europe/Madrid');
select t_check((select hora_confirmada and (fecha_hora at time zone 'Europe/Madrid')::time = '21:30' from partidos where id = :'pjue'),
               'hora del jueves confirmada a las 21:30');
select t_como(307);
select t_check((select count(*) from temporadas) = 2, 'los miembros ven las temporadas');

-- ═════════ 5. Fantasy: invitado por rango ═════════
select t_como(201);
select id as lf from ligas where nombre = 'Liga Fichas' \gset
select set_config('t.liga', :'lf', false);
select t_check(mercado_abierto(:'lf'), 'mercado de la liga Fichas abierto');
select cambiar_rango(t_m(207), 'invitado');
select cambiar_rango(t_m(206), 'invitado');
select t_check((select no_habitual from mercado_jugador where miembro_id = t_m(207)), 'pasar a invitado lo marca ×1,5 al momento');
select t_check((select no_habitual from v_mercado where miembro_id = t_m(206)), 'v_mercado lo muestra como invitado');
select t_como(208);
select t_check(comprar_ficha(:'lf', t_m(207)) is not null, 'u208 ficha a un invitado');
select t_debe_fallar(format('select comprar_ficha(%L, %L)', :'lf', t_m(206)), 'segundo invitado en la plantilla: no');
select t_check(comprar_ficha(:'lf', t_m(203)) is not null, 'fijos sin límite');
select t_como(201);
select cambiar_rango(t_m(207), 'fijo');
select t_check(not (select no_habitual from mercado_jugador where miembro_id = t_m(207)), 'volver a fijo quita el ×1,5');

-- ═════════ 6. Partes: verificación de goles ═════════
select set_config('t.liga', :'lv', false);
select t_jugar('2027-02-02 20:00 Europe/Madrid') as m1 \gset
select t_como(302);
select t_debe_fallar(format('select enviar_parte(%L, %L, %L)', :'m1', t_res(1, 1),
                            jsonb_build_array(t_jug(301, 4))), '1-1 con 4 goles de un jugador: rechazado');
select t_debe_fallar(format('select enviar_parte(%L, %L, %L)', :'m1', t_res(3, 1),
                            jsonb_build_array(t_jug(301, 2), t_jug(302, 0), t_jug(303, 0), t_jug(304, 1), t_jug(305, 0), t_jug(306, 0))),
                     'parte completo que suma 2 para un 3-1: rechazado');
select t_check(enviar_parte(:'m1', t_res(2, 1), jsonb_build_array(t_jug(301, 1))) = 2,
               'parte parcial ("no sé" el resto) que no supera el resultado: aceptado');
select t_check(enviar_parte(:'m1', null, jsonb_build_array(t_jug(301, 2))) = 1,
               'sin resultado en la llamada vale el ya guardado (2-1)');
select t_debe_fallar(format('select enviar_parte(%L, null, %L)', :'m1', jsonb_build_array(t_jug(301, 3))),
                     '3 goles con el 2-1 guardado: rechazado');
select t_check((select goles from reportes_jugador where partido_id = :'m1' and reportero_id = t_m(302) and sujeto_id = t_m(301)) = 2,
               'el parte rechazado no cambia nada');
select t_como(307);
select t_debe_fallar(format('select enviar_parte(%L, %L, %L)', :'m1', t_res(2, 1), jsonb_build_array(t_jug(301, 2))),
                     'quien no jugó no envía parte');

-- ═════════ 7. MVP ═════════
-- M1 2-1: u301 2 goles, u304 1 gol, u302 1 asistencia; u301 y u304 sacan un 9, el resto un 6
do $$
declare r int; s int; p uuid := (select id from partidos where liga_id = current_setting('t.liga')::uuid
                                   and (fecha_hora at time zone 'Europe/Madrid')::date = '2027-02-02');
begin
  for r in 301..306 loop
    perform t_como(r);
    perform enviar_parte(p, t_res(2, 1), jsonb_build_array(t_jug(301, 2), t_jug(302, 0, 1), t_jug(303, 0),
                                                         t_jug(304, 1), t_jug(305, 0), t_jug(306, 0)));
    for s in 301..306 loop
      if s <> r then perform t_votar(p, r, s, case when s in (301, 304) then 9 else 6 end); end if;
    end loop;
  end loop;
end $$;
select t_como(301);
select t_check(cerrar_post_partido(:'m1') = 'cerrado', 'M1 cerrado sin disputas');
select t_check((select es_mvp from puntos_fantasy where partido_id = :'m1' and miembro_id = t_m(301))
               and not (select es_mvp from puntos_fantasy where partido_id = :'m1' and miembro_id = t_m(304)),
               'empate a nota (9): MVP para quien tiene más goles + asistencias (u301)');
select t_check((select total from puntos_fantasy where partido_id = :'m1' and miembro_id = t_m(301)) = 22,
               'u301: 2 + 3 + 10 + 4 (nota 9) + 3 (MVP) = 22');
select t_check((select total from puntos_fantasy where partido_id = :'m1' and miembro_id = t_m(304)) = 11, 'u304: 2 + 5 + 4 = 11');
select t_check((select total from puntos_fantasy where partido_id = :'m1' and miembro_id = t_m(302)) = 10, 'u302: 2 + 3 + 3 + 2 = 10');
select t_check((select count(*) from v_mvps where partido_id = :'m1') = 1, 'un único MVP en M1');

-- M2 1-1: u301 y u304 1 gol cada uno y un 9 → MVP compartido
select t_jugar('2027-02-09 20:00 Europe/Madrid') as m2 \gset
select set_config('t.m2', :'m2', false);
do $$
declare r int; s int; p uuid := current_setting('t.m2')::uuid;
begin
  for r in 301..306 loop
    perform t_como(r);
    perform enviar_parte(p, t_res(1, 1), jsonb_build_array(t_jug(301, 1), t_jug(302, 0), t_jug(303, 0),
                                                         t_jug(304, 1), t_jug(305, 0), t_jug(306, 0)));
    for s in 301..306 loop
      if s <> r then perform t_votar(p, r, s, case when s in (301, 304) then 9 else 6 end); end if;
    end loop;
  end loop;
end $$;
select t_como(301);
select t_check(cerrar_post_partido(:'m2') = 'cerrado', 'M2 cerrado');
select t_check((select count(*) from puntos_fantasy where partido_id = :'m2' and es_mvp) = 2
               and (select bool_and(total = 15) from puntos_fantasy where partido_id = :'m2' and es_mvp),
               'empate total: MVP compartido, 2 + 1 + 5 + 4 + 3 = 15 cada uno');

-- M3 0-0 con pocos votos: nadie llega a 3 votantes → sin nota oficial (pero sí MVP, 0025)
select t_jugar('2027-02-16 20:00 Europe/Madrid') as m3 \gset
select set_config('t.m3', :'m3', false);
do $$
declare r int; s int; p uuid := current_setting('t.m3')::uuid;
begin
  for r in 301..306 loop
    perform t_como(r);
    perform enviar_parte(p, t_res(0, 0), jsonb_build_array(t_jug(301, 0), t_jug(302, 0), t_jug(303, 0),
                                                         t_jug(304, 0), t_jug(305, 0), t_jug(306, 0)));
  end loop;
  for s in 302..306 loop perform t_votar(p, 301, s, 10); end loop;   -- u301 vota a todos
  perform t_votar(p, 302, 304, 10);                                    -- u302 solo a u304
end $$;
select t_como(301);
select t_check(cerrar_post_partido(:'m3') = 'cerrado', 'M3 cerrado');
-- 0025: con menos de 3 votantes sigue habiendo MVP entre los más votados (aquí 2): u304, sin nota oficial
select t_check((select array_agg(miembro_id) from puntos_fantasy where partido_id = :'m3' and es_mvp) = array[t_m(304)],
               'menos de 3 votantes: MVP entre los que más votos tienen (u304)');
select t_check((select num_votantes = 2 and nota_media is null from puntos_fantasy where partido_id = :'m3' and miembro_id = t_m(304)),
               'u304: 2 votantes → sin nota');
select t_check((select num_votantes = 1 and nota_media is null from puntos_fantasy where partido_id = :'m3' and miembro_id = t_m(302)),
               'u302: un único votante → sin nota');
select t_check((select bool_and(total = case when miembro_id = t_m(304) then 6 else 3 end) from puntos_fantasy where partido_id = :'m3'),
               'M3: todos 2 + 1 (empate) = 3; u304 + 3 de MVP = 6');
select t_debe_fallar(format('select calcular_puntos(%L)', :'m3'), 'un partido cerrado no se vuelve a puntuar');
select t_check((select count(*) from puntos_fantasy where partido_id = :'m3') = 6, 'sin filas duplicadas');

-- ═════════ 8. Descuadre en el acta consolidada ═════════
-- 2-0 para el equipo 1; cuatro dicen que u301 marcó 1 y nadie sabe quién marcó el otro
select t_jugar('2027-02-23 20:00 Europe/Madrid') as m4 \gset
select set_config('t.m4', :'m4', false);
do $$
declare r int; p uuid := current_setting('t.m4')::uuid;
begin
  for r in 301..304 loop
    perform t_como(r);
    perform enviar_parte(p, t_res(2, 0), jsonb_build_array(t_jug(301, 1), t_jug(303, 0), t_jug(304, 0),
                                                         t_jug(305, 0), t_jug(306, 0)));
  end loop;
  for r in 305..306 loop
    perform t_como(r);
    perform enviar_parte(p, t_res(2, 0), jsonb_build_array(t_jug(303, 0), t_jug(304, 0), t_jug(305, 0), t_jug(306, 0)));
  end loop;
end $$;
select t_como(301);
select t_check(cerrar_post_partido(:'m4') = 'en_revision', 'la suma de goles (1) no cuadra con el 2-0: a revisión');
select id as dq from disputas where partido_id = :'m4' and tipo = 'descuadre' \gset
select t_check((select campo = 'goles_equipo_1' and (valores ->> 'resultado')::int = 2 and (valores ->> 'suma_jugadores')::int = 1
                  from disputas where id = :'dq'), 'disputa de descuadre del equipo 1: resultado 2, suma 1');
select t_check((select count(*) from disputas where partido_id = :'m4' and not resuelta) = 1, 'solo el descuadre queda abierto');
select t_debe_fallar(format('select calcular_puntos(%L)', :'m4'), 'el descuadre bloquea los puntos');
select t_debe_fallar(format('select resolver_disputa(%L, 2::smallint)', :'dq'), 'un descuadre no se resuelve eligiendo un valor');
select t_como(302);
select t_debe_fallar(format('select fijar_dato(p_partido => %L, p_sujeto => %L, p_campo => %L, p_valor => 1::smallint)', :'m4', t_m(302), 'goles'),
                     'solo un admin corrige datos');
select t_como(301);
select t_check(fijar_dato(p_partido => :'m4', p_sujeto => t_m(302), p_campo => 'goles', p_valor => 1::smallint) = 'cerrado',
               'el admin asigna el otro gol a u302: cuadra y se calculan los puntos');
select t_check((select goles from acta_jugador where partido_id = :'m4' and miembro_id = t_m(302)) = 1, 'acta: u302 1 gol');
select t_check(not exists (select 1 from disputas where partido_id = :'m4' and not resuelta), 'sin disputas abiertas');
select t_check((select total from puntos_fantasy where partido_id = :'m4' and miembro_id = t_m(302)) = 10, 'u302: 2 + 3 + 5 = 10');

-- Corrección del resultado de un encuentro con fijar_dato (p_n) en un partido aún abierto a partes
select t_jugar('2027-02-24 20:00 Europe/Madrid') as m5 \gset
select t_check(fijar_dato(p_partido => :'m5', p_n => 1::smallint, p_campo => 'goles_local', p_valor => 0::smallint) = 'post_partido',
               'fijar_dato del resultado durante el post-partido: se guarda y se aplicará al consolidar');
update partidos set estado = 'cancelado' where id = :'m5';

-- ═════════ 9. Estadísticas ═════════
select t_como(305);
\echo 'Rendimiento (Liga Lunes):'
select m.id = t_m(301) as u301, r.partidos, r.goles, r.asistencias, r.mvps, r.victorias, r.empates, r.pct_victorias, r.puntos_total
  from v_rendimiento r join miembros m on m.id = r.miembro_id where r.liga_id = :'lv' order by r.puntos_total desc;
select t_check((select partidos = 4 and goles = 4 and mvps = 2 and victorias = 2 and empates = 2 and pct_victorias = 50.0
                  and puntos_total = 22 + 15 + 3 + 10
                  from v_rendimiento where miembro_id = t_m(301)),
               'u301: 4 partidos, 4 goles, 2 MVP, 50 % de victorias, 50 puntos');
select t_check((select asistencias = 1 and goles = 1 and mvps = 0 from v_rendimiento where miembro_id = t_m(302)),
               'u302: 1 asistencia, 1 gol');
select t_check((select mvps from v_rendimiento where miembro_id = t_m(304)) = 2, 'u304: 2 MVP (compartido en M2 y M3 con pocos votantes)');
select t_check((select miembro_id from v_pichichi where liga_id = :'lv' and posicion = 1) = t_m(301), 'pichichi: u301');
select t_check((select count(*) from v_mvps where liga_id = :'lv') = 4, 'v_mvps: 4 MVP en la liga (1 + 2 compartidos + 1 con pocos votantes)');
select t_check((select posicion from v_clasificacion where miembro_id = t_m(301)) = 1, 'clasificación: u301 primero');

-- ═════════ 10. Permisos ═════════
select t_debe_fallar(format('select comprobar_descuadres(%L)', :'m4'), 'comprobar_descuadres es interna');
select t_debe_fallar(format('select calculo_factura(%L)', :'fmar'), 'calculo_factura es interna');
select t_debe_fallar(format('select inscribir_fijos(%L)', :'p2'), 'inscribir_fijos es interna');
select t_debe_fallar('insert into temporadas (liga_id, desde, hasta, dias_semana, hora) values (gen_random_uuid(), current_date, current_date, array[1]::smallint[], ''20:00'')',
                     'nadie escribe en temporadas directamente');
reset role;
set role anon;
select t_debe_fallar('select count(*) from temporadas', 'anon no lee temporadas');
select t_debe_fallar('select count(*) from v_mvps', 'anon no lee v_mvps');
reset role;
select t_check(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname in ('programar_temporada', 'liquidar_factura', 'enviar_parte',
                                                                         'fijar_dato', 'cambiar_rango')
                              and has_function_privilege('anon', p.oid, 'execute')), 'anon no ejecuta las RPC nuevas');
select t_check(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.prosecdef
                              and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
                              and p.proname in ('prioridad_espera', 'inscribir_fijos', 'programar_temporada', 'calculo_factura',
                                                'liquidar_factura', 'comprobar_descuadres', 'fijar_dato', 'enviar_parte',
                                                'cambiar_rango', 'es_no_habitual')),
               'todas las funciones nuevas fijan search_path');

\echo '══════ ESCENARIO V0.3 COMPLETADO SIN ERRORES ══════'
