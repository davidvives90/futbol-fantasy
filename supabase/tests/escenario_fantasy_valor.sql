-- 0044: puntos por nota continuos, precios con notas y resumen para tarjetas
do $$
declare v_liga uuid; v_perfil uuid; v_r jsonb; v_p uuid; v_n int;
begin
  perform t_check(puntos_por_nota(10, 4) = 4, '5 estrellas = 4 pts');
  perform t_check(puntos_por_nota(8, 4) = 2.5, '4 estrellas = 2,5 pts');
  perform t_check(puntos_por_nota(6, 4) = 1.5, '3 estrellas = 1,5 pts');
  perform t_check(puntos_por_nota(4, 4) = 0, '2 estrellas = 0');
  select p.liga_id into v_liga from puntos_fantasy pf join partidos p on p.id = pf.partido_id
   where p.estado = 'cerrado' and exists (select 1 from mercado_jugador mj where mj.liga_id = p.liga_id)
   group by p.liga_id order by count(*) desc limit 1;
  select m.perfil_id into v_perfil from miembros m where m.liga_id = v_liga and m.perfil_id is not null and m.estado = 'activo' limit 1;
  perform t_como_uid(v_perfil);
  v_r := resumen_jugadores_fantasy(v_liga);
  perform set_config('request.jwt.claim.sub', '', false);
  perform t_check(jsonb_typeof(v_r) = 'object' and (select count(*) from jsonb_object_keys(v_r)) > 0, 'resumen con jugadores');
  perform t_check(jsonb_array_length((select value from jsonb_each(v_r) limit 1)->'ultimos') between 1 and 5, 'últimas 5');
  -- recálculo con un partido cerrado nuevo (sin historial de ese partido)
  select p.id into v_p from partidos p where p.liga_id = v_liga and p.estado = 'cerrado'
   and not exists (select 1 from historial_precios h where h.partido_id = p.id) limit 1;
  if v_p is null then
    select p.id into v_p from partidos p where p.liga_id = v_liga and p.estado = 'cerrado' limit 1;
    delete from historial_precios where partido_id = v_p;
  end if;
  v_n := recalcular_precios(v_liga, v_p);
  perform t_check(v_n > 0, 'recalcula precios (' || v_n || ')');
  perform t_check((select count(*) from mercado_jugador where liga_id = v_liga and precio < (select precio_min from ligas where id = v_liga)) = 0, 'precios dentro de límites');
  raise notice 'escenario_fantasy_valor OK';
end $$;
