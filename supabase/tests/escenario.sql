-- Escenario completo de una liga, ejecutado como usuarios reales (rol authenticated + RLS).
-- Requiere 00_stubs.sql y las migraciones aplicadas. Se detiene al primer error o aserción fallida.
\set ON_ERROR_STOP 1
\pset pager off

-- ───────── Utilidades de prueba (como postgres) ─────────
create or replace function t_uid(i int) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid $$;

create or replace function t_como(i int) returns void language sql as $$
  select set_config('request.jwt.claim.sub', t_uid(i)::text, false) $$;

-- id de miembro del usuario i en la liga de prueba
create or replace function t_m(i int) returns uuid language sql stable security definer as $$
  select id from miembros where perfil_id = t_uid(i) and liga_id = current_setting('t.liga')::uuid $$;

create or replace function t_check(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FALLA: %', msg; end if;
  raise notice 'OK  %', msg;
end $$;

-- Ejecuta SQL que DEBE fallar
create or replace function t_debe_fallar(p_sql text, msg text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'OK  % (rechazado: %)', msg, sqlerrm;
    return;
  end;
  raise exception 'FALLA: debía rechazarse → %', msg;
end $$;

grant execute on function t_uid, t_como, t_m, t_check, t_debe_fallar to authenticated;

-- 14 usuarios con perfil. Porteros: u2 y u7.
insert into auth.users (id, email) select t_uid(i), 'u' || i || '@test' from generate_series(1, 14) i;
insert into perfiles (id, nombre, posicion)
select t_uid(i), 'Jugador ' || i,
       (case when i in (2, 7) then 'portero' when i % 3 = 0 then 'defensa'
             when i % 3 = 1 then 'medio' else 'delantero' end)::posicion_campo
  from generate_series(1, 14) i;

set role authenticated;

-- ═════════ 1. Crear liga (u1 queda como admin) ═════════
select t_como(1);
select crear_liga('{"nombre":"Pachanga Jueves","ciudad":"Madrid","campo_nombre":"Polideportivo Norte",
                   "campo_maps_url":"https://maps.app.goo.gl/abc123","precio_estimado":6.5,
                   "jugadores_por_equipo":5,"num_equipos":2}') as liga \gset
select set_config('t.liga', :'liga', false);
select codigo_invitacion as codigo from ligas where id = :'liga' \gset
select set_config('t.codigo', :'codigo', false);

select t_check((select plazas from ligas where id = :'liga') = 10, 'fútbol 5 × 2 equipos = 10 plazas');
select t_check((select rol from miembros where liga_id = :'liga' and perfil_id = t_uid(1)) = 'admin', 'el creador es admin');
select t_check((select count(*) from reglas_puntuacion where liga_id = :'liga') = 18, 'reglas por defecto sembradas');
select t_check((select count(*) from aspectos_valoracion where liga_id = :'liga') = 6, 'aspectos por defecto sembrados');
select t_debe_fallar($$select crear_liga('{"nombre":"Mala","campo_maps_url":"http://inseguro"}')$$, 'URL de Maps sin https');
-- Contrato con la app: crear_liga acepta puntuar_por_posicion y horas_post_partido
select crear_liga('{"nombre":"Liga sin posiciones","jugadores_por_equipo":7,"num_equipos":3,
                   "puntuar_por_posicion":false,"horas_post_partido":24}') as liga2 \gset
select t_check((select not puntuar_por_posicion and horas_post_partido = 24 and plazas = 21
                  from ligas where id = :'liga2'), 'crear_liga guarda puntuar_por_posicion y horas_post_partido');

-- ═════════ 2. Pre-crear 2 jugadores (enlaces personales) ═════════
select string_agg(token, ',' order by nombre) as tokens
  from precrear_jugadores(:'liga', array['Juan', 'Pepe'], array['600111222', null]) \gset
select split_part(:'tokens', ',', 1) as tok_juan, split_part(:'tokens', ',', 2) as tok_pepe \gset
select t_check((select count(*) from enlaces_invitacion(:'liga')) = 2, 'admin ve 2 enlaces pendientes');

select t_como(2);
select t_debe_fallar($$select * from enlaces_invitacion(current_setting('t.liga')::uuid)$$,
                     'un no-admin no puede ver tokens');
select t_debe_fallar($$select token_invitacion from miembros$$, 'columna token_invitacion no legible');
select t_check((select count(*) from (select id, liga_id, perfil_id, nombre_provisional, posicion, rol, estado,
                                              invitado_por, unido_en from miembros) t) >= 0,
               'las columnas que pide la app (Miembro.select) son legibles');

-- ═════════ 3. Unirse ═════════
-- u2..u11 con el código general
do $$ begin
  for i in 2..11 loop perform t_como(i); perform unirse(lower(current_setting('t.codigo'))); end loop;
end $$;
-- u12 reclama la ficha de Juan, u13 la de Pepe
select t_como(12); select unirse(:'tok_juan');
select t_como(13); select unirse(:'tok_pepe');
select t_check((select count(*) from miembros where liga_id = :'liga' and estado = 'pendiente_registro') = 0,
               'las fichas pre-creadas se han reclamado');
select t_check((select nombre_provisional from miembros where perfil_id = t_uid(12)) = 'Juan',
               'u12 hereda la ficha de Juan');
select t_debe_fallar(format('select unirse(%L)', :'tok_juan'), 'un token usado no vale dos veces');

-- u14 por el buscador: la liga pasa a pública con aprobación
select t_como(1);
update ligas set visibilidad = 'publica' where id = :'liga';
select t_como(14);
select t_check((select count(*) from buscar_ligas('pachanga')) = 1, 'la liga aparece en el buscador');
select t_check(solicitar_unirse(:'liga') = 'solicitud', 'u14 queda en solicitud');
select t_check(not es_miembro(:'liga'), 'en solicitud aún no es miembro');
select t_como(1);
select aprobar_solicitud(t_m(14));
select t_check((select count(*) from miembros where liga_id = :'liga' and estado = 'activo') = 14,
               '14 miembros activos');

-- ═════════ 4. Administradores ═════════
select t_como(5);
select t_debe_fallar(format('select cambiar_rol(%L, ''admin'')', t_m(5)), 'un jugador no se nombra admin');
select t_debe_fallar(format('update ligas set nombre = ''Hackeada'' where id = %L', :'liga')
                     || ' returning 1/0', 'un jugador no edita la liga');
select t_check((select nombre from ligas where id = :'liga') = 'Pachanga Jueves', 'nombre sin cambios');
select t_como(1);
select cambiar_rol(t_m(2), 'admin');
select t_check(num_admins(:'liga') = 2, 'u2 nombrado admin');
select cambiar_rol(t_m(2), 'jugador');
select t_debe_fallar(format('select cambiar_rol(%L, ''jugador'')', t_m(1)), 'no se quita al último admin');
select t_debe_fallar(format('select abandonar_liga(%L)', :'liga'), 'el último admin no puede irse');
select cambiar_rol(t_m(2), 'admin');

-- ═════════ 5. Convocatoria: 12 se apuntan a 10 plazas ═════════
select t_como(1);
select crear_partido(:'liga', now() + interval '2 days', 50) as partido \gset
select set_config('t.partido', :'partido', false);
select t_check((select plazas from partidos where id = :'partido') = 10, 'partido copia 10 plazas de la liga');

do $$ begin
  for i in 1..12 loop
    perform t_como(i);
    insert into convocatorias (partido_id, miembro_id)
    values (current_setting('t.partido')::uuid, t_m(i));
  end loop;
end $$;
select t_check((select count(*) from convocatorias where partido_id = :'partido' and estado = 'confirmado') = 10, '10 confirmados');
select t_check((select count(*) from convocatorias where partido_id = :'partido' and estado = 'espera') = 2, '2 en lista de espera');
select t_check((select estado from partidos where id = :'partido') = 'completo', 'partido completo');

select t_como(13);
select t_debe_fallar(format('insert into convocatorias (partido_id, miembro_id) values (%L, %L)', :'partido', t_m(5)),
                     'no se puede apuntar a otro');

-- u3 se da de baja → sube u11 (primero en espera)
select t_como(3);
update convocatorias set estado = 'baja' where partido_id = :'partido' and miembro_id = t_m(3);
select t_check((select estado from convocatorias where partido_id = :'partido' and miembro_id = t_m(11)) = 'confirmado',
               'baja de u3 promueve a u11');
select t_check((select estado from convocatorias where partido_id = :'partido' and miembro_id = t_m(12)) = 'espera',
               'u12 sigue en espera');
-- u3 vuelve: va al final de la cola
update convocatorias set estado = 'confirmado' where partido_id = :'partido' and miembro_id = t_m(3);
select t_check((select estado from convocatorias where partido_id = :'partido' and miembro_id = t_m(3)) = 'espera',
               'u3 vuelve y queda en espera');

select t_como(4);
select t_debe_fallar(format('update convocatorias set equipo = 1 where partido_id = %L and miembro_id = %L',
                            :'partido', t_m(4)), 'un jugador no se cambia de equipo');

-- ═════════ 6. Equipos (admin) ═════════
-- Confirmados: u1 u2 u4 u5 u6 u7 u8 u9 u10 u11. Equipo 1 = u1 u2 u4 u5 u6 · Equipo 2 = u7 u8 u9 u10 u11
select t_como(1);
select guardar_equipos(:'partido', jsonb_build_object(
  t_m(1), 1, t_m(2), 1, t_m(4), 1, t_m(5), 1, t_m(6), 1,
  t_m(7), 2, t_m(8), 2, t_m(9), 2, t_m(10), 2, t_m(11), 2));
select t_check((select estado from partidos where id = :'partido') = 'equipos_hechos', 'equipos confirmados');
select t_check((select count(*) from encuentros where partido_id = :'partido') = 1, 'encuentro 1 creado solo');

-- ═════════ 7. Factura y partido jugado ═════════
insert into facturas (liga_id, partido_id, archivo_path, nombre_archivo, importe, subida_por)
values (:'liga', :'partido', :'liga' || '/f1.pdf', 'reserva.pdf', 65, t_m(1));
insert into storage.objects (bucket_id, name) values ('facturas', :'liga' || '/f1.pdf');
select t_como(5);
select t_check((select count(*) from storage.objects where bucket_id = 'facturas') = 1, 'un miembro ve la factura');
select t_debe_fallar(format('insert into storage.objects (bucket_id, name) values (''facturas'', %L)', :'liga' || '/x.pdf'),
                     'un jugador no sube facturas');
select t_debe_fallar(format('insert into reportes_encuentro values (%L, 1, %L, 1, 1)', :'partido', t_m(5)),
                     'no se reporta antes de jugar');

select t_como(1);
select marcar_jugado(:'partido');
select t_check((select estado from partidos where id = :'partido') = 'post_partido', 'ventana post-partido abierta');
select t_check((select count(*) from movimientos where partido_id = :'partido') = 10, '10 cargos generados');
select t_check((select -sum(importe) from movimientos where partido_id = :'partido') = 65, 'cargos suman la factura (65 €)');
select t_check(generar_cargos(:'partido') = 0, 'generar_cargos es idempotente');

-- ═════════ 8. Partes de los 10 jugadores ═════════
-- Realidad: 5-3. u1: 3 goles, u4: 2 goles (+1 asist u5), u8: 2 goles, u9: 1 gol. Portero u7: 4 paradas.
-- Desacuerdos: u10 cree que fue 4-3; la mitad cree que u4 marcó 1 (→ disputa); u6 dice que u1 marcó 2.
do $$
declare r int; s int;
begin
  foreach r in array array[1,2,4,5,6,7,8,9,10,11] loop
    perform t_como(r);
    insert into reportes_encuentro (partido_id, n, reportero_id, goles_local, goles_visitante)
    values (current_setting('t.partido')::uuid, 1, t_m(r), case when r = 10 then 4 else 5 end, 3);

    foreach s in array array[1,2,4,5,6,7,8,9,10,11] loop
      insert into reportes_jugador (partido_id, reportero_id, sujeto_id, goles, asistencias, autogoles, paradas_clave)
      values (current_setting('t.partido')::uuid, t_m(r), t_m(s),
              case s when 1 then (case when r = 6 then 2 else 3 end)
                     when 4 then (case when r in (1,2,5,6,7) then 1 else 2 end)
                     when 8 then 2 when 9 then 1 else 0 end,
              case s when 5 then 1 else 0 end,
              0,
              case when s = 7 then 3 + (r % 3) when s = 2 then (case when r < 6 then 1 else null end) else null end);
    end loop;
  end loop;
end $$;

-- ═════════ 9. Valoraciones por aspectos (anónimas) ═════════
do $$
declare r int; s int; a record;
begin
  foreach r in array array[1,2,4,5,6,7,8,9,10,11] loop
    perform t_como(r);
    foreach s in array array[1,2,4,5,6,7,8,9,10,11] loop
      continue when r = s;
      for a in select clave, aplica_a from aspectos_valoracion where liga_id = current_setting('t.liga')::uuid loop
        continue when (a.aplica_a = 'porteros' and s not in (2, 7)) or (a.aplica_a = 'campo' and s in (2, 7));
        insert into valoraciones (partido_id, votante_id, votado_id, aspecto, nota)
        values (current_setting('t.partido')::uuid, t_m(r), t_m(s), a.clave,
                least(10, greatest(1, case s when 1 then 8 when 8 then 8 when 4 then 7 else 6 end
                                      + (r % 3) - 1)));
      end loop;
    end loop;
  end loop;
end $$;

select t_como(5);
select t_debe_fallar(format('insert into valoraciones (partido_id, votante_id, votado_id, aspecto, nota) values (%L,%L,%L,''porteria'',8)',
                            :'partido', t_m(5), t_m(4)), 'aspecto de portero a un jugador de campo');
select t_debe_fallar(format('insert into valoraciones (partido_id, votante_id, votado_id, aspecto, nota) values (%L,%L,%L,''ataque'',8)',
                            :'partido', t_m(5), t_m(5)), 'no se vota a sí mismo');
select t_debe_fallar(format('insert into valoraciones (partido_id, votante_id, votado_id, aspecto, nota) values (%L,%L,%L,''ataque'',8)',
                            :'partido', t_m(5), t_m(3)), 'no se vota a quien no jugó');
select t_check((select count(*) from valoraciones where votante_id <> t_m(5)) = 0, 'u5 no ve votos ajenos');
select t_check((select count(*) from valoraciones) > 0, 'u5 ve los suyos');
select t_check((select count(*) from reportes_jugador where reportero_id <> t_m(5)) = 0, 'u5 no ve partes ajenos');
select t_check((select votantes from v_progreso_post_partido where partido_id = :'partido') = 10, 'progreso: 10 votantes');
select t_check((select partes_resultado from v_progreso_post_partido where partido_id = :'partido') >= 3,
               'un no-admin ve cuántos partes hay (la app usa partes_resultado)');
select t_como(3);
select t_debe_fallar(format('insert into reportes_encuentro values (%L, 1, %L, 5, 3)', :'partido', t_m(3)),
                     'quien no jugó no envía parte');

-- ═════════ 10. Cierre de la ventana y consenso ═════════
select t_como(5);
select t_debe_fallar(format('select cerrar_post_partido(%L)', :'partido'), 'un jugador no cierra la ventana');
select t_como(1);
select t_check(cerrar_post_partido(:'partido') = 'en_revision', 'hay disputas → en revisión');
\echo 'Disputas abiertas:'
select tipo, campo, (select nombre from perfiles where id = (select perfil_id from miembros where id = sujeto_id)) as jugador,
       valores, valor_propuesto, num_reportes
  from disputas where partido_id = :'partido' and not resuelta;
select t_check((select count(*) from disputas where partido_id = :'partido' and not resuelta) = 1, 'una sola disputa (goles de u4)');
select t_check((select goles_local = 5 and goles_visitante = 3 and confianza = 90 from encuentros where partido_id = :'partido'),
               'resultado consolidado 5-3 con 90 % de acuerdo');
select t_check((select goles from acta_jugador where miembro_id = t_m(1) and partido_id = :'partido') = 3, 'u1: 3 goles (90 %)');
select t_check((select paradas_clave from acta_jugador where miembro_id = t_m(7)) = 4, 'u7: 4 paradas (mediana)');
select t_check((select porterias_cero from acta_jugador where miembro_id = t_m(7)) = 0, 'u7 encajó → sin portería a cero');
select t_check((select goles_encajados from acta_jugador where miembro_id = t_m(7)) = 5, 'u7 encajó 5');
select t_debe_fallar(format('select calcular_puntos(%L)', :'partido'), 'no se puntúa con disputas abiertas');

-- ═════════ 11. Resolver disputa → puntos ═════════
select t_check(resolver_disputa((select id from disputas where partido_id = :'partido' and not resuelta), 2::smallint) = 'cerrado',
               'disputa resuelta → partido cerrado');
select t_check((select goles from acta_jugador where miembro_id = t_m(4)) = 2, 'u4: 2 goles (decidido por admin)');
select * from v_descuadres where partido_id = :'partido';
select t_check((select goles_local = goles_local_jugadores and goles_visitante = goles_visitante_jugadores
                  from v_descuadres where partido_id = :'partido'), 'los goles de los jugadores cuadran con el 5-3');

\echo 'Puntos del partido:'
select coalesce(pe.apodo, pe.nombre) as jugador, pf.posicion, pf.victorias as v, pf.nota_media, pf.num_votantes as votos,
       pf.es_mvp, pf.total, pf.desglose - 'notas' as desglose
  from puntos_fantasy pf join miembros m on m.id = pf.miembro_id join perfiles pe on pe.id = m.perfil_id
 where pf.partido_id = :'partido' order by pf.total desc;

select t_check((select count(*) from puntos_fantasy where partido_id = :'partido') = 10, '10 jugadores puntuados');
select t_check((select count(*) from puntos_fantasy where partido_id = :'partido' and es_mvp) >= 1, 'hay MVP');
select t_check((select es_mvp from puntos_fantasy where miembro_id = t_m(1)), 'u1 es MVP (mejor nota media recortada)');
select t_check((select not es_mvp from puntos_fantasy where miembro_id = t_m(8)), 'u8 (segunda mejor nota) no es MVP');
-- u1: medio, 3 goles ×5, victoria 3, jugado 2, nota 8 → 4, MVP 3 = 27
select t_check((select total from puntos_fantasy where miembro_id = t_m(1)) = 27, 'u1 suma 27 puntos');
-- u7: portero, derrota, 0 goles, 4 paradas → +2, encajó 5 → -1, nota 6 → 2, jugado 2 = 5
select t_check((select total from puntos_fantasy where miembro_id = t_m(7)) = 5, 'u7 (portero) suma 5 puntos');
select t_check((select desglose->'notas' ? 'porteria' from puntos_fantasy where miembro_id = t_m(7)), 'el portero tiene nota de portería');

-- ═════════ 12. Estadísticas y caja ═════════
select t_como(9);
select t_check((select count(*) from v_clasificacion where liga_id = :'liga') = 10, 'clasificación con 10 jugadores');
select t_check((select miembro_id from v_clasificacion where liga_id = :'liga' and posicion = 1) = t_m(1), 'u1 lidera la clasificación');
select t_check((select miembro_id from v_pichichi where liga_id = :'liga' and posicion = 1) = t_m(1), 'u1 lidera el pichichi');
select t_check((select pct_victorias from v_rendimiento where miembro_id = t_m(1)) = 100, 'u1: 100 % victorias');
select t_check((select count(*) from v_notas_aspecto where miembro_id = t_m(1)) = 5, 'notas por aspecto de u1');
select t_check((select saldo from v_saldos where miembro_id = t_m(9)) = -6.5, 'u9 debe 6,50 €');
select t_check((select count(*) from v_saldos) = 1, 'un jugador solo ve su saldo');
select t_check((select pct_acierto from v_fiabilidad where miembro_id = t_m(9)) = 100, 'u9 reportó todo bien (100 %)');
select t_debe_fallar(format('select registrar_pago(%L, 6.5)', t_m(9)), 'un jugador no registra pagos');

select t_como(1);
select registrar_pago(t_m(9), 6.5, :'partido', 'Bizum');
select t_check((select saldo from v_saldos where miembro_id = t_m(9)) = 0, 'u9 al día tras pagar');
select t_check((select estado_pago from v_pagos_partido where partido_id = :'partido' and miembro_id = t_m(9)) = 'pagado', 'u9 pagado');
select t_check((select estado_pago from v_pagos_partido where partido_id = :'partido' and miembro_id = t_m(4)) = 'pendiente', 'u4 pendiente');
select t_check((select count(*) from v_saldos where liga_id = :'liga') = 14, 'el admin ve todos los saldos');
select t_check((select pct_acierto from v_fiabilidad where miembro_id = t_m(10)) < 100, 'u10 (dijo 4-3) tiene menos fiabilidad');

-- ═════════ 13. Expulsión ═════════
select crear_partido(:'liga', now() + interval '9 days', 50) as partido2 \gset
select t_como(6);
insert into convocatorias (partido_id, miembro_id) values (:'partido2', t_m(6));
select t_como(12);
insert into convocatorias (partido_id, miembro_id) values (:'partido2', t_m(12));
select t_como(1);
select t_debe_fallar(format('select expulsar(%L)', t_m(1)), 'el admin no se expulsa a sí mismo');
select expulsar(t_m(6));
select t_check((select estado from convocatorias where partido_id = :'partido2' and miembro_id = t_m(6)) = 'baja',
               'el expulsado pierde su plaza futura');
select t_check((select count(*) from puntos_fantasy where miembro_id = t_m(6)) = 1, 'su historial se conserva');
select t_como(6);
select t_check(not es_miembro(:'liga'), 'u6 ya no es miembro');
select t_debe_fallar(format('select unirse(%L)', :'codigo'), 'el expulsado no vuelve con el código');
select t_check((select count(*) from partidos) = 0, 'el expulsado no ve partidos');

-- regenerar código invalida el anterior
select t_como(2);
select regenerar_codigo(:'liga') is not null as regenerado;
select t_como(14);
select abandonar_liga(:'liga');
select t_debe_fallar(format('select unirse(%L)', :'codigo'), 'el código antiguo deja de valer');

reset role;
\echo '══════ ESCENARIO COMPLETADO SIN ERRORES ══════'
