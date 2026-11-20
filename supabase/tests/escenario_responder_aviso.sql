-- 0040: responder desde la notificación
do $$
declare v_m uuid; v_p uuid; v_t text; v_r text;
begin
  select c.miembro_id, c.partido_id into v_m, v_p from convocatorias c join partidos p on p.id = c.partido_id
   join miembros m on m.id = c.miembro_id
   where p.estado in ('abierto', 'completo') and m.estado = 'activo' limit 1;
  if v_p is null then
    select m.id, p.id into v_m, v_p from partidos p join miembros m on m.liga_id = p.liga_id and m.estado = 'activo'
     where p.estado in ('abierto', 'completo') limit 1;
  end if;
  v_t := token_aviso_de(v_m);
  perform t_check(length(v_t) = 64, 'token de 64 caracteres');
  perform t_check(token_aviso_de(v_m) = v_t, 'el token no cambia');
  v_r := responder_aviso(v_t, v_p, 'no');
  perform t_check(v_r = 'baja', 'No voy desde el aviso: ' || v_r);
  v_r := responder_aviso(v_t, v_p, 'voy');
  perform t_check(v_r in ('confirmado', 'espera'), 'Voy desde el aviso: ' || v_r);
  perform t_check(responder_aviso(repeat('x', 64), v_p, 'voy') = 'no_valido', 'token falso rechazado');
  raise notice 'escenario_responder_aviso OK';
end $$;
