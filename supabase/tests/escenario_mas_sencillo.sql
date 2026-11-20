-- 0039: cesiones desactivadas por defecto y alineación automática
do $$
declare v_liga uuid; v_admin uuid; v_m uuid; v_p uuid; v_n int; v_ficha uuid; v_err text;
begin
  select l.id, m.perfil_id, m.id into v_liga, v_admin, v_m from ligas l join miembros m on m.liga_id = l.id and m.rol = 'admin'
   order by l.creada_en limit 1;
  delete from alineaciones a using partidos p where a.partido_id = p.id and p.liga_id = v_liga;
  insert into partidos (liga_id, fecha_hora, plazas, num_equipos, creado_por)
  values (v_liga, now() + interval '30 minutes', 10, 2, v_m) returning id into v_p;
  update ligas set horas_cierre_alineacion = 2 where id = v_liga;
  perform t_check(congelar_alineaciones(v_p), 'congela las alineaciones');
  select count(*) into v_n from alineaciones where partido_id = v_p and manager_id = v_m;
  perform t_check(v_n = least(5, (select count(*) from fichas where liga_id = v_liga and propietario_id = v_m)),
                  'sin alinear: juega con sus mejores jugadores (' || v_n || ')');
  perform t_check((select count(*) from alineaciones where partido_id = v_p and manager_id = v_m and rol = 'POR') = 1,
                  'con un portero');
  -- Cesiones desactivadas por defecto
  select id into v_ficha from fichas where liga_id = v_liga and propietario_id = v_m limit 1;
  begin
    insert into cesiones (liga_id, ficha_id, propietario_id, partido_id, pct)
    values (v_liga, v_ficha, v_m, v_p, 0.1);
    v_err := null;
  exception when others then v_err := sqlerrm;
  end;
  perform t_check(v_err like '%cesiones están desactivadas%', 'cesión rechazada si están desactivadas: ' || coalesce(v_err, 'sin error'));
  raise notice 'escenario_mas_sencillo OK';
end $$;
