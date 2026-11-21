-- 0042: fijos pendientes, suplentes por orden, bajas y capitanes
do $$
declare v_liga uuid; v_admin uuid; v_perfil uuid; v_p uuid; v_fijos uuid[]; v_sup uuid[]; v_n int; v_m uuid; v_e text; v_i int;
begin
  select l.id, m.id, m.perfil_id into v_liga, v_admin, v_perfil from ligas l join miembros m on m.liga_id = l.id and m.rol = 'admin'
   order by l.creada_en limit 1;
  delete from ausencias where liga_id = v_liga;
  -- 4 fijos y 3 suplentes, partido de 2x2 = 4 plazas
  select array_agg(id order by unido_en, id) into v_fijos from (select id, unido_en from miembros where liga_id = v_liga
     and estado = 'activo' order by unido_en, id limit 6) x;
  select array_agg(id order by unido_en, id) into v_sup from (select id, unido_en from miembros where liga_id = v_liga
     and estado = 'activo' order by unido_en, id offset 6 limit 3) x;
  update miembros set rango = 'reserva' where liga_id = v_liga and rango = 'fijo' and not (id = any(v_fijos));
  update miembros set rango = 'fijo' where id = any(v_fijos);
  update miembros set rango = 'reserva' where id = any(v_sup);
  update ligas set modo_convocatoria = 'clasica', modo_equipos = 'capitanes', capitanes_por_equipo = 1 where id = v_liga;
  insert into partidos (liga_id, fecha_hora, plazas, num_equipos, creado_por)
  values (v_liga, now() + interval '3 days', 6, 2, v_admin) returning id into v_p;

  select count(*) into v_n from convocatorias where partido_id = v_p and estado = 'pendiente';
  perform t_check(v_n = 6, 'los 6 fijos aparecen pendientes (' || v_n || ')');
  perform t_check((select estado from partidos where id = v_p) = 'completo', 'con los fijos pendientes está completo');

  -- suplentes por orden
  for v_i in 1..3 loop
    insert into convocatorias (partido_id, miembro_id, estado) values (v_p, v_sup[v_i], 'confirmado');
    perform pg_sleep(0.01);
  end loop;
  perform t_check((select count(*) from convocatorias where partido_id = v_p and estado = 'espera') = 3, 'suplentes en espera: ' || (select string_agg(estado::text, ',') from convocatorias where partido_id = v_p) || ' sup=' || coalesce(array_length(v_sup,1),0));

  -- un fijo dice que no: entra el primer suplente
  update convocatorias set estado = 'baja' where partido_id = v_p and miembro_id = v_fijos[1];
  select estado into v_e from convocatorias where partido_id = v_p and miembro_id = v_sup[1];
  perform t_check(v_e = 'confirmado', 'entra el primer suplente: ' || v_e);
  perform t_check((select estado from convocatorias where partido_id = v_p and miembro_id = v_sup[2]) = 'espera', 'el segundo sigue esperando');

  -- otro fijo en duda: mantiene su plaza
  update convocatorias set estado = 'duda' where partido_id = v_p and miembro_id = v_fijos[2];
  perform t_check((select estado from convocatorias where partido_id = v_p and miembro_id = v_sup[2]) = 'espera', 'duda no libera plaza');

  -- baja larga del fijo 3: libera su plaza y entra el segundo suplente
  perform t_como_uid(v_perfil);
  perform registrar_ausencia(v_fijos[3], current_date, current_date + 60, 'lesion');
  perform set_config('request.jwt.claim.sub', '', false);
  perform t_check((select estado from convocatorias where partido_id = v_p and miembro_id = v_fijos[3]) = 'baja', 'lesionado fuera');
  perform t_check((select estado from convocatorias where partido_id = v_p and miembro_id = v_sup[2]) = 'confirmado', 'entra el segundo suplente');

  -- nuevo partido: el lesionado no aparece
  insert into partidos (liga_id, fecha_hora, plazas, num_equipos, creado_por)
  values (v_liga, now() + interval '10 days', 6, 2, v_admin) returning id into v_m;
  perform t_check(not exists (select 1 from convocatorias where partido_id = v_m and miembro_id = v_fijos[3]), 'lesionado no se apunta solo');
  -- vuelve: se le apunta
  delete from ausencias where miembro_id = v_fijos[3];
  perform t_check((select estado from convocatorias where partido_id = v_m and miembro_id = v_fijos[3]) = 'pendiente', 'al volver queda pendiente');

  -- capitanes y equipos automáticos
  update convocatorias set estado = 'confirmado' where partido_id = v_p and estado in ('pendiente', 'duda');
  perform t_check(sortear_capitanes(v_p) = 2, 'se sortean 2 capitanes');
  perform t_check((select count(distinct equipo) from convocatorias where partido_id = v_p and capitan) = 2, 'un capitán por equipo');
  perform t_check(equipos_automaticos(v_p) = 6, 'equipos automáticos para 6');
  perform t_check((select estado from partidos where id = v_p) = 'equipos_hechos', 'equipos hechos');
  perform t_check((select count(*) from convocatorias where partido_id = v_p and estado = 'confirmado' and equipo = 1) = 3, '3 por equipo');
  update ligas set modo_convocatoria = 'apertura', modo_equipos = 'admin' where id = v_liga;
  raise notice 'escenario_convocatoria_sencilla OK';
end $$;
