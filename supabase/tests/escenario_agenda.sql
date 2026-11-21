-- 0043: mi agenda con partidos de varias ligas
do $$
declare v_perfil uuid; v_n int; v_ligas int;
begin
  select m.perfil_id into v_perfil from miembros m join partidos p on p.liga_id = m.liga_id
   where m.estado = 'activo' and m.perfil_id is not null and p.estado in ('abierto', 'completo') and p.fecha_hora > now()
   group by m.perfil_id order by count(distinct m.liga_id) desc limit 1;
  perform t_como_uid(v_perfil);
  select count(*), count(distinct liga_id) into v_n, v_ligas from mi_agenda(60);
  perform set_config('request.jwt.claim.sub', '', false);
  perform t_check(v_n > 0, 'mi agenda tiene partidos (' || v_n || ' en ' || v_ligas || ' ligas)');
  raise notice 'escenario_agenda OK';
end $$;
