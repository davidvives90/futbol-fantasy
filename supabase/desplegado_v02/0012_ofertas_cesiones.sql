-- 0012 · Ofertas negociadas y cesiones (ampliación 0.2, docs/mercado_fantasy.md §9.4–9.5)
--
-- Decisiones:
--  · Una oferta nueva del mismo comprador por la misma ficha cancela la anterior (la "contraoferta" del comprador).
--  · Al responder una oferta caducada no se lanza error: queda 'caducada' y se devuelve ese estado.
--  · Una cesión se ofrece para el PRÓXIMO partido con la alineación abierta; el importe se fija al aceptarla
--    (pct × valor de mercado en ese momento). Ofrecer cuenta como "ceder" para el límite de 1 por jornada.
--  · Las cesiones ofrecidas que nadie acepta se cancelan al congelar las alineaciones del partido; las aceptadas
--    pasan a 'finalizada' al liquidar la jornada (0013).
--  · No se puede recibir en cesión a un jugador del que ya tienes ficha.

create table ofertas (
  id            uuid primary key default gen_random_uuid(),
  liga_id       uuid not null references ligas on delete cascade,
  ficha_id      uuid not null references fichas on delete cascade,
  comprador_id  uuid not null references miembros on delete cascade,
  vendedor_id   uuid not null references miembros on delete cascade,
  importe       numeric(7,2) not null check (importe > 0),
  estado        text not null default 'pendiente'
                check (estado in ('pendiente', 'aceptada', 'rechazada', 'cancelada', 'caducada')),
  creada_en     timestamptz not null default now(),
  expira_en     timestamptz not null,
  resuelta_en   timestamptz,
  check (comprador_id <> vendedor_id)
);
create index on ofertas (ficha_id) where estado = 'pendiente';
create index on ofertas (comprador_id);
create index on ofertas (vendedor_id);

create table cesiones (
  id             uuid primary key default gen_random_uuid(),
  liga_id        uuid not null references ligas on delete cascade,
  ficha_id       uuid not null references fichas on delete cascade,
  propietario_id uuid not null references miembros on delete cascade,
  cesionario_id  uuid references miembros on delete cascade,
  partido_id     uuid not null references partidos on delete cascade,
  pct            numeric(4,3) not null check (pct > 0 and pct <= 1),
  importe        numeric(7,2),                 -- se fija al aceptar
  estado         text not null default 'ofrecida'
                 check (estado in ('ofrecida', 'aceptada', 'finalizada', 'cancelada')),
  creada_en      timestamptz not null default now(),
  aceptada_en    timestamptz,
  check (cesionario_id is null or cesionario_id <> propietario_id)
);
create unique index cesion_activa_por_ficha on cesiones (ficha_id) where estado in ('ofrecida', 'aceptada');
create unique index cede_una_por_jornada on cesiones (propietario_id, partido_id) where estado in ('ofrecida', 'aceptada');
create unique index recibe_una_por_jornada on cesiones (cesionario_id, partido_id) where estado = 'aceptada';

-- ───────────── Ayudantes redefinidos ─────────────
create or replace function ficha_cedida(p_ficha uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from cesiones where ficha_id = p_ficha and estado = 'aceptada')
$$;

-- No habituales: fichas propias + la recibida en cesión para ese partido
create or replace function no_habituales_de(p_liga uuid, p_manager uuid, p_partido uuid default null) returns int
language sql stable security definer set search_path = public as $$
  select (select count(*) from fichas f
            join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
           where f.liga_id = p_liga and f.propietario_id = p_manager and mj.no_habitual)::int
       + (select count(*) from cesiones c join fichas f on f.id = c.ficha_id
            join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
           where c.cesionario_id = p_manager and c.estado = 'aceptada' and mj.no_habitual
             and (p_partido is null or c.partido_id = p_partido))::int
$$;

create or replace function soltar_ficha(p_ficha uuid) returns void
language plpgsql security definer set search_path = public as $$
declare f fichas;
begin
  select * into f from fichas where id = p_ficha;
  if f.propietario_id is null then return; end if;
  delete from alineaciones a using partidos p
   where a.partido_id = p.id and p.liga_id = f.liga_id and not p.alineaciones_congeladas
     and a.manager_id = f.propietario_id and a.jugador_id = f.jugador_id;
  update ofertas set estado = 'cancelada', resuelta_en = now() where ficha_id = p_ficha and estado = 'pendiente';
  update cesiones set estado = 'cancelada' where ficha_id = p_ficha and estado = 'ofrecida';
end $$;

create or replace function caducar_ofertas(p_liga uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  update ofertas set estado = 'caducada', resuelta_en = now()
   where estado = 'pendiente' and expira_en <= now() and (p_liga is null or liga_id = p_liga);
  get diagnostics k = row_count;
  return k;
end $$;

-- ───────────── RPC: ofertas ─────────────
create or replace function hacer_oferta(p_ficha uuid, p_importe numeric) returns uuid
language plpgsql security definer set search_path = public as $$
declare f fichas; l ligas; v_m uuid; v_id uuid;
begin
  select * into f from fichas where id = p_ficha;
  if not found then raise exception 'Ficha no encontrada'; end if;
  v_m := mi_miembro(f.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if f.propietario_id is null then raise exception 'Esa ficha está libre: cómprala en el mercado'; end if;
  if f.propietario_id = v_m then raise exception 'Esa ficha ya es tuya'; end if;
  if coalesce(p_importe, 0) <= 0 then raise exception 'La oferta tiene que ser mayor que 0'; end if;
  perform exigir_mercado_abierto(f.liga_id);
  if ficha_cedida(p_ficha) then raise exception 'Está cedida esta jornada: no se puede ofertar'; end if;
  if exists (select 1 from fichas where propietario_id = v_m and jugador_id = f.jugador_id) then
    raise exception 'Ya tienes a ese jugador en la plantilla';
  end if;
  perform asegurar_manager(f.liga_id, v_m);
  select * into l from ligas where id = f.liga_id;
  update ofertas set estado = 'cancelada', resuelta_en = now()
   where ficha_id = p_ficha and comprador_id = v_m and estado = 'pendiente';
  insert into ofertas (liga_id, ficha_id, comprador_id, vendedor_id, importe, expira_en)
  values (f.liga_id, p_ficha, v_m, f.propietario_id, round(p_importe, 2),
          now() + make_interval(hours => l.horas_caducidad_oferta))
  returning id into v_id;
  return v_id;
end $$;

-- El dueño acepta o rechaza. Al aceptar se revalida todo con el estado de ese momento.
create or replace function responder_oferta(p_oferta uuid, p_aceptar boolean) returns text
language plpgsql security definer set search_path = public as $$
declare o ofertas; f fichas; v_m uuid;
begin
  select * into o from ofertas where id = p_oferta for update;
  if not found then raise exception 'Oferta no encontrada'; end if;
  v_m := mi_miembro(o.liga_id);
  if v_m is null or o.vendedor_id <> v_m then raise exception 'Solo el dueño de la ficha puede responder'; end if;
  if o.estado <> 'pendiente' then raise exception 'La oferta ya no está pendiente (%)', o.estado; end if;
  if o.expira_en <= now() then
    update ofertas set estado = 'caducada', resuelta_en = now() where id = p_oferta;
    return 'caducada';
  end if;
  if not p_aceptar then
    update ofertas set estado = 'rechazada', resuelta_en = now() where id = p_oferta;
    return 'rechazada';
  end if;

  perform exigir_mercado_abierto(o.liga_id);
  select * into f from fichas where id = o.ficha_id for update;
  if f.propietario_id is distinct from o.vendedor_id then raise exception 'Esa ficha ya no es tuya'; end if;
  if ficha_cedida(f.id) then raise exception 'Está cedida esta jornada: espera a que vuelva'; end if;
  perform validar_hueco(o.liga_id, o.comprador_id, f.jugador_id);
  perform mover_saldo(o.liga_id, o.comprador_id, -o.importe, 'oferta_pagada', f.jugador_id);
  perform mover_saldo(o.liga_id, o.vendedor_id, o.importe, 'oferta_cobrada', f.jugador_id);
  perform transferir_ficha(f.id, o.comprador_id, o.importe);   -- cancela las demás ofertas pendientes
  update ofertas set estado = 'aceptada', resuelta_en = now() where id = p_oferta;
  return 'aceptada';
end $$;

create or replace function cancelar_oferta(p_oferta uuid) returns void
language plpgsql security definer set search_path = public as $$
declare o ofertas;
begin
  select * into o from ofertas where id = p_oferta for update;
  if not found then raise exception 'Oferta no encontrada'; end if;
  if o.comprador_id is distinct from mi_miembro(o.liga_id) then raise exception 'Esa oferta no es tuya'; end if;
  if o.estado <> 'pendiente' then raise exception 'La oferta ya no está pendiente (%)', o.estado; end if;
  update ofertas set estado = 'cancelada', resuelta_en = now() where id = p_oferta;
end $$;

-- ───────────── RPC: cesiones ─────────────
create or replace function ofrecer_cesion(p_ficha uuid, p_pct numeric) returns uuid
language plpgsql security definer set search_path = public as $$
declare f fichas; l ligas; v_m uuid; v_p uuid; v_id uuid;
begin
  select * into f from fichas where id = p_ficha for update;
  if not found then raise exception 'Ficha no encontrada'; end if;
  v_m := mi_miembro(f.liga_id);
  if v_m is null or f.propietario_id is distinct from v_m then raise exception 'Esa ficha no es tuya'; end if;
  perform exigir_mercado_abierto(f.liga_id);
  select * into l from ligas where id = f.liga_id;
  if p_pct is null or p_pct < l.cesion_pct_min or p_pct > l.cesion_pct_max then
    raise exception 'El %% de cesión debe estar entre el % %% y el % %% del valor',
      round(l.cesion_pct_min * 100), round(l.cesion_pct_max * 100);
  end if;
  v_p := proximo_partido(f.liga_id);
  if v_p is null then raise exception 'No hay ningún partido próximo con la alineación abierta'; end if;
  if exists (select 1 from cesiones where propietario_id = v_m and partido_id = v_p
                                     and estado in ('ofrecida', 'aceptada')) then
    raise exception 'Solo puedes ceder un jugador por jornada';
  end if;
  if exists (select 1 from cesiones where ficha_id = p_ficha and estado in ('ofrecida', 'aceptada')) then
    raise exception 'Esa ficha ya está ofrecida en cesión';
  end if;
  insert into cesiones (liga_id, ficha_id, propietario_id, partido_id, pct)
  values (f.liga_id, p_ficha, v_m, v_p, round(p_pct, 3))
  returning id into v_id;
  return v_id;
end $$;

create or replace function aceptar_cesion(p_cesion uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare c cesiones; f fichas; v_m uuid; v_imp numeric; v_saldo numeric;
begin
  select * into c from cesiones where id = p_cesion for update;
  if not found then raise exception 'Cesión no encontrada'; end if;
  v_m := mi_miembro(c.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if c.estado <> 'ofrecida' then raise exception 'Esa cesión ya no está disponible (%)', c.estado; end if;
  if c.propietario_id = v_m then raise exception 'No puedes aceptar tu propia cesión'; end if;
  perform exigir_mercado_abierto(c.liga_id);
  if (select alineaciones_congeladas from partidos where id = c.partido_id)
     or now() >= hora_cierre_alineacion(c.partido_id) then
    raise exception 'La alineación de ese partido ya está cerrada';
  end if;
  select * into f from fichas where id = c.ficha_id;
  if f.propietario_id is distinct from c.propietario_id then raise exception 'Esa ficha ha cambiado de dueño'; end if;
  if exists (select 1 from cesiones where cesionario_id = v_m and partido_id = c.partido_id and estado = 'aceptada') then
    raise exception 'Solo puedes recibir un jugador cedido por jornada';
  end if;
  if exists (select 1 from fichas where propietario_id = v_m and jugador_id = f.jugador_id) then
    raise exception 'Ya tienes a ese jugador en la plantilla';
  end if;
  if (select no_habitual from mercado_jugador where liga_id = c.liga_id and miembro_id = f.jugador_id)
     and no_habituales_de(c.liga_id, v_m, c.partido_id) >= 1 then
    raise exception 'Solo puedes tener un jugador no habitual en la plantilla';
  end if;
  perform asegurar_manager(c.liga_id, v_m);
  v_imp := round(c.pct * precio_actual(f.jugador_id), 2);
  v_saldo := mover_saldo(c.liga_id, v_m, -v_imp, 'cesion_pagada', f.jugador_id, c.partido_id);
  perform mover_saldo(c.liga_id, c.propietario_id, v_imp, 'cesion_cobrada', f.jugador_id, c.partido_id);
  update cesiones set estado = 'aceptada', cesionario_id = v_m, importe = v_imp, aceptada_en = now()
   where id = p_cesion;
  -- El dueño ya no puede alinearlo en ese partido
  delete from alineaciones where partido_id = c.partido_id and manager_id = c.propietario_id
                             and jugador_id = f.jugador_id;
  return v_saldo;
end $$;

create or replace function cancelar_cesion(p_cesion uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c cesiones;
begin
  select * into c from cesiones where id = p_cesion for update;
  if not found then raise exception 'Cesión no encontrada'; end if;
  if c.propietario_id is distinct from mi_miembro(c.liga_id) then raise exception 'Esa cesión no es tuya'; end if;
  if c.estado <> 'ofrecida' then raise exception 'Solo se puede retirar una cesión que nadie ha aceptado'; end if;
  update cesiones set estado = 'cancelada' where id = p_cesion;
end $$;

-- ───────────── Vistas ─────────────
-- Plantilla propia + la ficha recibida en cesión (cedida_a_mi). cedida_a_otro = no la puedes alinear esta jornada.
create view v_mi_plantilla as
select f.liga_id, f.jugador_id, f.id as ficha_id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional) as nombre,
       posicion_de(f.jugador_id) as posicion,
       f.precio_compra, mj.precio as precio_actual,
       round(mj.precio * (1 - l.comision_venta), 2) as precio_venta,
       mj.precio - f.precio_compra as plusvalia,
       mj.no_habitual, f.adquirida_en as comprado_en,
       greatest(f.clausula, mj.precio) as clausula,
       f.protegida_jornadas > 0 as protegida,
       false as cedida_a_mi,
       ficha_cedida(f.id) as cedida_a_otro,
       (select c.partido_id from cesiones c where c.ficha_id = f.id and c.estado in ('ofrecida', 'aceptada')) as cesion_partido_id,
       (select c.estado from cesiones c where c.ficha_id = f.id and c.estado in ('ofrecida', 'aceptada')) as cesion_estado,
       (select c.estado from partidos p join convocatorias c on c.partido_id = p.id and c.miembro_id = f.jugador_id
         where p.liga_id = f.liga_id and p.estado in ('abierto', 'completo', 'equipos_hechos')
         order by p.fecha_hora limit 1) as estado_proximo_partido
  from fichas f
  join miembros m on m.id = f.jugador_id
  join ligas l on l.id = f.liga_id
  left join perfiles pe on pe.id = m.perfil_id
  left join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
 where f.propietario_id = mi_miembro(f.liga_id)
union all
select f.liga_id, f.jugador_id, f.id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional),
       posicion_de(f.jugador_id),
       null, mj.precio, null, null,
       mj.no_habitual, c.aceptada_en,
       null, false,
       true, false, c.partido_id, c.estado,
       (select cv.estado from convocatorias cv where cv.partido_id = c.partido_id and cv.miembro_id = f.jugador_id)
  from cesiones c
  join fichas f on f.id = c.ficha_id
  join miembros m on m.id = f.jugador_id
  left join perfiles pe on pe.id = m.perfil_id
  left join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
 where c.estado = 'aceptada' and c.cesionario_id = mi_miembro(c.liga_id);

-- Ofertas enviadas y recibidas por mí
create view v_mis_ofertas as
select o.id as oferta_id, o.liga_id, o.ficha_id, f.jugador_id,
       coalesce(pj.apodo, pj.nombre, mj_m.nombre_provisional) as jugador_nombre,
       case when o.comprador_id = mi_miembro(o.liga_id) then 'enviada' else 'recibida' end as direccion,
       o.comprador_id, coalesce(pc.apodo, pc.nombre, mc.nombre_provisional) as comprador_nombre,
       o.vendedor_id,  coalesce(pv.apodo, pv.nombre, mv.nombre_provisional) as vendedor_nombre,
       o.importe, o.estado, o.creada_en, o.expira_en, o.resuelta_en,
       mk.precio as precio_mercado,
       case when f.propietario_id is not null then greatest(f.clausula, mk.precio) end as clausula_actual
  from ofertas o
  join fichas f on f.id = o.ficha_id
  join miembros mj_m on mj_m.id = f.jugador_id left join perfiles pj on pj.id = mj_m.perfil_id
  join miembros mc on mc.id = o.comprador_id left join perfiles pc on pc.id = mc.perfil_id
  join miembros mv on mv.id = o.vendedor_id left join perfiles pv on pv.id = mv.perfil_id
  left join mercado_jugador mk on mk.liga_id = f.liga_id and mk.miembro_id = f.jugador_id
 where mi_miembro(o.liga_id) in (o.comprador_id, o.vendedor_id);

-- Cesiones ofrecidas y aún aceptables (visibles para toda la liga)
create view v_cesiones_disponibles as
select c.id as cesion_id, c.liga_id, c.ficha_id, f.jugador_id,
       coalesce(pj.apodo, pj.nombre, mj_m.nombre_provisional) as jugador_nombre,
       c.propietario_id, coalesce(pp.apodo, pp.nombre, mp.nombre_provisional) as propietario_nombre,
       c.pct, round(c.pct * mk.precio, 2) as importe, mk.precio as precio_mercado, mk.no_habitual,
       c.partido_id, pa.fecha_hora, hora_cierre_alineacion(c.partido_id) as cierre,
       c.propietario_id = mi_miembro(c.liga_id) as es_mia
  from cesiones c
  join fichas f on f.id = c.ficha_id
  join partidos pa on pa.id = c.partido_id
  join miembros mj_m on mj_m.id = f.jugador_id left join perfiles pj on pj.id = mj_m.perfil_id
  join miembros mp on mp.id = c.propietario_id left join perfiles pp on pp.id = mp.perfil_id
  left join mercado_jugador mk on mk.liga_id = f.liga_id and mk.miembro_id = f.jugador_id
 where c.estado = 'ofrecida' and es_miembro(c.liga_id)
   and not pa.alineaciones_congeladas and now() < hora_cierre_alineacion(c.partido_id);
