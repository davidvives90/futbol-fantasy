-- 0027 · Fantasy: equipo inicial repartido, menos dinero, protección de 7 días
--  · Cada mánager nuevo recibe 5 jugadores al azar pero compensados (valor total ≈ 5 × precio medio) y,
--    además, un dinero inicial de 1,5 × precio medio. Lo que queda sin repartir está en el mercado.
--  · Copias por jugador: suficientes para el reparto de todos los posibles mánagers + ~2 fichas libres por mánager.
--  · Protección tras fichar (no se puede clausular): ligas.proteccion_dias (7 por defecto) en vez de jornadas.
--  · reiniciar_fantasy(liga): el admin empieza el Fantasy de cero con este sistema.

alter table ligas
  add column proteccion_dias smallint not null default 7
    constraint ligas_proteccion_dias_ck check (proteccion_dias between 0 and 30),
  add column reparto_inicial smallint not null default 5
    constraint ligas_reparto_inicial_ck check (reparto_inicial between 0 and 11),
  add column factor_presupuesto numeric(3,1) not null default 1.5
    constraint ligas_factor_presupuesto_ck check (factor_presupuesto between 0 and 10);
alter table fichas add column protegida_hasta timestamptz;

-- ───────────── Copias: reparto de todos + 2 libres por mánager ─────────────
create or replace function copias_formula(p_liga uuid) returns int
language sql stable security definer set search_path = public as $$
  select greatest(2, ceil(
           greatest((select count(*) from fantasy_managers fm join miembros m on m.id = fm.miembro_id
                      where fm.liga_id = p_liga and m.estado = 'activo'),
                    (select count(*) from miembros where liga_id = p_liga and estado in ('activo', 'pendiente_registro')))::numeric
           * (least((select reparto_inicial from ligas where id = p_liga),
                    (select max_plantilla from ligas where id = p_liga)) + 2)
           / nullif((select count(*) from mercado_jugador mj where mj.liga_id = p_liga
                      and mj.miembro_id in (select jugadores_liga(p_liga))), 0)))::int
$$;

create or replace function presupuesto_liga(p_liga uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select round(l.factor_presupuesto * coalesce(avg(mj.precio), 0) * 2) / 2
    from ligas l left join mercado_jugador mj on mj.liga_id = l.id and mj.miembro_id in (select jugadores_liga(l.id))
   where l.id = p_liga group by l.factor_presupuesto
$$;

-- ───────────── Reparto: 5 al azar, compensados ─────────────
-- Prueba 300 combinaciones al azar de jugadores con ficha libre (máx. 1 invitado) y se queda con la de valor
-- total más cercano a reparto × precio medio. Devuelve cuántos jugadores ha recibido.
create or replace function repartir_equipo(p_liga uuid, p_manager uuid) returns int
language plpgsql security definer set search_path = public as $$
declare l ligas; v_r int; v_obj numeric; v_cand uuid[]; v_precio numeric[]; v_inv boolean[]; v_n int;
        v_mejor int[]; v_mejor_dif numeric := null; v_sel int[]; v_suma numeric; v_ninv int; i int; t int; j uuid;
        k int := 0; v_ya int;
begin
  select * into l from ligas where id = p_liga;
  select count(*) into v_ya from fichas where liga_id = p_liga and propietario_id = p_manager;
  v_r := least(l.reparto_inicial, l.max_plantilla) - v_ya;
  if v_r <= 0 then return 0; end if;
  select avg(precio) * v_r into v_obj from mercado_jugador where liga_id = p_liga and miembro_id in (select jugadores_liga(p_liga));

  select array_agg(miembro_id), array_agg(precio), array_agg(no_habitual) into v_cand, v_precio, v_inv
    from (select mj.miembro_id, mj.precio, mj.no_habitual from mercado_jugador mj
           where mj.liga_id = p_liga and mj.miembro_id in (select jugadores_liga(p_liga))
             and exists (select 1 from fichas f where f.liga_id = p_liga and f.jugador_id = mj.miembro_id and f.propietario_id is null)
             and not exists (select 1 from fichas f where f.propietario_id = p_manager and f.jugador_id = mj.miembro_id)
           order by random()) x;
  v_n := coalesce(array_length(v_cand, 1), 0);
  if v_n = 0 then return 0; end if;
  v_r := least(v_r, v_n);

  for t in 1..300 loop
    -- combinación al azar de v_r índices distintos
    select array_agg(x) into v_sel from (select x from generate_series(1, v_n) x order by random() limit v_r) s;
    v_suma := 0; v_ninv := 0;
    foreach i in array v_sel loop
      v_suma := v_suma + v_precio[i];
      if v_inv[i] then v_ninv := v_ninv + 1; end if;
    end loop;
    continue when v_ninv > 1;
    if v_mejor_dif is null or abs(v_suma - v_obj) < v_mejor_dif then
      v_mejor_dif := abs(v_suma - v_obj);
      v_mejor := v_sel;
      exit when v_mejor_dif < 0.05;
    end if;
  end loop;
  if v_mejor is null then return 0; end if;

  foreach i in array v_mejor loop
    j := v_cand[i];
    update fichas
       set propietario_id = p_manager, precio_compra = v_precio[i], clausula = v_precio[i], adquirida_en = now(),
           protegida_hasta = case when l.proteccion_dias > 0 then now() + make_interval(days => l.proteccion_dias) end,
           protegida_jornadas = case when l.proteccion_dias > 0 then 1 else 0 end
     where id = (select id from fichas where liga_id = p_liga and jugador_id = j and propietario_id is null
                  order by numero limit 1);
    if found then k := k + 1; end if;
  end loop;
  return k;
end $$;

-- Alta de mánager: dinero inicial (1,5 × precio medio) + reparto de su equipo
create or replace function asegurar_manager(p_liga uuid, p_miembro uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_presu numeric;
begin
  if exists (select 1 from fantasy_managers where liga_id = p_liga and miembro_id = p_miembro) then return; end if;
  if (select presupuesto_inicial from ligas where id = p_liga) is null then
    raise exception 'El mercado aún no está abierto: falta cerrar la encuesta inicial';
  end if;
  if not (select fantasy_activo from ligas where id = p_liga) then
    raise exception 'El Fantasy está desactivado en esta liga';
  end if;
  v_presu := presupuesto_liga(p_liga);
  update ligas set presupuesto_inicial = v_presu where id = p_liga and presupuesto_inicial is distinct from v_presu;
  insert into fantasy_managers (liga_id, miembro_id, saldo) values (p_liga, p_miembro, v_presu)
  on conflict do nothing;
  if found then
    insert into transacciones_fantasy (liga_id, manager_id, tipo, importe, saldo_despues)
    values (p_liga, p_miembro, 'presupuesto_inicial', v_presu, v_presu);
    perform asegurar_fichas(p_liga);
    perform repartir_equipo(p_liga, p_miembro);
  end if;
end $$;

-- ───────────── Protección por días ─────────────
create or replace function transferir_ficha(p_ficha uuid, p_nuevo uuid, p_importe numeric) returns void
language plpgsql security definer set search_path = public as $$
declare f fichas; l ligas;
begin
  select * into f from fichas where id = p_ficha;
  select * into l from ligas where id = f.liga_id;
  perform soltar_ficha(p_ficha);
  update fichas
     set propietario_id = p_nuevo, precio_compra = p_importe,
         clausula = greatest(p_importe, precio_actual(f.jugador_id)),
         adquirida_en = now(),
         protegida_hasta = case when l.proteccion_dias > 0 then now() + make_interval(days => l.proteccion_dias) end,
         protegida_jornadas = case when l.proteccion_dias > 0 then 1 else 0 end
   where id = p_ficha;
end $$;

-- protegida_jornadas queda como indicador (1 = protegida) para las vistas; la fecha manda.
-- El cierre de jornada lo decrementaba: no se quita mientras la fecha no haya pasado.
create or replace function mantener_proteccion() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.propietario_id is not distinct from old.propietario_id
     and new.protegida_jornadas < old.protegida_jornadas
     and new.protegida_hasta is not null and new.protegida_hasta > now() then
    new.protegida_jornadas := old.protegida_jornadas;
  end if;
  return new;
end $$;
create trigger t_mantener_proteccion before update of protegida_jornadas on fichas
  for each row execute function mantener_proteccion();

create or replace function caducar_protecciones() returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  update fichas set protegida_jornadas = 0
   where protegida_jornadas > 0 and protegida_hasta is not null and protegida_hasta <= now();
  get diagnostics k = row_count;
  return k;
end $$;

create or replace function pagar_clausula(p_ficha uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare f fichas; v_m uuid; v_imp numeric; v_saldo numeric; v_dueno uuid;
begin
  perform caducar_protecciones();
  select * into f from fichas where id = p_ficha for update;
  if not found then raise exception 'Ficha no encontrada'; end if;
  v_m := mi_miembro(f.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if f.propietario_id is null then raise exception 'Esa ficha está libre: cómprala en el mercado'; end if;
  if f.propietario_id = v_m then raise exception 'Esa ficha ya es tuya'; end if;
  perform exigir_mercado_abierto(f.liga_id);
  if f.protegida_hasta is not null and f.protegida_hasta > now() then
    raise exception 'Ficha protegida: se fichó hace poco y no se puede clausular hasta el %', fecha_corta(f.protegida_hasta);
  end if;
  if f.protegida_hasta is null and f.protegida_jornadas > 0 then
    raise exception 'Ficha protegida: se adquirió hace poco y no se puede clausular todavía';
  end if;
  if ficha_cedida(p_ficha) then raise exception 'Está cedida esta jornada: no se puede clausular'; end if;
  perform asegurar_manager(f.liga_id, v_m);
  perform validar_hueco(f.liga_id, v_m, f.jugador_id);
  v_dueno := f.propietario_id;
  v_imp := clausula_efectiva(p_ficha);
  v_saldo := mover_saldo(f.liga_id, v_m, -v_imp, 'clausula_pagada', f.jugador_id);
  perform mover_saldo(f.liga_id, v_dueno, v_imp, 'clausula_cobrada', f.jugador_id);
  perform transferir_ficha(p_ficha, v_m, v_imp);
  return v_saldo;
end $$;

-- ───────────── Reinicio del Fantasy (admin) ─────────────
create or replace function reiniciar_fantasy(p_liga uuid) returns int
language plpgsql security definer set search_path = public as $$
declare k int := 0; m record;
begin
  if auth.uid() is not null then perform exigir_admin(p_liga); end if;
  if (select presupuesto_inicial from ligas where id = p_liga) is null then
    raise exception 'El Fantasy aún no ha empezado: cierra antes la encuesta inicial';
  end if;
  delete from ofertas where liga_id = p_liga;
  delete from cesiones where liga_id = p_liga;
  delete from alineaciones a using partidos p where a.partido_id = p.id and p.liga_id = p_liga;
  delete from puntos_manager pm using partidos p where pm.partido_id = p.id and p.liga_id = p_liga;
  delete from transacciones_fantasy where liga_id = p_liga;
  update fichas set propietario_id = null, precio_compra = null, clausula = null, adquirida_en = null,
                    protegida_jornadas = 0, protegida_hasta = null
   where liga_id = p_liga;
  delete from fantasy_managers where liga_id = p_liga;
  for m in select id from miembros where liga_id = p_liga and estado = 'activo' and perfil_id is not null loop
    perform asegurar_manager(p_liga, m.id);
    k := k + 1;
  end loop;
  return k;
end $$;

revoke execute on function copias_formula(uuid), presupuesto_liga(uuid), repartir_equipo(uuid, uuid),
  transferir_ficha(uuid, uuid, numeric), mantener_proteccion(), caducar_protecciones(),
  pagar_clausula(uuid), reiniciar_fantasy(uuid)
  from public, anon;
revoke execute on function copias_formula(uuid), presupuesto_liga(uuid), repartir_equipo(uuid, uuid),
  transferir_ficha(uuid, uuid, numeric), mantener_proteccion(), caducar_protecciones()
  from authenticated;
grant execute on function pagar_clausula(uuid), reiniciar_fantasy(uuid) to authenticated;
