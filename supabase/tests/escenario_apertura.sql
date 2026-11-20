-- Escenario 0026 · Convocatoria con apertura, vacía y plazas reservadas a fijos
\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);
update ligas set modo_convocatoria = 'apertura', duracion_partido_min = 60, horas_apertura_convocatoria = 2,
                 horas_reserva_fijos = 24
 where id = current_setting('t.liga')::uuid;
-- Datos de la liga: dos fijos y dos reservas con perfil
update miembros set rango = 'reserva' where liga_id = current_setting('t.liga')::uuid and rango = 'invitado';
select (array_agg(perfil_id order by id))[1] as f1, (array_agg(perfil_id order by id))[2] as f2, count(*) as nfijos
  from miembros where liga_id = current_setting('t.liga')::uuid and rango = 'fijo' and estado = 'activo' and perfil_id is not null \gset
select (array_agg(perfil_id order by id))[1] as r1, (array_agg(perfil_id order by id))[2] as r2
  from miembros where liga_id = current_setting('t.liga')::uuid and rango = 'reserva' and estado = 'activo' and perfil_id is not null \gset
select count(*) as fijos_total from miembros where liga_id = current_setting('t.liga')::uuid and rango = 'fijo'
   and estado in ('activo', 'pendiente_registro') \gset
select t_check(:'r2' is not null and :'f2' is not null, 'hay 2 fijos y 2 reservas');

update partidos set estado = 'cancelado'
 where liga_id = current_setting('t.liga')::uuid and fecha_hora between now() - interval '5 hours' and now() + interval '11 days';
-- partido anterior (hace 5 h) → el siguiente se abrió hace 2 h; el de después aún no
insert into partidos (liga_id, fecha_hora, plazas, num_equipos, estado)
values (current_setting('t.liga')::uuid, now() - interval '5 hours', 10, 2, 'cerrado');
insert into partidos (liga_id, fecha_hora, plazas, num_equipos, estado)
values (current_setting('t.liga')::uuid, now() + interval '3 days', :'fijos_total', 2, 'abierto') returning id as p2 \gset
insert into partidos (liga_id, fecha_hora, plazas, num_equipos, estado)
values (current_setting('t.liga')::uuid, now() + interval '10 days', 10, 2, 'abierto') returning id as p3 \gset

select t_check(not exists (select 1 from convocatorias where partido_id = :'p2'), 'la convocatoria nace vacía (ni los fijos)');
select t_check(convocatoria_abre_en(:'p2') <= now() and convocatoria_abre_en(:'p3') > now(), 'p2 abierta, p3 aún no');
select t_check(plazas_reservadas_fijos(:'p2') = :'fijos_total', 'todas las plazas guardadas a los fijos');

set role authenticated;
select t_como_uid(:'r1');
select t_debe_fallar(format('insert into convocatorias (partido_id, miembro_id, estado) values (%L, mi_miembro(%L), %L)',
                            :'p3', current_setting('t.liga'), 'confirmado'), 'no se apunta nadie antes de abrir');
insert into convocatorias (partido_id, miembro_id, estado) values (:'p2', mi_miembro(current_setting('t.liga')::uuid), 'confirmado');
select t_check((select estado from convocatorias where partido_id = :'p2' and miembro_id = mi_miembro(current_setting('t.liga')::uuid)) = 'espera',
               'un reserva va a la espera: las plazas son de los fijos hasta 24 h antes');
select t_como_uid(:'f1');
insert into convocatorias (partido_id, miembro_id, estado) values (:'p2', mi_miembro(current_setting('t.liga')::uuid), 'confirmado');
select t_check((select estado from convocatorias where partido_id = :'p2' and miembro_id = mi_miembro(current_setting('t.liga')::uuid)) = 'confirmado',
               'un fijo que pulsa Voy entra');
select t_como_uid(:'f2');
insert into convocatorias (partido_id, miembro_id, estado) values (:'p2', mi_miembro(current_setting('t.liga')::uuid), 'baja');
reset role;
select t_check((select c.estado from convocatorias c join miembros m on m.id = c.miembro_id
                 where c.partido_id = :'p2' and m.perfil_id = :'r1') = 'confirmado',
               'un fijo dice «No voy» → su plaza pasa al primero de la espera');

-- fin de la reserva: las plazas sin contestar pasan a la espera
set role authenticated;
select t_como_uid(:'r2');
insert into convocatorias (partido_id, miembro_id, estado) values (:'p2', mi_miembro(current_setting('t.liga')::uuid), 'confirmado');
reset role;
select t_check((select c.estado from convocatorias c join miembros m on m.id = c.miembro_id
                 where c.partido_id = :'p2' and m.perfil_id = :'r2') = 'espera', 'segundo reserva, a la espera');
update partidos set fecha_hora = now() + interval '20 hours' where id = :'p2';
select enviar_recordatorios();
select t_check((select c.estado from convocatorias c join miembros m on m.id = c.miembro_id
                 where c.partido_id = :'p2' and m.perfil_id = :'r2') = 'confirmado',
               'a 24 h del partido las plazas libres de fijos pasan a la lista de espera');
select t_check(exists (select 1 from notificaciones n where n.tipo = 'entras' and n.perfil_id = :'r2'), 'aviso «¡Entras!»');

-- fantasy desactivable
update ligas set fantasy_activo = false where id = current_setting('t.liga')::uuid;
select t_check(not (select fantasy_activo from ligas where id = current_setting('t.liga')::uuid), 'Fantasy desactivado');
update ligas set fantasy_activo = true, modo_convocatoria = 'clasica' where id = current_setting('t.liga')::uuid;
\echo '══════ ESCENARIO APERTURA COMPLETADO SIN ERRORES ══════'
