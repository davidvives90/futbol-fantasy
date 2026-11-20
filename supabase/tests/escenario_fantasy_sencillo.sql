-- 0038: Fantasy sin encuesta. El primero que entra lo arranca; todos con valor parecido (45–55).
do $$
declare v_admin uuid; v_liga uuid; v_m uuid; v_n int; v_min numeric; v_max numeric; v_presu numeric;
begin
  select l.id, m.perfil_id into v_liga, v_admin from ligas l join miembros m on m.liga_id = l.id and m.rol = 'admin'
   order by l.creada_en limit 1;
  update ligas set fantasy_activo = true, reparto_inicial = 3 where id = v_liga;
  perform reiniciar_fantasy(v_liga, true);
  -- Simula liga recién creada: sin precios ni presupuesto
  delete from fantasy_managers where liga_id = v_liga;
  delete from historial_precios where liga_id = v_liga;
  delete from fichas where liga_id = v_liga;
  delete from mercado_jugador where liga_id = v_liga;
  update ligas set presupuesto_inicial = null where id = v_liga;
  perform t_check(not mercado_abierto(v_liga), 'sin empezar: mercado cerrado');

  perform t_como_uid(v_admin);
  perform t_check(entrar_fantasy(v_liga), 'entrar_fantasy devuelve true');
  reset role;
  select count(*), min(rating), max(rating) into v_n, v_min, v_max from mercado_jugador where liga_id = v_liga;
  perform t_check(v_n = (select count(*) from jugadores_liga(v_liga)), 'todos los jugadores tienen precio');
  perform t_check(v_min >= 45 and v_max <= 55, 'valoraciones iniciales entre 45 y 55');
  select presupuesto_inicial into v_presu from ligas where id = v_liga;
  perform t_check(v_presu > 0, 'presupuesto fijado');
  select m.id into v_m from miembros m where m.liga_id = v_liga and m.perfil_id = v_admin;
  perform t_check(exists (select 1 from fantasy_managers where liga_id = v_liga and miembro_id = v_m), 'equipo creado');
  perform t_check((select count(*) from fichas where liga_id = v_liga and propietario_id is not null) > 0, 'jugadores repartidos');
  -- idempotente
  perform t_como_uid(v_admin);
  perform entrar_fantasy(v_liga);
  reset role;
  perform t_check((select presupuesto_inicial from ligas where id = v_liga) = v_presu, 'segunda entrada no cambia nada');
  raise notice 'escenario_fantasy_sencillo OK';
end $$;
