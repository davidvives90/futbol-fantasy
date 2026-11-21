-- 0046: códigos de dinero y sin anuncios
do $$
declare v_master uuid; v_user uuid; v_liga uuid; r jsonb; v_ok boolean;
begin
  select m.perfil_id, m.liga_id into v_user, v_liga from miembros m join fantasy_managers f on f.miembro_id = m.id
   where m.estado = 'activo' and m.perfil_id is not null limit 1;
  select id into v_master from auth.users where id <> v_user limit 1;
  insert into masters (perfil_id) values (v_master) on conflict do nothing;
  perform t_como_uid(v_master);
  perform master_crear_codigo('SINADS30', p_tipo => 'sin_anuncios', p_dias => 30);
  perform master_crear_codigo('SINADSYA', p_tipo => 'sin_anuncios');
  perform master_crear_codigo('PASTA2', 2);
  perform t_check((mis_ventajas()->>'sin_anuncios')::boolean, 'el máster no ve anuncios');

  perform t_como_uid(v_user);
  perform t_check(not (mis_ventajas()->>'sin_anuncios')::boolean, 'usuario normal ve anuncios');
  r := canjear('sinads30');
  perform t_check(r->>'tipo' = 'sin_anuncios' and (mis_ventajas()->>'sin_anuncios')::boolean, 'canjea 30 días sin anuncios');
  begin perform canjear('SINADS30'); v_ok := false; exception when others then v_ok := true; end;
  perform t_check(v_ok, 'no se puede canjear dos veces');
  r := canjear('SINADSYA');
  perform t_check((mis_ventajas()->>'para_siempre')::boolean, 'sin anuncios para siempre');
  begin perform canjear('PASTA2'); v_ok := false; exception when others then v_ok := true; end;
  perform t_check(v_ok, 'dinero sin liga pide liga');
  r := canjear('PASTA2', v_liga);
  perform t_check(r->>'tipo' = 'dinero' and (r->>'importe')::numeric = 2, 'canjea dinero en la liga');
  perform set_config('request.jwt.claim.sub', '', false);

  update ligas set compras_dinero = false where id = v_liga;
  perform t_como_uid(v_master);
  perform master_crear_codigo('PASTA3', 3);
  perform t_como_uid(v_user);
  begin perform canjear('PASTA3', v_liga); v_ok := false; exception when others then v_ok := true; end;
  perform t_check(v_ok, 'liga sin compras de dinero lo rechaza');
  perform set_config('request.jwt.claim.sub', '', false);
  update ligas set compras_dinero = true where id = v_liga;
  delete from masters where perfil_id = v_master;
  raise notice 'escenario_tienda OK';
end $$;
