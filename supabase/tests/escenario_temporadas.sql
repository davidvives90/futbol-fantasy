\set ON_ERROR_STOP 1
\pset pager off
reset role;
select set_config('t.liga', (select id::text from ligas where nombre = 'Liga Lunes'), false);
select set_config('t.admin', (select perfil_id::text from miembros where liga_id = current_setting('t.liga')::uuid and rol = 'admin'
                                and estado = 'activo' limit 1), false);
select set_config('t.jug', (select perfil_id::text from miembros where liga_id = current_setting('t.liga')::uuid and rol = 'jugador'
                              and estado = 'activo' and perfil_id is not null order by unido_en, id limit 1), false);
select set_config('t.part', (select id::text from partidos where liga_id = current_setting('t.liga')::uuid and estado = 'cerrado'
                               order by fecha_hora desc limit 1), false);
set role authenticated;
select t_como_uid(current_setting('t.jug')::uuid);

-- compartir
select resumen_compartir(current_setting('t.part')::uuid) as r \gset
\echo :r
select t_check(jsonb_array_length(:'r'::jsonb -> 'encuentros') >= 1 and (:'r'::jsonb -> 'equipos') <> '{}'::jsonb, 'resumen con equipos y resultado');
select t_check(jsonb_array_length(:'r'::jsonb -> 'confirmados') >= 2, 'resumen con convocados');

-- rendimiento por periodo = histórico cuando no hay temporadas_cerradas
select t_check((select count(*) from rendimiento_periodo(current_setting('t.liga')::uuid))
               = (select count(*) from v_rendimiento where liga_id = current_setting('t.liga')::uuid), 'periodo completo = histórico');
select t_check((select sum(goles) from rendimiento_periodo(current_setting('t.liga')::uuid))
               = (select sum(goles) from v_rendimiento where liga_id = current_setting('t.liga')::uuid), 'mismos goles');

-- temporadas_cerradas
select t_debe_fallar(format($$select cerrar_temporada(%L)$$, current_setting('t.liga')), 'jugador no cierra temporada');
select t_como_uid(current_setting('t.admin')::uuid);
reset role;
-- partidos a medias de pruebas anteriores: los damos por cerrados para poder cerrar la temporada
update partidos set estado = 'cancelado' where liga_id = current_setting('t.liga')::uuid and estado in ('jugado', 'post_partido', 'en_revision');
set role authenticated;
select cerrar_temporada(current_setting('t.liga')::uuid, 'Otoño') as tid \gset
select t_check((select nombre = 'Otoño' and numero = 1 and partidos >= 1 and jsonb_array_length(clasificacion) >= 2
                  from temporadas_cerradas where id = :'tid'), 'temporada guardada con clasificación');
select t_check((select count(distinct tipo) >= 4 from premios where temporada_id = :'tid'), 'premios repartidos');
select t_check(exists (select 1 from premios where temporada_id = :'tid' and tipo = 'campeon'), 'hay campeón');
select t_check(inicio_temporada(current_setting('t.liga')::uuid) is not null, 'nueva temporada empieza');
select t_check((select count(*) from rendimiento_periodo(current_setting('t.liga')::uuid, inicio_temporada(current_setting('t.liga')::uuid))) = 0,
               'clasificación de la nueva temporada vacía');
select t_debe_fallar(format($$select cerrar_temporada(%L)$$, current_setting('t.liga')), 'no se cierra una temporada sin partidos');
select reabrir_temporada(current_setting('t.liga')::uuid);
select t_check(not exists (select 1 from temporadas_cerradas where id = :'tid') and not exists (select 1 from premios where temporada_id = :'tid'),
               'reabrir deshace el cierre');
select cerrar_temporada(current_setting('t.liga')::uuid);
select t_check((select nombre from temporadas_cerradas where liga_id = current_setting('t.liga')::uuid) = 'Temporada 1', 'nombre por defecto');

-- aviso de fin de baja
reset role;
insert into ausencias (liga_id, miembro_id, desde, hasta, motivo)
select current_setting('t.liga')::uuid, id, current_date - 20, current_date - 1, 'lesion'
  from miembros where perfil_id = current_setting('t.jug')::uuid and liga_id = current_setting('t.liga')::uuid;
select enviar_recordatorios();
select t_check(exists (select 1 from notificaciones where tipo = 'fin_baja' and perfil_id = current_setting('t.jug')::uuid), 'aviso de fin de baja');
select enviar_recordatorios();
select t_check((select count(*) from notificaciones where tipo = 'fin_baja' and perfil_id = current_setting('t.jug')::uuid) = 1, 'solo una vez');
\echo '══════ ESCENARIO TEMPORADAS Y COMPARTIR COMPLETADO SIN ERRORES ══════'
