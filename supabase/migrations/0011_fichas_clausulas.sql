-- 0011 · Fichas limitadas y cláusulas de rescisión (ampliación 0.2, docs/mercado_fantasy.md §9.1–9.3, §9.6)
-- Sustituye la propiedad compartida ilimitada (tabla plantillas) por C fichas por jugador.
-- `plantillas` pasa a ser una VISTA sobre las fichas con dueño, para que las funciones de 0008 que la leen
-- (precios, congelación, clasificación) sigan funcionando.
--
-- Decisiones:
--  · Protección: en vez de guardar el partido hasta el que está protegida, cada ficha guarda
--    protegida_jornadas (= ligas.proteccion_jornadas al adquirirla) y liquidar_jornada lo descuenta.
--    Con el valor por defecto 1, una ficha adquirida no se puede clausular hasta que se cierre el próximo partido.
--  · La cláusula efectiva es siempre max(clausula, precio de mercado); además, tras cada jornada se sube en la
--    tabla la de las fichas que se hayan quedado por debajo del nuevo precio.
--  · Las fichas libres no tienen cláusula (null).
--  · C = max(2, ⌈M·max_plantilla·0,8 / P⌉) solo crece: se recalcula al entrar mánagers (fantasy_managers) o
--    jugadores (mercado_jugador).
--  · transacciones_fantasy.tipo pasa de enum a texto con CHECK, para añadir tipos sin ALTER TYPE … ADD VALUE
--    (que no se puede usar en la misma transacción en la que se crea).

-- ───────────── Parámetros nuevos ─────────────
alter table ligas
  add column copias_por_jugador       smallint     not null default 2    check (copias_por_jugador >= 1),
  add column coste_subida_clausula    numeric(4,3) not null default 0.10 check (coste_subida_clausula between 0 and 1),
  add column proteccion_jornadas      smallint     not null default 1    check (proteccion_jornadas between 0 and 10),
  add column cesion_pct_min           numeric(4,3) not null default 0.05,
  add column cesion_pct_max           numeric(4,3) not null default 0.30,
  add column horas_caducidad_oferta   smallint     not null default 48   check (horas_caducidad_oferta between 1 and 720),
  add column partidos_min_rendimiento smallint     not null default 3    check (partidos_min_rendimiento between 0 and 50),
  add constraint ligas_cesion_ck check (cesion_pct_min > 0 and cesion_pct_min <= cesion_pct_max and cesion_pct_max <= 1);

alter table transacciones_fantasy alter column tipo type text using tipo::text;
alter table transacciones_fantasy add constraint transacciones_tipo_ck check (tipo in (
  'presupuesto_inicial', 'compra', 'venta', 'ingreso_puntos', 'ajuste',
  'clausula_pagada', 'clausula_cobrada', 'subida_clausula',
  'oferta_pagada', 'oferta_cobrada', 'cesion_pagada', 'cesion_cobrada'));

-- ───────────── Fichas ─────────────
create table fichas (
  id                  uuid primary key default gen_random_uuid(),
  liga_id             uuid not null references ligas on delete cascade,
  jugador_id          uuid not null references miembros on delete cascade,
  numero              smallint not null check (numero >= 1),
  propietario_id      uuid references miembros on delete set null,   -- null = libre en el mercado
  clausula            numeric(7,2) check (clausula > 0),
  precio_compra       numeric(7,2),
  adquirida_en        timestamptz,
  protegida_jornadas  smallint not null default 0 check (protegida_jornadas >= 0),
  unique (liga_id, jugador_id, numero)
);
create unique index fichas_un_dueno_por_jugador on fichas (propietario_id, jugador_id) where propietario_id is not null;
create index on fichas (liga_id, propietario_id);
create index on fichas (liga_id, jugador_id) where propietario_id is null;

-- ───────────── Nº de fichas por jugador ─────────────
create or replace function copias_formula(p_liga uuid) returns int
language sql stable security definer set search_path = public as $$
  select greatest(2, ceil(
           (select count(*) from fantasy_managers fm join miembros m on m.id = fm.miembro_id
             where fm.liga_id = p_liga and m.estado = 'activo')::numeric
           * (select max_plantilla from ligas where id = p_liga) * 0.8
           / nullif((select count(*) from mercado_jugador mj where mj.liga_id = p_liga
                      and mj.miembro_id in (select jugadores_liga(p_liga))), 0)))::int
$$;

-- Sube C si toca (nunca baja) y crea las fichas que falten. Idempotente.
create or replace function asegurar_fichas(p_liga uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_c int;
begin
  select greatest(copias_por_jugador, coalesce(copias_formula(p_liga), 2)) into v_c from ligas where id = p_liga;
  update ligas set copias_por_jugador = v_c where id = p_liga and copias_por_jugador <> v_c;
  insert into fichas (liga_id, jugador_id, numero)
  select mj.liga_id, mj.miembro_id, n
    from mercado_jugador mj cross join generate_series(1, v_c) n
   where mj.liga_id = p_liga
  on conflict (liga_id, jugador_id, numero) do nothing;
  return v_c;
end $$;

create or replace function tras_alta_fichas() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform asegurar_fichas(new.liga_id);
  return null;
end $$;

create trigger t_fichas_manager after insert on fantasy_managers
  for each row execute function tras_alta_fichas();
create trigger t_fichas_jugador after insert on mercado_jugador
  for each row execute function tras_alta_fichas();

-- ───────────── Migración de datos: plantillas → fichas ─────────────
-- C cubre a los dueños actuales aunque la fórmula diera menos.
update ligas l
   set copias_por_jugador = greatest(2, copias_formula(l.id),
                                     coalesce((select max(n) from (select count(*) n from plantillas p
                                                                     where p.liga_id = l.id
                                                                     group by p.jugador_id) t), 0))
 where exists (select 1 from mercado_jugador where liga_id = l.id);
select asegurar_fichas(l.id) from ligas l where exists (select 1 from mercado_jugador where liga_id = l.id);

update fichas f
   set propietario_id = x.manager_id, precio_compra = x.precio_compra, adquirida_en = x.comprado_en,
       clausula = greatest(x.precio_compra, mj.precio), protegida_jornadas = 0
  from (select p.*, row_number() over (partition by p.liga_id, p.jugador_id order by p.comprado_en, p.manager_id) rn
          from plantillas p) x
  join mercado_jugador mj on mj.liga_id = x.liga_id and mj.miembro_id = x.jugador_id
 where f.liga_id = x.liga_id and f.jugador_id = x.jugador_id and f.numero = x.rn;

-- La tabla plantillas pasa a ser una vista sobre las fichas con dueño
drop view v_mercado;
drop view v_mi_plantilla;
drop view v_clasificacion_managers;
drop table plantillas;

create view plantillas with (security_invoker = true) as
select f.liga_id, f.propietario_id as manager_id, f.jugador_id, f.precio_compra, f.adquirida_en as comprado_en,
       f.id as ficha_id, f.clausula
  from fichas f
 where f.propietario_id is not null;

-- ───────────── Ayudantes ─────────────
-- Mueve saldo de un mánager y deja la transacción. Falla si el saldo quedaría negativo.
create or replace function mover_saldo(p_liga uuid, p_manager uuid, p_importe numeric, p_tipo text,
                                       p_jugador uuid default null, p_partido uuid default null) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_saldo numeric;
begin
  perform asegurar_manager(p_liga, p_manager);
  select saldo into v_saldo from fantasy_managers where liga_id = p_liga and miembro_id = p_manager for update;
  if v_saldo + p_importe < 0 then
    raise exception 'Saldo insuficiente: hay % M y hacen falta % M', v_saldo, -p_importe;
  end if;
  update fantasy_managers set saldo = saldo + p_importe where liga_id = p_liga and miembro_id = p_manager;
  insert into transacciones_fantasy (liga_id, manager_id, jugador_id, partido_id, tipo, importe, saldo_despues)
  values (p_liga, p_manager, p_jugador, p_partido, p_tipo, round(p_importe, 2), v_saldo + p_importe);
  return v_saldo + p_importe;
end $$;

-- Próximo partido de la liga con la alineación aún abierta (para cesiones y límite de no habituales)
create or replace function proximo_partido(p_liga uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select p.id from partidos p
   where p.liga_id = p_liga and p.estado in ('abierto', 'completo', 'equipos_hechos')
     and not p.alineaciones_congeladas and now() < hora_cierre_alineacion(p.id)
   order by p.fecha_hora limit 1
$$;

-- Precio de mercado actual de un jugador
create or replace function precio_actual(p_jugador uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select precio from mercado_jugador where miembro_id = p_jugador
$$;

-- Cláusula efectiva: nunca por debajo del valor de mercado
create or replace function clausula_efectiva(p_ficha uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select greatest(f.clausula, mj.precio)
    from fichas f join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
   where f.id = p_ficha and f.propietario_id is not null
$$;

-- Nº de no habituales de un mánager (fichas propias; 0012 añade la cedida que recibe esa jornada)
create or replace function no_habituales_de(p_liga uuid, p_manager uuid, p_partido uuid default null) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from fichas f
    join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
   where f.liga_id = p_liga and f.propietario_id = p_manager and mj.no_habitual
$$;

-- ¿Puede este mánager incorporar a este jugador? (lanza el motivo si no)
create or replace function validar_hueco(p_liga uuid, p_manager uuid, p_jugador uuid) returns void
language plpgsql stable security definer set search_path = public as $$
declare l ligas; v_n int;
begin
  select * into l from ligas where id = p_liga;
  if exists (select 1 from fichas where propietario_id = p_manager and jugador_id = p_jugador) then
    raise exception 'Ya tienes a ese jugador en la plantilla';
  end if;
  select count(*) into v_n from fichas where liga_id = p_liga and propietario_id = p_manager;
  if v_n >= l.max_plantilla then
    raise exception 'La plantilla está llena (máximo % jugadores)', l.max_plantilla;
  end if;
  if (select no_habitual from mercado_jugador where liga_id = p_liga and miembro_id = p_jugador)
     and no_habituales_de(p_liga, p_manager, proximo_partido(p_liga)) >= 1 then
    raise exception 'Solo puedes tener un jugador no habitual en la plantilla';
  end if;
end $$;

-- ¿Está la ficha cedida en una cesión en curso? (0012 la redefine; aquí aún no hay cesiones)
create or replace function ficha_cedida(p_ficha uuid) returns boolean
language sql stable set search_path = public as $$ select false $$;

-- Antes de que una ficha cambie de dueño o quede libre: limpia lo que dependía del dueño anterior
-- (0012 añade la cancelación de ofertas y cesiones)
create or replace function soltar_ficha(p_ficha uuid) returns void
language plpgsql security definer set search_path = public as $$
declare f fichas;
begin
  select * into f from fichas where id = p_ficha;
  if f.propietario_id is null then return; end if;
  -- fuera de las alineaciones aún no congeladas del dueño anterior
  delete from alineaciones a using partidos p
   where a.partido_id = p.id and p.liga_id = f.liga_id and not p.alineaciones_congeladas
     and a.manager_id = f.propietario_id and a.jugador_id = f.jugador_id;
end $$;

-- Asigna la ficha a un nuevo dueño por un importe (compra, cláusula u oferta)
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
         adquirida_en = now(), protegida_jornadas = l.proteccion_jornadas
   where id = p_ficha;
end $$;

create or replace function exigir_mercado_abierto(p_liga uuid) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not mercado_abierto(p_liga) then
    raise exception 'El mercado está cerrado (desde % h antes de un partido hasta que se calculan sus puntos)',
      (select horas_cierre_alineacion from ligas where id = p_liga);
  end if;
end $$;

-- ───────────── RPC: comprar y vender fichas ─────────────
create or replace function comprar_ficha(p_liga uuid, p_jugador uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_m uuid; mj mercado_jugador; f fichas; v_saldo numeric;
begin
  v_m := mi_miembro(p_liga);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  perform exigir_mercado_abierto(p_liga);
  perform asegurar_manager(p_liga, v_m);
  select * into mj from mercado_jugador where liga_id = p_liga and miembro_id = p_jugador;
  if not found or p_jugador not in (select jugadores_liga(p_liga)) then
    raise exception 'Ese jugador no está en el mercado';
  end if;
  perform validar_hueco(p_liga, v_m, p_jugador);
  select * into f from fichas where liga_id = p_liga and jugador_id = p_jugador and propietario_id is null
   order by numero limit 1 for update skip locked;
  if not found then
    raise exception 'No quedan fichas libres de este jugador: puedes pagar la cláusula de un dueño o hacerle una oferta';
  end if;
  v_saldo := mover_saldo(p_liga, v_m, -mj.precio, 'compra', p_jugador);
  perform transferir_ficha(f.id, v_m, mj.precio);
  return v_saldo;
end $$;

create or replace function vender_ficha(p_ficha uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare f fichas; l ligas; v_m uuid; v_cobro numeric;
begin
  select * into f from fichas where id = p_ficha for update;
  if not found then raise exception 'Ficha no encontrada'; end if;
  v_m := mi_miembro(f.liga_id);
  if v_m is null or f.propietario_id is distinct from v_m then raise exception 'Esa ficha no es tuya'; end if;
  perform exigir_mercado_abierto(f.liga_id);
  if ficha_cedida(p_ficha) then raise exception 'Está cedida esta jornada: no se puede vender hasta que vuelva'; end if;
  select * into l from ligas where id = f.liga_id;
  v_cobro := round(precio_actual(f.jugador_id) * (1 - l.comision_venta), 2);
  perform soltar_ficha(p_ficha);
  update fichas set propietario_id = null, clausula = null, precio_compra = null, adquirida_en = null,
                    protegida_jornadas = 0
   where id = p_ficha;
  return mover_saldo(f.liga_id, v_m, v_cobro, 'venta', f.jugador_id);
end $$;

-- Envoltorios con la firma de la app 0.1
create or replace function comprar_jugador(p_liga uuid, p_jugador uuid) returns numeric
language plpgsql security definer set search_path = public as $$
begin
  return comprar_ficha(p_liga, p_jugador);
end $$;

create or replace function vender_jugador(p_liga uuid, p_jugador uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_f uuid;
begin
  select id into v_f from fichas where liga_id = p_liga and jugador_id = p_jugador
                                   and propietario_id = mi_miembro(p_liga);
  if v_f is null then raise exception 'Ese jugador no está en tu plantilla'; end if;
  return vender_ficha(v_f);
end $$;

-- ───────────── RPC: cláusulas ─────────────
-- Fijar la cláusula: subirla cuesta coste_subida_clausula × subida; bajarla es gratis (mínimo: valor de mercado)
create or replace function fijar_clausula(p_ficha uuid, p_importe numeric) returns numeric
language plpgsql security definer set search_path = public as $$
declare f fichas; l ligas; v_m uuid; v_precio numeric; v_actual numeric; v_nueva numeric; v_coste numeric;
begin
  select * into f from fichas where id = p_ficha for update;
  if not found then raise exception 'Ficha no encontrada'; end if;
  v_m := mi_miembro(f.liga_id);
  if v_m is null or f.propietario_id is distinct from v_m then raise exception 'Esa ficha no es tuya'; end if;
  perform exigir_mercado_abierto(f.liga_id);
  select * into l from ligas where id = f.liga_id;
  v_precio := precio_actual(f.jugador_id);
  v_nueva := round(p_importe, 2);
  if v_nueva < v_precio then
    raise exception 'La cláusula no puede ser menor que el valor de mercado (% M)', v_precio;
  end if;
  v_actual := greatest(f.clausula, v_precio);
  if v_nueva > v_actual then
    v_coste := round((v_nueva - v_actual) * l.coste_subida_clausula, 2);
    if v_coste > 0 then
      perform mover_saldo(f.liga_id, v_m, -v_coste, 'subida_clausula', f.jugador_id);
    end if;
  end if;
  update fichas set clausula = v_nueva where id = p_ficha;
  return v_nueva;
end $$;

-- Pagar la cláusula: el dueño no puede negarse
create or replace function pagar_clausula(p_ficha uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare f fichas; v_m uuid; v_imp numeric; v_saldo numeric; v_dueno uuid;
begin
  select * into f from fichas where id = p_ficha for update;
  if not found then raise exception 'Ficha no encontrada'; end if;
  v_m := mi_miembro(f.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if f.propietario_id is null then raise exception 'Esa ficha está libre: cómprala en el mercado'; end if;
  if f.propietario_id = v_m then raise exception 'Esa ficha ya es tuya'; end if;
  perform exigir_mercado_abierto(f.liga_id);
  if f.protegida_jornadas > 0 then
    raise exception 'Ficha protegida: se adquirió hace poco y no se puede clausular hasta que se cierre el próximo partido';
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

-- ───────────── Vistas (v_mi_plantilla se crea en 0012, con las cesiones) ─────────────
create view v_mercado as
select mj.liga_id, mj.miembro_id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional) as nombre,
       posicion_de(mj.miembro_id) as posicion,
       m.estado,
       mj.precio, mj.rating, mj.no_habitual,
       vj.general as valoracion_encuesta,
       mj.precio - coalesce(prev.precio, mj.precio) as variacion,
       round(100 * (mj.precio - coalesce(prev.precio, mj.precio)) / nullif(coalesce(prev.precio, mj.precio), 0), 1)
         as variacion_pct,
       coalesce(h.duenos, 0) as num_plantillas,
       round(100.0 * coalesce(h.duenos, 0) / nullif((select count(*) from fantasy_managers f where f.liga_id = mj.liga_id), 0), 1)
         as pct_plantillas,
       exists (select 1 from fichas f where f.propietario_id = mi_miembro(mj.liga_id)
                 and f.jugador_id = mj.miembro_id) as en_mi_plantilla,
       round(mj.precio * (1 - l.comision_venta), 2) as precio_venta,
       coalesce(h.total, 0) as fichas_totales,
       coalesce(h.total, 0) - coalesce(h.duenos, 0) as fichas_libres,
       (select min(greatest(f.clausula, mj.precio)) from fichas f
         where f.liga_id = mj.liga_id and f.jugador_id = mj.miembro_id and f.propietario_id is not null
           and f.propietario_id is distinct from mi_miembro(mj.liga_id)
           and f.protegida_jornadas = 0 and not ficha_cedida(f.id)) as clausula_minima,
       (select f.id from fichas f where f.propietario_id = mi_miembro(mj.liga_id)
          and f.jugador_id = mj.miembro_id) as mi_ficha_id
  from mercado_jugador mj
  join miembros m on m.id = mj.miembro_id
  join ligas l on l.id = mj.liga_id
  left join perfiles pe on pe.id = m.perfil_id
  left join valoracion_jugador vj on vj.liga_id = mj.liga_id and vj.miembro_id = mj.miembro_id
  left join (select jugador_id, count(*) total, count(propietario_id) duenos from fichas group by jugador_id) h
    on h.jugador_id = mj.miembro_id
  left join lateral (select hp.precio from historial_precios hp
                      where hp.liga_id = mj.liga_id and hp.miembro_id = mj.miembro_id
                      order by hp.creado_en desc, hp.id desc offset 1 limit 1) prev on true
 where es_miembro(mj.liga_id) and m.estado in ('activo', 'pendiente_registro');

create view v_clasificacion_managers as
select fm.liga_id, fm.miembro_id as manager_id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional) as nombre,
       fm.puntos_totales, fm.saldo,
       coalesce(v.valor, 0) as valor_plantilla,
       fm.saldo + coalesce(v.valor, 0) as patrimonio,
       (select pm.puntos from puntos_manager pm join partidos p on p.id = pm.partido_id
         where pm.manager_id = fm.miembro_id order by p.fecha_hora desc limit 1) as puntos_ultima_jornada,
       rank() over (partition by fm.liga_id
                    order by fm.puntos_totales desc, fm.saldo + coalesce(v.valor, 0) desc) as posicion
  from fantasy_managers fm
  join miembros m on m.id = fm.miembro_id
  left join perfiles pe on pe.id = m.perfil_id
  left join (select f.propietario_id, sum(mj.precio) valor
               from fichas f join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
              where f.propietario_id is not null
              group by f.propietario_id) v on v.propietario_id = fm.miembro_id
 where es_miembro(fm.liga_id) and m.estado = 'activo';

-- Fichas de un jugador: dueño, cláusula efectiva, protección (la app filtra por jugador_id)
create view v_fichas_jugador as
select f.id as ficha_id, f.liga_id, f.jugador_id, f.numero,
       f.propietario_id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional) as propietario_nombre,
       case when f.propietario_id is not null then greatest(f.clausula, mj.precio) end as clausula,
       f.protegida_jornadas > 0 as protegida,
       ficha_cedida(f.id) as cedida,
       f.propietario_id = mi_miembro(f.liga_id) as es_mia,
       f.precio_compra, f.adquirida_en
  from fichas f
  join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
  left join miembros m on m.id = f.propietario_id
  left join perfiles pe on pe.id = m.perfil_id
 where es_miembro(f.liga_id);
