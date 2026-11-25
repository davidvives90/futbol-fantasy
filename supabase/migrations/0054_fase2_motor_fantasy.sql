-- 0054 · Fase 2: motor Fantasy avanzado
--  1. Economía en escala de 50 M (valor base por jugador). Presupuesto = jugadores por equipo × base + base/5
--     (F5 260 M, F7 360 M, F11 560 M) o uno fijo del admin. Las ligas existentes se reescalan ×40/3 (calidad 50 = 50 M).
--  2. Copias según mánagers y jugadores: siempre hay copias para que cada mánager tenga alineación completa + 1
--     reserva: C = ⌈M·(N+1)/P⌉ (mín. 1, máx. M). Modo rareza (copia 1 ×1,25 pts y ×1,5 precio; 2-3 ×1,10 y ×1,2)
--     e inflación por escasez (+10 % por cada copia con dueño).
--  3. Inicio: reparto (se cobra del presupuesto), mercado libre, subasta diaria (lote de N copias) o draft por turnos.
--  4. Cláusula automática = % del precio pagado (150 % por defecto).
--  5. Alineación táctica o libre, capitán ×2, ariete +3 si marca, 1-2 suplentes que entran solos.
--  6. Jornadas especiales (doble puntuación, goles dobles) y prima inversa para los últimos.
--  7. Herencia al cerrar la temporada: nada, reinicio total, heredar valor de mercado o heredar bonus.

-- ───────────── 1. Configuración ─────────────
alter table ligas
  add column if not exists valor_base numeric(6,2) not null default 50 check (valor_base between 1 and 500),
  add column if not exists presupuesto_fijo numeric(8,2) check (presupuesto_fijo is null or presupuesto_fijo > 0),
  add column if not exists modo_inicio text not null default 'reparto'
    check (modo_inicio in ('reparto', 'mercado', 'subasta', 'draft')),
  add column if not exists modo_copias text not null default 'clasico' check (modo_copias in ('clasico', 'rareza')),
  add column if not exists inflacion_escasez boolean not null default false,
  add column if not exists clausula_pct numeric(4,2) not null default 1.5 check (clausula_pct between 1 and 5),
  add column if not exists modo_alineacion text not null default 'tactico' check (modo_alineacion in ('tactico', 'libre')),
  add column if not exists suplentes smallint not null default 1 check (suplentes between 0 and 2),
  add column if not exists capitan_activo boolean not null default true,
  add column if not exists ariete_activo boolean not null default true,
  add column if not exists prima_inversa numeric(7,2) not null default 0 check (prima_inversa >= 0),
  add column if not exists subasta_tipo text not null default 'abierta' check (subasta_tipo in ('abierta', 'ciega')),
  add column if not exists subasta_lote smallint not null default 1 check (subasta_lote between 1 and 10),
  add column if not exists subasta_horas smallint not null default 24 check (subasta_horas between 1 and 72),
  add column if not exists subasta_hora time not null default '10:00',
  add column if not exists subasta_puja_min numeric(7,2) check (subasta_puja_min is null or subasta_puja_min > 0),
  add column if not exists auto_fichaje boolean not null default true,
  add column if not exists herencia_temporada text not null default 'ninguna'
    check (herencia_temporada in ('ninguna', 'reinicio', 'valor', 'bonus'));
alter table ligas alter column precio_min set default 15;
alter table ligas alter column precio_max set default 155;
alter table ligas alter column ingreso_por_punto set default 0.5;

alter table partidos add column if not exists evento_especial text
  check (evento_especial is null or evento_especial in ('doble_puntos', 'goles_dobles'));

alter table alineaciones
  add column if not exists capitan boolean not null default false,
  add column if not exists ariete boolean not null default false,
  add column if not exists suplente smallint check (suplente between 1 and 2),
  add column if not exists entra_por uuid,
  add column if not exists sustituido boolean not null default false;
alter table puntos_manager add column if not exists prima numeric(8,2) not null default 0;
alter table transacciones_fantasy drop constraint if exists transacciones_tipo_ck;
alter table transacciones_fantasy add constraint transacciones_tipo_ck check (tipo in (
  'presupuesto_inicial', 'compra', 'venta', 'ingreso_puntos', 'ajuste', 'clausula_pagada', 'clausula_cobrada',
  'subida_clausula', 'oferta_pagada', 'oferta_cobrada', 'cesion_pagada', 'cesion_cobrada',
  'reparto_inicial', 'subasta', 'draft', 'herencia_temporada'));

-- La plantilla siempre admite alineación completa + 1 reserva
create or replace function ajustar_plantilla() returns trigger
language plpgsql as $$
begin
  new.max_plantilla := least(15, greatest(new.max_plantilla, new.jugadores_por_equipo + greatest(1, new.suplentes)));
  return new;
end $$;
drop trigger if exists t_ajustar_plantilla on ligas;
create trigger t_ajustar_plantilla before insert or update of max_plantilla, jugadores_por_equipo, suplentes on ligas
  for each row execute function ajustar_plantilla();

-- ───────────── Reescalado de la economía ─────────────
create or replace function _reescalar_economia(p_liga uuid, p_factor numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_factor is null or p_factor <= 0 or p_factor = 1 then return; end if;
  update fantasy_managers set saldo = round(saldo * p_factor, 2) where liga_id = p_liga;
  update mercado_jugador set precio = greatest(0.05, redondear_005(precio * p_factor)) where liga_id = p_liga;
  update historial_precios set precio = round(precio * p_factor, 2) where liga_id = p_liga;
  update fichas set precio_compra = round(precio_compra * p_factor, 2), clausula = round(clausula * p_factor, 2)
   where liga_id = p_liga;
  update transacciones_fantasy set importe = round(importe * p_factor, 2), saldo_despues = round(saldo_despues * p_factor, 2)
   where liga_id = p_liga;
  update puntos_manager pm set ingreso = round(ingreso * p_factor, 2), prima = round(prima * p_factor, 2)
    from partidos p where p.id = pm.partido_id and p.liga_id = p_liga;
  update ofertas set importe = round(importe * p_factor, 2) where liga_id = p_liga;
  update cesiones set importe = round(importe * p_factor, 2) where liga_id = p_liga and importe is not null;
  update ligas set precio_min = round(precio_min * p_factor, 2), precio_max = round(precio_max * p_factor, 2),
                   presupuesto_inicial = round(presupuesto_inicial * p_factor, 2),
                   presupuesto_fijo = round(presupuesto_fijo * p_factor, 2),
                   ingreso_por_punto = round(ingreso_por_punto * p_factor, 3),
                   subasta_puja_min = round(subasta_puja_min * p_factor, 2),
                   prima_inversa = round(prima_inversa * p_factor, 2),
                   valor_base = round(valor_base * p_factor, 2)
   where id = p_liga;
end $$;
revoke execute on function _reescalar_economia(uuid, numeric) from public, anon, authenticated;

-- El admin cambia el valor base: todo el dinero de la liga se multiplica en proporción.
create or replace function cambiar_escala(p_liga uuid, p_valor_base numeric) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_actual numeric;
begin
  perform exigir_admin(p_liga);
  if p_valor_base is null or p_valor_base < 1 or p_valor_base > 500 then
    raise exception 'El valor base va de 1 a 500 M';
  end if;
  select valor_base into v_actual from ligas where id = p_liga for update;
  perform _reescalar_economia(p_liga, p_valor_base / v_actual);
  update ligas set valor_base = p_valor_base where id = p_liga;
  return p_valor_base;
end $$;
revoke execute on function cambiar_escala(uuid, numeric) from public, anon;
grant execute on function cambiar_escala(uuid, numeric) to authenticated;

-- Ligas existentes: de la escala antigua (calidad 50 ≈ 3,75 M) a la nueva (50 M). Se mantiene el ingreso por punto
-- proporcional para no cambiar el equilibrio a mitad de temporada. El presupuesto de los nuevos mánagers pasa a
-- ser su dinero de antes + lo que vale un reparto inicial (ahora el reparto se cobra).
do $$
declare l record;
begin
  for l in select * from ligas loop
    update ligas set valor_base = 3.75 where id = l.id;
    perform _reescalar_economia(l.id, 50 / 3.75);
    update ligas set valor_base = 50, precio_min = 15, precio_max = 155,
                     presupuesto_fijo = case when presupuesto_inicial is not null
                                             then round(presupuesto_inicial + least(reparto_inicial, max_plantilla) * 50) end,
                     max_plantilla = max_plantilla
     where id = l.id;
  end loop;
end $$;

-- ───────────── Subastas y draft (tablas) ─────────────
create table if not exists subastas (
  id            uuid primary key default gen_random_uuid(),
  liga_id       uuid not null references ligas on delete cascade,
  ficha_id      uuid not null references fichas on delete cascade,
  jugador_id    uuid not null references miembros on delete cascade,
  tipo          text not null check (tipo in ('abierta', 'ciega')),
  precio_salida numeric(7,2) not null check (precio_salida > 0),
  abre_en       timestamptz not null default now(),
  cierra_en     timestamptz not null,
  estado        text not null default 'abierta' check (estado in ('abierta', 'adjudicada', 'desierta', 'cancelada')),
  ganador_id    uuid references miembros on delete set null,
  importe       numeric(7,2),
  resuelta_en   timestamptz
);
create unique index if not exists subastas_ficha_abierta on subastas (ficha_id) where estado = 'abierta';
create index if not exists subastas_liga on subastas (liga_id, estado, cierra_en);
create table if not exists pujas (
  subasta_id uuid not null references subastas on delete cascade,
  manager_id uuid not null references miembros on delete cascade,
  importe    numeric(7,2) not null check (importe > 0),
  creada_en  timestamptz not null default now(),
  primary key (subasta_id, manager_id)
);
alter table subastas enable row level security;
alter table pujas enable row level security;
drop policy if exists subastas_leer on subastas;
create policy subastas_leer on subastas for select using (es_miembro(liga_id));
drop policy if exists pujas_propias on pujas;
create policy pujas_propias on pujas for select
  using (manager_id = mi_miembro((select liga_id from subastas s where s.id = subasta_id)));
grant select on subastas, pujas to authenticated;

create table if not exists drafts (
  liga_id     uuid primary key references ligas on delete cascade,
  estado      text not null default 'en_curso' check (estado in ('en_curso', 'terminado')),
  orden       uuid[] not null,
  rondas      smallint not null check (rondas between 1 and 15),
  pick        int not null default 0,
  iniciado_en timestamptz not null default now(),
  turno_desde timestamptz not null default now()
);
create table if not exists draft_picks (
  liga_id    uuid not null references ligas on delete cascade,
  pick       int not null,
  manager_id uuid not null references miembros on delete cascade,
  jugador_id uuid references miembros on delete set null,
  importe    numeric(7,2),
  creado_en  timestamptz not null default now(),
  primary key (liga_id, pick)
);
alter table drafts enable row level security;
alter table draft_picks enable row level security;
drop policy if exists drafts_leer on drafts;
create policy drafts_leer on drafts for select using (es_miembro(liga_id));
drop policy if exists draft_picks_leer on draft_picks;
create policy draft_picks_leer on draft_picks for select using (es_miembro(liga_id));
grant select on drafts, draft_picks to authenticated;

-- ───────────── Presupuesto y copias ─────────────
create or replace function presupuesto_liga(p_liga uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(l.presupuesto_fijo, l.jugadores_por_equipo * l.valor_base + round(l.valor_base / 5, 2))
    from ligas l where l.id = p_liga
$$;

-- Copias = las justas para que todos los mánagers puedan tener alineación completa + 1 reserva.
create or replace function copias_formula(p_liga uuid) returns int
language sql stable security definer set search_path = public as $$
  with d as (
    select (select count(*) from fantasy_managers fm join miembros m on m.id = fm.miembro_id
             where fm.liga_id = p_liga and m.estado = 'activo') as m,
           (select jugadores_por_equipo from ligas where id = p_liga) as n,
           (select count(*) from mercado_jugador mj where mj.liga_id = p_liga
              and mj.miembro_id in (select jugadores_liga(p_liga))) as p)
  select case when p = 0 or m = 0 then 1
              else least(m, greatest(1, ceil(m * (n + 1)::numeric / p)))::int end
    from d
$$;
revoke execute on function copias_formula(uuid) from public, anon, authenticated;

-- Multiplicadores de la copia (modo rareza)
create or replace function factor_precio_copia(p_modo text, p_numero int) returns numeric
language sql immutable as $$
  select case when p_modo = 'rareza' then case when p_numero = 1 then 1.5 when p_numero <= 3 then 1.2 else 1 end else 1 end
$$;
create or replace function factor_puntos_copia(p_modo text, p_numero int) returns numeric
language sql immutable as $$
  select case when p_modo = 'rareza' then case when p_numero = 1 then 1.25 when p_numero <= 3 then 1.10 else 1 end else 1 end
$$;

-- Precio de una copia: valor de mercado × rareza × escasez (+10 % por cada copia del jugador que ya tiene dueño)
create or replace function precio_ficha(p_ficha uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select redondear_005(mj.precio * factor_precio_copia(l.modo_copias, f.numero)
         * case when l.inflacion_escasez
                then 1 + 0.1 * (select count(*) from fichas x where x.liga_id = f.liga_id and x.jugador_id = f.jugador_id
                                                              and x.propietario_id is not null)
                else 1 end)
    from fichas f join ligas l on l.id = f.liga_id
    join mercado_jugador mj on mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id
   where f.id = p_ficha
$$;

-- Copia libre más barata de un jugador (la de número más alto)
create or replace function ficha_libre(p_liga uuid, p_jugador uuid, p_numero int default null) returns uuid
language sql stable security definer set search_path = public as $$
  select f.id from fichas f
   where f.liga_id = p_liga and f.jugador_id = p_jugador and f.propietario_id is null
     and (p_numero is null or f.numero = p_numero)
     and not exists (select 1 from subastas s where s.ficha_id = f.id and s.estado = 'abierta')
   order by f.numero desc limit 1
$$;

-- ───────────── Mercado: reglas comunes ─────────────
create or replace function exigir_mercado_abierto(p_liga uuid) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not mercado_abierto(p_liga) then
    raise exception 'El mercado está cerrado (desde % h antes de un partido hasta que se calculan sus puntos)',
      (select horas_cierre_alineacion from ligas where id = p_liga);
  end if;
  if exists (select 1 from drafts where liga_id = p_liga and estado = 'en_curso') then
    raise exception 'El draft está en marcha: el mercado abre cuando termine';
  end if;
end $$;

create or replace function validar_hueco(p_liga uuid, p_manager uuid, p_jugador uuid) returns void
language plpgsql stable security definer set search_path = public as $$
declare l ligas; v_n int;
begin
  select * into l from ligas where id = p_liga;
  if not l.auto_fichaje and p_manager = p_jugador then
    raise exception 'En esta liga no puedes ficharte a ti mismo';
  end if;
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

-- Al fichar, la cláusula es el % de la liga sobre lo pagado (nunca menos que el valor de mercado)
create or replace function transferir_ficha(p_ficha uuid, p_nuevo uuid, p_importe numeric) returns void
language plpgsql security definer set search_path = public as $$
declare f fichas; l ligas;
begin
  select * into f from fichas where id = p_ficha;
  select * into l from ligas where id = f.liga_id;
  perform soltar_ficha(p_ficha);
  update fichas
     set propietario_id = p_nuevo, precio_compra = p_importe,
         clausula = greatest(round(p_importe * l.clausula_pct, 2), precio_actual(f.jugador_id)),
         adquirida_en = now(),
         protegida_hasta = case when l.proteccion_dias > 0 then now() + make_interval(days => l.proteccion_dias) end,
         protegida_jornadas = case when l.proteccion_dias > 0 then 1 else 0 end
   where id = p_ficha;
end $$;

drop function if exists comprar_ficha(uuid, uuid);
create or replace function comprar_ficha(p_liga uuid, p_jugador uuid, p_numero int default null) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_m uuid; l ligas; v_f uuid; v_precio numeric; v_saldo numeric;
begin
  v_m := mi_miembro(p_liga);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  select * into l from ligas where id = p_liga;
  perform exigir_mercado_abierto(p_liga);
  if l.modo_inicio = 'subasta' then
    raise exception 'En esta liga los jugadores libres salen en subasta: puja en la pestaña Mercado';
  end if;
  if l.modo_inicio = 'draft' and not exists (select 1 from drafts where liga_id = p_liga and estado = 'terminado') then
    raise exception 'Primero se hace el draft: el administrador lo inicia en Ajustes Fantasy';
  end if;
  perform asegurar_manager(p_liga, v_m);
  if p_jugador not in (select jugadores_liga(p_liga))
     or not exists (select 1 from mercado_jugador where liga_id = p_liga and miembro_id = p_jugador) then
    raise exception 'Ese jugador no está en el mercado';
  end if;
  perform validar_hueco(p_liga, v_m, p_jugador);
  v_f := ficha_libre(p_liga, p_jugador, p_numero);
  if v_f is null then
    raise exception 'No quedan copias libres de este jugador: puedes pagar la cláusula de un dueño o hacerle una oferta';
  end if;
  perform 1 from fichas where id = v_f for update;
  v_precio := precio_ficha(v_f);
  v_saldo := mover_saldo(p_liga, v_m, -v_precio, 'compra', p_jugador);
  perform transferir_ficha(v_f, v_m, v_precio);
  return v_saldo;
end $$;
revoke execute on function comprar_ficha(uuid, uuid, int) from public, anon;
grant execute on function comprar_ficha(uuid, uuid, int) to authenticated;

-- Vender cobra el valor de la copia (con su rareza) menos la comisión
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
  v_cobro := round(precio_actual(f.jugador_id) * factor_precio_copia(l.modo_copias, f.numero) * (1 - l.comision_venta), 2);
  perform soltar_ficha(p_ficha);
  update fichas set propietario_id = null, clausula = null, precio_compra = null, adquirida_en = null,
                    protegida_jornadas = 0
   where id = p_ficha;
  return mover_saldo(f.liga_id, v_m, v_cobro, 'venta', f.jugador_id);
end $$;

-- ───────────── Mánagers y reparto ─────────────
create or replace function asegurar_manager(p_liga uuid, p_miembro uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_presu numeric; l ligas;
begin
  if exists (select 1 from fantasy_managers where liga_id = p_liga and miembro_id = p_miembro) then return; end if;
  select * into l from ligas where id = p_liga;
  if l.presupuesto_inicial is null then
    raise exception 'El mercado aún no está abierto: falta cerrar la encuesta inicial';
  end if;
  if not l.fantasy_activo then raise exception 'El Fantasy está desactivado en esta liga'; end if;
  v_presu := presupuesto_liga(p_liga);
  update ligas set presupuesto_inicial = v_presu where id = p_liga and presupuesto_inicial is distinct from v_presu;
  insert into fantasy_managers (liga_id, miembro_id, saldo) values (p_liga, p_miembro, v_presu)
  on conflict do nothing;
  if found then
    insert into transacciones_fantasy (liga_id, manager_id, tipo, importe, saldo_despues)
    values (p_liga, p_miembro, 'presupuesto_inicial', v_presu, v_presu);
    perform asegurar_fichas(p_liga);
    if l.modo_inicio = 'reparto' then perform repartir_equipo(p_liga, p_miembro); end if;
  end if;
end $$;

-- Reparto equilibrado: alineación completa al azar, de valor parecido para todos, pagado del presupuesto.
create or replace function repartir_equipo(p_liga uuid, p_manager uuid) returns int
language plpgsql security definer set search_path = public as $$
declare l ligas; v_r int; v_obj numeric; v_cand uuid[]; v_fic uuid[]; v_precio numeric[]; v_inv boolean[]; v_n int;
        v_mejor int[]; v_mejor_dif numeric := null; v_sel int[]; v_suma numeric; v_ninv int; i int; t int;
        k int := 0; v_ya int; v_saldo numeric; v_total numeric := 0;
begin
  select * into l from ligas where id = p_liga;
  select count(*) into v_ya from fichas where liga_id = p_liga and propietario_id = p_manager;
  v_r := least(l.jugadores_por_equipo, l.max_plantilla) - v_ya;   -- alineación completa
  if v_r <= 0 then return 0; end if;
  select saldo into v_saldo from fantasy_managers where liga_id = p_liga and miembro_id = p_manager;

  select array_agg(jugador), array_agg(ficha), array_agg(precio), array_agg(no_habitual)
    into v_cand, v_fic, v_precio, v_inv
    from (select mj.miembro_id jugador, ficha_libre(p_liga, mj.miembro_id) ficha,
                 precio_ficha(ficha_libre(p_liga, mj.miembro_id)) precio, mj.no_habitual
            from mercado_jugador mj
           where mj.liga_id = p_liga and mj.miembro_id in (select jugadores_liga(p_liga))
             and ficha_libre(p_liga, mj.miembro_id) is not null
             and (l.auto_fichaje or mj.miembro_id <> p_manager)
             and not exists (select 1 from fichas f where f.propietario_id = p_manager and f.jugador_id = mj.miembro_id)
           order by random()) x;
  v_n := coalesce(array_length(v_cand, 1), 0);
  if v_n = 0 then return 0; end if;
  v_r := least(v_r, v_n);
  -- objetivo: el valor medio × huecos, sin pasar del presupuesto (deja un 4 % de margen)
  select avg(p) * v_r into v_obj from unnest(v_precio) p;
  v_obj := least(v_obj, v_saldo * 0.96);

  for t in 1..400 loop
    select array_agg(x) into v_sel from (select x from generate_series(1, v_n) x order by random() limit v_r) s;
    v_suma := 0; v_ninv := 0;
    foreach i in array v_sel loop
      v_suma := v_suma + v_precio[i];
      if v_inv[i] then v_ninv := v_ninv + 1; end if;
    end loop;
    continue when v_ninv > 1 or v_suma > v_saldo;
    if v_mejor_dif is null or abs(v_suma - v_obj) < v_mejor_dif then
      v_mejor_dif := abs(v_suma - v_obj);
      v_mejor := v_sel;
      exit when v_mejor_dif < l.valor_base * 0.02;
    end if;
  end loop;
  if v_mejor is null then return 0; end if;

  foreach i in array v_mejor loop
    perform transferir_ficha(v_fic[i], p_manager, v_precio[i]);
    v_total := v_total + v_precio[i];
    k := k + 1;
  end loop;
  if v_total > 0 then perform mover_saldo(p_liga, p_manager, -v_total, 'reparto_inicial'); end if;
  return k;
end $$;

-- ───────────── Subastas ─────────────
-- Saca a subasta un lote de copias libres (una por jugador). p_forzar: aunque hoy ya haya salido el lote.
create or replace function crear_subastas(p_liga uuid, p_forzar boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare l ligas; r record; k int := 0;
begin
  select * into l from ligas where id = p_liga for update;
  if not l.fantasy_activo or l.presupuesto_inicial is null then return 0; end if;
  if not p_forzar and (l.modo_inicio <> 'subasta' or exists (
       select 1 from subastas where liga_id = p_liga
          and (abre_en at time zone 'Europe/Madrid')::date = (now() at time zone 'Europe/Madrid')::date)) then
    return 0;
  end if;
  perform asegurar_fichas(p_liga);
  for r in select x.id, x.jugador_id from (
             select distinct on (f.jugador_id) f.id, f.jugador_id
               from fichas f
              where f.liga_id = p_liga and f.propietario_id is null
                and f.jugador_id in (select jugadores_liga(p_liga))
                and not exists (select 1 from subastas s where s.liga_id = p_liga and s.jugador_id = f.jugador_id
                                                          and s.estado = 'abierta')
              order by f.jugador_id, f.numero desc) x
            order by random() limit l.subasta_lote loop
    insert into subastas (liga_id, ficha_id, jugador_id, tipo, precio_salida, cierra_en)
    values (p_liga, r.id, r.jugador_id, l.subasta_tipo,
            coalesce(l.subasta_puja_min, precio_ficha(r.id)), now() + make_interval(hours => l.subasta_horas));
    k := k + 1;
  end loop;
  if k > 0 and coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
    perform notificar((select coalesce(array_agg(m.perfil_id), '{}') from fantasy_managers fm
                         join miembros m on m.id = fm.miembro_id where fm.liga_id = p_liga and m.perfil_id is not null),
                      p_liga, 'subasta', '🔨 Nueva subasta',
                      case when k = 1 then 'Sale un jugador a subasta. ¡Puja antes de que cierre!'
                           else k || ' jugadores salen a subasta. ¡Puja antes de que cierren!' end,
                      '/fantasy');
  end if;
  return k;
end $$;
revoke execute on function crear_subastas(uuid, boolean) from public, anon, authenticated;

create or replace function lanzar_subasta(p_liga uuid) returns int
language plpgsql security definer set search_path = public as $$
begin
  perform exigir_admin(p_liga);
  return crear_subastas(p_liga, true);
end $$;

-- Pujar (o cambiar tu puja). Abierta: hay que superar la mejor; si queda menos de 2 min, se alarga 2 min.
create or replace function pujar(p_subasta uuid, p_importe numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s subastas; l ligas; v_m uuid; v_saldo numeric; v_mejor numeric; v_lider uuid; v_min numeric; v_imp numeric;
begin
  select * into s from subastas where id = p_subasta for update;
  if not found then raise exception 'Subasta no encontrada'; end if;
  if s.estado <> 'abierta' or now() >= s.cierra_en then raise exception 'La subasta ya está cerrada'; end if;
  select * into l from ligas where id = s.liga_id;
  v_m := mi_miembro(s.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  perform asegurar_manager(s.liga_id, v_m);
  perform validar_hueco(s.liga_id, v_m, s.jugador_id);
  v_imp := round(p_importe, 2);
  if v_imp < s.precio_salida then raise exception 'La puja mínima es % M', s.precio_salida; end if;
  select saldo into v_saldo from fantasy_managers where liga_id = s.liga_id and miembro_id = v_m;
  if v_imp > v_saldo then raise exception 'No tienes saldo suficiente: tienes % M', v_saldo; end if;

  if s.tipo = 'abierta' then
    select importe, manager_id into v_mejor, v_lider from pujas where subasta_id = p_subasta
     order by importe desc, creada_en limit 1;
    if v_lider = v_m then raise exception 'Ya vas ganando esta subasta'; end if;
    v_min := coalesce(v_mejor + greatest(0.5, round(v_mejor * 0.02, 2)), s.precio_salida);
    if v_imp < v_min then raise exception 'Tienes que pujar al menos % M', v_min; end if;
    if s.cierra_en - now() < interval '2 minutes' then
      update subastas set cierra_en = now() + interval '2 minutes' where id = p_subasta;
    end if;
    if v_lider is not null and coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
      perform notificar(array[(select perfil_id from miembros where id = v_lider)], s.liga_id, 'subasta',
                        '🔨 Te han superado', 'Han pujado ' || v_imp || ' M por ' || nombre_miembro(s.jugador_id), '/fantasy');
    end if;
  end if;

  insert into pujas (subasta_id, manager_id, importe) values (p_subasta, v_m, v_imp)
  on conflict (subasta_id, manager_id) do update set importe = excluded.importe, creada_en = now();
  return jsonb_build_object('importe', v_imp, 'cierra_en', (select cierra_en from subastas where id = p_subasta));
end $$;

create or replace function retirar_puja(p_subasta uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s subastas;
begin
  select * into s from subastas where id = p_subasta;
  if not found or s.estado <> 'abierta' then raise exception 'La subasta ya está cerrada'; end if;
  if s.tipo = 'abierta' then raise exception 'En la subasta abierta las pujas no se retiran'; end if;
  delete from pujas where subasta_id = p_subasta and manager_id = mi_miembro(s.liga_id);
end $$;

-- Adjudica las subastas vencidas: gana la puja más alta que se pueda pagar (empate: la primera).
create or replace function resolver_subastas(p_liga uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare s record; b record; k int := 0; v_ok boolean;
begin
  for s in select * from subastas where estado = 'abierta' and cierra_en <= now()
              and (p_liga is null or liga_id = p_liga) order by cierra_en for update skip locked loop
    v_ok := false;
    for b in select * from pujas where subasta_id = s.id order by importe desc, creada_en loop
      begin
        if (select propietario_id from fichas where id = s.ficha_id) is not null then exit; end if;
        perform validar_hueco(s.liga_id, b.manager_id, s.jugador_id);
        perform mover_saldo(s.liga_id, b.manager_id, -b.importe, 'subasta', s.jugador_id);
        perform transferir_ficha(s.ficha_id, b.manager_id, b.importe);
        update subastas set estado = 'adjudicada', ganador_id = b.manager_id, importe = b.importe, resuelta_en = now()
         where id = s.id;
        v_ok := true;
        if coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
          perform notificar(array[(select perfil_id from miembros where id = b.manager_id)], s.liga_id, 'subasta',
                            '🔨 ¡Subasta ganada!', nombre_miembro(s.jugador_id) || ' es tuyo por ' || b.importe || ' M',
                            '/fantasy');
        end if;
        exit;
      exception when others then
        null;   -- esa puja no se puede pagar (saldo, plantilla llena…): pasa a la siguiente
      end;
    end loop;
    if not v_ok then
      update subastas set estado = 'desierta', resuelta_en = now() where id = s.id;
    end if;
    k := k + 1;
  end loop;
  return k;
end $$;
revoke execute on function resolver_subastas(uuid) from public, anon, authenticated;

-- Tarea programada: resuelve las vencidas y saca el lote del día a partir de la hora de la liga
create or replace function subastas_programadas() returns int
language plpgsql security definer set search_path = public as $$
declare l record; k int;
begin
  k := resolver_subastas();
  for l in select id from ligas where fantasy_activo and modo_inicio = 'subasta' and presupuesto_inicial is not null
             and (now() at time zone 'Europe/Madrid')::time >= subasta_hora loop
    k := k + crear_subastas(l.id);
  end loop;
  return k;
end $$;
revoke execute on function subastas_programadas() from public, anon, authenticated;

-- Lista para la app: en las ciegas no se ve la mejor puja hasta que cierra
create or replace function subastas_liga(p_liga uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_m uuid;
begin
  if not es_miembro(p_liga) then raise exception 'No perteneces a esta liga'; end if;
  perform resolver_subastas(p_liga);
  v_m := mi_miembro(p_liga);
  return coalesce((select jsonb_agg(x order by x.abierta desc, x.cierra_en desc) from (
    select s.id, s.jugador_id, f.numero, s.tipo, s.precio_salida, s.abre_en, s.cierra_en, s.estado,
           s.estado = 'abierta' as abierta, s.ganador_id, s.importe,
           (select count(*) from pujas p where p.subasta_id = s.id) as num_pujas,
           case when s.tipo = 'abierta' or s.estado <> 'abierta'
                then (select max(importe) from pujas p where p.subasta_id = s.id) end as mejor,
           case when s.tipo = 'abierta'
                then (select p.manager_id = v_m from pujas p where p.subasta_id = s.id order by importe desc, creada_en limit 1) end
             as voy_ganando,
           (select importe from pujas p where p.subasta_id = s.id and p.manager_id = v_m) as mi_puja
      from subastas s join fichas f on f.id = s.ficha_id
     where s.liga_id = p_liga and (s.estado = 'abierta' or s.resuelta_en > now() - interval '3 days')) x), '[]');
end $$;

revoke execute on function lanzar_subasta(uuid), pujar(uuid, numeric), retirar_puja(uuid), subastas_liga(uuid)
  from public, anon;
grant execute on function lanzar_subasta(uuid), pujar(uuid, numeric), retirar_puja(uuid), subastas_liga(uuid)
  to authenticated;

-- ───────────── Draft ─────────────
create or replace function turno_draft(p_liga uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select case when (d.pick / n) % 2 = 0 then d.orden[d.pick % n + 1] else d.orden[n - d.pick % n] end
    from drafts d cross join lateral (select array_length(d.orden, 1) n) x
   where d.liga_id = p_liga and d.estado = 'en_curso'
$$;

create or replace function _avanzar_draft(p_liga uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d drafts; v_sig uuid;
begin
  update drafts set pick = pick + 1, turno_desde = now() where liga_id = p_liga returning * into d;
  if d.pick >= array_length(d.orden, 1) * d.rondas then
    update drafts set estado = 'terminado' where liga_id = p_liga;
    perform notificar((select coalesce(array_agg(m.perfil_id), '{}') from miembros m where m.id = any(d.orden)),
                      p_liga, 'draft', '✅ Draft terminado', 'Ya puedes fichar en el mercado y hacer tu alineación', '/fantasy');
  else
    v_sig := turno_draft(p_liga);
    perform notificar(array[(select perfil_id from miembros where id = v_sig)], p_liga, 'draft',
                      '⏱️ Te toca en el draft', 'Elige tu jugador', '/fantasy');
  end if;
end $$;
revoke execute on function _avanzar_draft(uuid) from public, anon, authenticated;

-- El admin inicia el draft: orden al azar, en serpiente (1-2-3, 3-2-1…). Rondas: alineación + 1 reserva.
create or replace function iniciar_draft(p_liga uuid, p_rondas int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l ligas; v_orden uuid[]; v_r int;
begin
  perform exigir_admin(p_liga);
  select * into l from ligas where id = p_liga for update;
  if l.modo_inicio <> 'draft' then raise exception 'La liga no está en modo draft'; end if;
  if exists (select 1 from drafts where liga_id = p_liga) then raise exception 'El draft ya se hizo'; end if;
  if l.presupuesto_inicial is null then
    perform igualar_precios(p_liga);
    update ligas set presupuesto_inicial = presupuesto_liga(p_liga) where id = p_liga;
  end if;
  perform crear_managers(p_liga);
  select array_agg(miembro_id order by random()) into v_orden from fantasy_managers where liga_id = p_liga;
  if coalesce(array_length(v_orden, 1), 0) < 2 then raise exception 'Hacen falta al menos 2 mánagers'; end if;
  v_r := least(coalesce(p_rondas, l.jugadores_por_equipo + 1), l.max_plantilla);
  insert into drafts (liga_id, orden, rondas) values (p_liga, v_orden, v_r);
  perform notificar((select coalesce(array_agg(m.perfil_id), '{}') from miembros m where m.id = any(v_orden)),
                    p_liga, 'draft', '🎲 ¡Empieza el draft!',
                    'Elige por turnos: ' || v_r || ' rondas. Primero: ' || nombre_miembro(v_orden[1]), '/fantasy');
  return estado_draft(p_liga);
end $$;

create or replace function draft_elegir(p_liga uuid, p_jugador uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d drafts; v_m uuid; v_f uuid; v_precio numeric;
begin
  select * into d from drafts where liga_id = p_liga for update;
  if not found or d.estado <> 'en_curso' then raise exception 'No hay ningún draft en marcha'; end if;
  v_m := mi_miembro(p_liga);
  if turno_draft(p_liga) is distinct from v_m then raise exception 'No es tu turno'; end if;
  perform validar_hueco(p_liga, v_m, p_jugador);
  v_f := ficha_libre(p_liga, p_jugador);
  if v_f is null then raise exception 'No quedan copias libres de ese jugador'; end if;
  v_precio := precio_ficha(v_f);
  perform mover_saldo(p_liga, v_m, -v_precio, 'draft', p_jugador);
  perform transferir_ficha(v_f, v_m, v_precio);
  insert into draft_picks (liga_id, pick, manager_id, jugador_id, importe) values (p_liga, d.pick, v_m, p_jugador, v_precio);
  perform _avanzar_draft(p_liga);
  return estado_draft(p_liga);
end $$;

-- Pasar el turno: el propio mánager, o el admin si alguien no contesta
create or replace function draft_pasar(p_liga uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d drafts; v_turno uuid;
begin
  select * into d from drafts where liga_id = p_liga for update;
  if not found or d.estado <> 'en_curso' then raise exception 'No hay ningún draft en marcha'; end if;
  v_turno := turno_draft(p_liga);
  if v_turno is distinct from mi_miembro(p_liga) and not es_admin(p_liga) then raise exception 'No es tu turno'; end if;
  insert into draft_picks (liga_id, pick, manager_id) values (p_liga, d.pick, v_turno);
  perform _avanzar_draft(p_liga);
  return estado_draft(p_liga);
end $$;

create or replace function estado_draft(p_liga uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when d.liga_id is null then null else jsonb_build_object(
    'estado', d.estado, 'orden', to_jsonb(d.orden), 'rondas', d.rondas, 'pick', d.pick,
    'total', array_length(d.orden, 1) * d.rondas, 'ronda', d.pick / array_length(d.orden, 1) + 1,
    'turno', turno_draft(p_liga), 'turno_desde', d.turno_desde,
    'picks', coalesce((select jsonb_agg(jsonb_build_object('pick', p.pick, 'manager_id', p.manager_id,
                                                           'jugador_id', p.jugador_id, 'importe', p.importe) order by p.pick)
                         from draft_picks p where p.liga_id = p_liga), '[]')) end
    from (select 1) x left join drafts d on d.liga_id = p_liga
   where es_miembro(p_liga)
$$;

revoke execute on function iniciar_draft(uuid, int), draft_elegir(uuid, uuid), draft_pasar(uuid), estado_draft(uuid),
                           turno_draft(uuid) from public, anon;
grant execute on function iniciar_draft(uuid, int), draft_elegir(uuid, uuid), draft_pasar(uuid), estado_draft(uuid),
                          turno_draft(uuid) to authenticated;

-- ───────────── Alineación: capitán, ariete y suplentes ─────────────
drop function if exists guardar_alineacion(uuid, uuid[], text[]);
create or replace function guardar_alineacion(p_partido uuid, p_jugadores uuid[], p_roles text[] default null,
                                              p_capitan uuid default null, p_ariete uuid default null,
                                              p_suplentes uuid[] default null)
returns int language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_m uuid; v_tam int; v_n int; v_roles text[]; v_sup uuid[]; v_todos uuid[];
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  select * into l from ligas where id = p.liga_id;
  v_m := mi_miembro(p.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') or p.alineaciones_congeladas
     or now() >= hora_cierre_alineacion(p_partido) then
    raise exception 'La alineación de este partido ya está cerrada (cierra % h antes del partido)', l.horas_cierre_alineacion;
  end if;
  perform asegurar_manager(p.liga_id, v_m);

  v_tam := p.plazas / p.num_equipos;
  v_n := coalesce(array_length(p_jugadores, 1), 0);
  v_sup := coalesce(p_suplentes, '{}');
  if v_n > v_tam then
    raise exception 'La alineación es de media plantilla del partido: como máximo % jugadores', v_tam;
  end if;
  if coalesce(array_length(v_sup, 1), 0) > l.suplentes then
    raise exception 'Como máximo % suplentes', l.suplentes;
  end if;
  v_todos := coalesce(p_jugadores, '{}') || v_sup;
  if (select count(distinct x) from unnest(v_todos) x) <> coalesce(array_length(v_todos, 1), 0) then
    raise exception 'Hay jugadores repetidos en la alineación';
  end if;
  if exists (select 1 from unnest(v_todos) x
               join fichas f on f.jugador_id = x and f.propietario_id = v_m
               join cesiones c on c.ficha_id = f.id and c.estado = 'aceptada') then
    raise exception 'Ese jugador está cedido esta jornada: no puedes alinearlo';
  end if;
  if exists (select 1 from unnest(v_todos) x
              where not exists (select 1 from fichas f where f.propietario_id = v_m and f.jugador_id = x)
                and not exists (select 1 from cesiones c join fichas f on f.id = c.ficha_id
                                 where c.cesionario_id = v_m and c.partido_id = p_partido
                                   and c.estado = 'aceptada' and f.jugador_id = x)) then
    raise exception 'Solo puedes alinear jugadores de tu plantilla (o el que tengas cedido esta jornada)';
  end if;

  if p_roles is null then
    v_roles := array(select case when k = 1 and l.modo_alineacion = 'tactico' then 'POR' else 'MED' end
                       from generate_series(1, v_n) k);
  else
    if coalesce(array_length(p_roles, 1), 0) <> v_n then
      raise exception 'Hay que indicar un rol por jugador (POR, DEF, MED o DEL)';
    end if;
    v_roles := array(select upper(trim(r)) from unnest(p_roles) r);
    if exists (select 1 from unnest(v_roles) r where r is null or r not in ('POR', 'DEF', 'MED', 'DEL')) then
      raise exception 'Rol no válido: usa POR, DEF, MED o DEL';
    end if;
  end if;
  if l.modo_alineacion = 'tactico' and v_n >= 1 then
    if (select count(*) from unnest(v_roles) r where r = 'POR') <> 1 then
      raise exception 'La alineación lleva exactamente un portero (POR)';
    end if;
    if v_n >= 4 and (not 'DEF' = any(v_roles) or not 'DEL' = any(v_roles)) then
      raise exception 'Con 4 o más jugadores, la alineación táctica lleva al menos un defensa y un delantero';
    end if;
  end if;

  if p_capitan is not null and (not l.capitan_activo or not p_capitan = any(p_jugadores)) then
    raise exception 'El capitán tiene que ser uno de los titulares';
  end if;
  if p_ariete is not null and (not l.ariete_activo or not p_ariete = any(p_jugadores)) then
    raise exception 'El ariete tiene que ser uno de los titulares';
  end if;

  delete from alineaciones where partido_id = p_partido and manager_id = v_m;
  insert into alineaciones (partido_id, manager_id, jugador_id, rol, capitan, ariete)
  select p_partido, v_m, t.x, v_roles[t.k], t.x = p_capitan, t.x = p_ariete
    from unnest(p_jugadores) with ordinality as t(x, k);
  insert into alineaciones (partido_id, manager_id, jugador_id, rol, suplente)
  select p_partido, v_m, t.x, 'MED', t.k from unnest(v_sup) with ordinality as t(x, k);
  return v_n;
end $$;
revoke execute on function guardar_alineacion(uuid, uuid[], text[], uuid, uuid, uuid[]) from public, anon;
grant execute on function guardar_alineacion(uuid, uuid[], text[], uuid, uuid, uuid[]) to authenticated;

-- Congelar: si no alineó, se copia la anterior (titulares, suplentes, capitán y ariete) o sus mejores jugadores
create or replace function congelar_alineaciones(p_partido uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_tam int; fm record; v_prev uuid;
begin
  select * into p from partidos where id = p_partido for update;
  if p.alineaciones_congeladas or p.estado = 'cancelado' then return false; end if;
  if now() < hora_cierre_alineacion(p_partido) and p.estado not in ('jugado', 'post_partido', 'en_revision', 'cerrado') then
    return false;
  end if;
  select * into l from ligas where id = p.liga_id;
  v_tam := p.plazas / p.num_equipos;

  update cesiones set estado = 'cancelada' where partido_id = p_partido and estado = 'ofrecida';
  update ofertas set estado = 'caducada', resuelta_en = now() where liga_id = p.liga_id and estado = 'pendiente';

  for fm in select miembro_id from fantasy_managers where liga_id = p.liga_id loop
    if not exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id) then
      select a.partido_id into v_prev
        from alineaciones a join partidos pp on pp.id = a.partido_id
       where a.manager_id = fm.miembro_id and pp.liga_id = p.liga_id and pp.fecha_hora < p.fecha_hora
       order by pp.fecha_hora desc limit 1;
      if v_prev is not null then
        insert into alineaciones (partido_id, manager_id, jugador_id, rol, copiada, capitan, ariete, suplente)
        select p_partido, fm.miembro_id, a.jugador_id, a.rol, true, a.capitan, a.ariete, a.suplente
          from alineaciones a
          join fichas f on f.propietario_id = a.manager_id and f.jugador_id = a.jugador_id
         where a.partido_id = v_prev and a.manager_id = fm.miembro_id
           and not exists (select 1 from cesiones c where c.ficha_id = f.id and c.estado = 'aceptada')
         order by a.suplente nulls first, (a.rol = 'POR') desc, a.jugador_id
         limit v_tam + l.suplentes;
        -- no más titulares de la cuenta (si el partido es más pequeño)
        delete from alineaciones a where a.partido_id = p_partido and a.manager_id = fm.miembro_id and a.suplente is null
           and a.jugador_id not in (select x.jugador_id from alineaciones x where x.partido_id = p_partido
                                      and x.manager_id = fm.miembro_id and x.suplente is null
                                    order by (x.rol = 'POR') desc, x.jugador_id limit v_tam);
      end if;
      insert into alineaciones (partido_id, manager_id, jugador_id, rol, copiada)
      select p_partido, fm.miembro_id, x.jugador_id, 'MED', true
        from (select distinct on (f.jugador_id) f.jugador_id, coalesce(mj.precio, 0) precio
                from fichas f
                left join mercado_jugador mj on mj.liga_id = p.liga_id and mj.miembro_id = f.jugador_id
               where f.liga_id = p.liga_id and f.propietario_id = fm.miembro_id
                 and not exists (select 1 from cesiones c where c.ficha_id = f.id and c.estado = 'aceptada')
                 and not exists (select 1 from alineaciones a2 where a2.partido_id = p_partido
                                    and a2.manager_id = fm.miembro_id and a2.jugador_id = f.jugador_id)
               order by f.jugador_id) x
       order by x.precio desc, x.jugador_id
       limit greatest(0, v_tam - (select count(*) from alineaciones
                                   where partido_id = p_partido and manager_id = fm.miembro_id and suplente is null));
      if l.modo_alineacion = 'tactico'
         and exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id and suplente is null)
         and not exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id
                                                       and rol = 'POR' and suplente is null) then
        update alineaciones set rol = 'POR'
         where partido_id = p_partido and manager_id = fm.miembro_id
           and jugador_id = (select a3.jugador_id from alineaciones a3
                              left join miembros mm on mm.id = a3.jugador_id
                              left join perfiles pf on pf.id = mm.perfil_id
                              where a3.partido_id = p_partido and a3.manager_id = fm.miembro_id and a3.suplente is null
                              order by (coalesce(mm.posicion, pf.posicion)::text = 'portero') desc nulls last,
                                       a3.jugador_id limit 1);
      end if;
    end if;
  end loop;

  update alineaciones a
     set no_habitual = coalesce(mj.no_habitual, false),
         multiplicador = case when coalesce(mj.no_habitual, false) then l.bonus_no_habitual else 1 end
    from mercado_jugador mj
   where a.partido_id = p_partido and mj.liga_id = p.liga_id and mj.miembro_id = a.jugador_id;
  update alineaciones set no_habitual = false, multiplicador = 1
   where partido_id = p_partido and multiplicador is null;

  update partidos set alineaciones_congeladas = true where id = p_partido;
  return true;
end $$;

-- Número de la copia con la que el mánager alinea a ese jugador (la suya o la cedida)
create or replace function numero_copia(p_partido uuid, p_manager uuid, p_jugador uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select f.numero from fichas f where f.propietario_id = p_manager and f.jugador_id = p_jugador limit 1),
    (select f.numero from cesiones c join fichas f on f.id = c.ficha_id
      where c.partido_id = p_partido and c.cesionario_id = p_manager and f.jugador_id = p_jugador limit 1), 99)
$$;

-- ───────────── Liquidación de la jornada ─────────────
create or replace function liquidar_jornada(p_partido uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; fm record; t record; s record; v_pts numeric; v_des jsonb; v_m int; v_prima numeric;
        v_ing numeric; v_doble numeric;
begin
  select * into p from partidos where id = p_partido for update;
  if not found then raise exception 'Partido no encontrado'; end if;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado <> 'cerrado' then raise exception 'El partido aún no tiene los puntos calculados'; end if;
  if p.jornada_liquidada then return false; end if;
  select * into l from ligas where id = p.liga_id;
  v_doble := case when p.evento_especial = 'doble_puntos' then 2 else 1 end;

  perform congelar_alineaciones(p_partido);

  -- Suplentes: entran por los titulares que no jugaron, en su orden y con el rol del titular
  for fm in select miembro_id from fantasy_managers where liga_id = p.liga_id loop
    for t in select a.* from alineaciones a
              where a.partido_id = p_partido and a.manager_id = fm.miembro_id and a.suplente is null
                and not exists (select 1 from puntos_fantasy pf where pf.partido_id = p_partido and pf.miembro_id = a.jugador_id)
              order by (a.rol = 'POR') desc, a.jugador_id loop
      select a.* into s from alineaciones a
       where a.partido_id = p_partido and a.manager_id = fm.miembro_id and a.suplente is not null and a.entra_por is null
         and exists (select 1 from puntos_fantasy pf where pf.partido_id = p_partido and pf.miembro_id = a.jugador_id)
       order by a.suplente limit 1;
      exit when not found;
      update alineaciones set entra_por = t.jugador_id, rol = t.rol
       where partido_id = p_partido and manager_id = fm.miembro_id and jugador_id = s.jugador_id;
      update alineaciones set sustituido = true
       where partido_id = p_partido and manager_id = fm.miembro_id and jugador_id = t.jugador_id;
    end loop;
  end loop;

  update alineaciones a
     set bonus_rol = case when exists (select 1 from puntos_fantasy pf
                                         where pf.partido_id = a.partido_id and pf.miembro_id = a.jugador_id)
                          then bonus_rol(a.partido_id, a.jugador_id, a.rol) else 0 end
   where a.partido_id = p_partido;

  create temp table if not exists tmp_pm (manager_id uuid primary key, pts numeric, des jsonb) on commit drop;
  delete from tmp_pm where true;
  for fm in select * from fantasy_managers where liga_id = p.liga_id loop
    with c as (
      select a.*, coalesce(pf.total, 0) puntos, pf.miembro_id is not null jugo,
             coalesce(aj.goles, 0) goles,
             factor_puntos_copia(l.modo_copias, numero_copia(p_partido, fm.miembro_id, a.jugador_id)) rareza
        from alineaciones a
        left join puntos_fantasy pf on pf.partido_id = a.partido_id and pf.miembro_id = a.jugador_id
        left join acta_jugador aj on aj.partido_id = a.partido_id and aj.miembro_id = a.jugador_id
       where a.partido_id = p_partido and a.manager_id = fm.miembro_id),
    v as (
      select c.*, (c.suplente is null and not c.sustituido) or c.entra_por is not null as cuenta,
             round(((c.puntos + coalesce(c.bonus_rol, 0)) * c.multiplicador * c.rareza
                    * case when c.capitan and l.capitan_activo then 2 else 1 end
                    + case when c.ariete and l.ariete_activo and c.goles > 0 then regla_def(l.id, 'ariete', 3) else 0 end)
                   * v_doble, 2) as total
        from c)
    select coalesce(sum(total) filter (where cuenta), 0),
           coalesce(jsonb_agg(jsonb_build_object(
             'jugador_id', jugador_id, 'rol', rol, 'puntos', puntos, 'bonus_rol', coalesce(bonus_rol, 0),
             'multiplicador', multiplicador, 'rareza', rareza, 'capitan', capitan, 'ariete', ariete and goles > 0,
             'suplente', suplente, 'entra_por', entra_por, 'sustituido', sustituido, 'cuenta', cuenta,
             'jugo', jugo, 'doble', v_doble > 1,
             'cedido', exists (select 1 from cesiones ce join fichas f on f.id = ce.ficha_id
                                where ce.partido_id = p_partido and ce.cesionario_id = fm.miembro_id
                                  and ce.estado = 'aceptada' and f.jugador_id = v.jugador_id),
             'total', case when cuenta then total else 0 end)
             order by suplente nulls first, (rol = 'POR') desc, rol, jugador_id), '[]'::jsonb)
      into v_pts, v_des
      from v;
    insert into tmp_pm values (fm.miembro_id, v_pts, v_des);
  end loop;

  select count(*) into v_m from tmp_pm;
  for t in select x.*, rank() over (order by x.pts desc) rk from tmp_pm x loop
    v_prima := case when l.prima_inversa > 0 and v_m > 1 then round(l.prima_inversa * (t.rk - 1)::numeric / (v_m - 1), 2) else 0 end;
    v_ing := round(greatest(t.pts, 0) * l.ingreso_por_punto, 2) + v_prima;
    insert into puntos_manager (partido_id, manager_id, puntos, ingreso, prima, desglose)
    values (p_partido, t.manager_id, t.pts, v_ing, v_prima, t.des);
    update fantasy_managers set puntos_totales = puntos_totales + t.pts, saldo = saldo + v_ing
     where liga_id = p.liga_id and miembro_id = t.manager_id;
    if v_ing > 0 then
      insert into transacciones_fantasy (liga_id, manager_id, partido_id, tipo, importe, saldo_despues)
      values (p.liga_id, t.manager_id, p_partido, 'ingreso_puntos', v_ing,
              (select saldo from fantasy_managers where liga_id = p.liga_id and miembro_id = t.manager_id));
    end if;
  end loop;

  update cesiones set estado = 'finalizada' where partido_id = p_partido and estado = 'aceptada';
  update cesiones set estado = 'cancelada'  where partido_id = p_partido and estado = 'ofrecida';
  update fichas set protegida_jornadas = protegida_jornadas - 1
   where liga_id = p.liga_id and protegida_jornadas > 0;
  perform caducar_ofertas(p.liga_id);

  update partidos set jornada_liquidada = true where id = p_partido;
  perform recalcular_precios(p.liga_id, p_partido);
  update fichas f set clausula = mj.precio
    from mercado_jugador mj
   where f.liga_id = p.liga_id and f.propietario_id is not null
     and mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id and f.clausula < mj.precio;
  perform asegurar_fichas(p.liga_id);
  return true;
end $$;

-- ───────────── Jornadas especiales ─────────────
create or replace function fijar_evento_especial(p_partido uuid, p_evento text) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos;
begin
  select * into p from partidos where id = p_partido for update;
  if not found then raise exception 'Partido no encontrado'; end if;
  perform exigir_admin(p.liga_id);
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') then
    raise exception 'Solo se puede marcar antes de jugar el partido';
  end if;
  if p_evento is not null and p_evento not in ('doble_puntos', 'goles_dobles') then
    raise exception 'Evento no válido';
  end if;
  update partidos set evento_especial = p_evento where id = p_partido;
  if p_evento is not null and coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
    perform notificar((select coalesce(array_agg(perfil_id), '{}') from miembros where liga_id = p.liga_id and estado = 'activo'),
                      p.liga_id, 'evento', case p_evento when 'doble_puntos' then '⚡ Jornada de puntos dobles'
                                                         else '⚽ Jornada de goles dobles' end,
                      case p_evento when 'doble_puntos' then 'Los puntos de los mánagers valen el doble en el próximo partido'
                                    else 'Cada gol vale el doble en el próximo partido' end,
                      '/partidos/' || p_partido);
  end if;
end $$;
revoke execute on function fijar_evento_especial(uuid, text) from public, anon;
grant execute on function fijar_evento_especial(uuid, text) to authenticated;

-- calcular_puntos (0025) con goles dobles
create or replace function calcular_puntos(p_partido uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; a record; v_v int; v_e int; v_d int; v_nota record; d jsonb; v_total numeric;
        v_dest jsonb; v_votos int; v_gol numeric;
begin
  select * into p from partidos where id = p_partido for update;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado not in ('post_partido', 'en_revision') then
    raise exception 'El partido no está pendiente de puntuar (estado: %)', p.estado;
  end if;
  if exists (select 1 from disputas where partido_id = p_partido and not resuelta) then
    raise exception 'Quedan datos en disputa por resolver';
  end if;
  if exists (select 1 from encuentros where partido_id = p_partido and goles_local is null) then
    raise exception 'El acta no está consolidada';
  end if;
  select * into l from ligas where id = p.liga_id;
  v_gol := regla(l.id, 'gol') * case when p.evento_especial = 'goles_dobles' then 2 else 1 end;

  delete from puntos_fantasy where partido_id = p_partido;

  for a in select aj.*, c.equipo from acta_jugador aj
             join convocatorias c on c.partido_id = aj.partido_id and c.miembro_id = aj.miembro_id
            where aj.partido_id = p_partido loop
    select count(*) filter (where gf > gc), count(*) filter (where gf = gc), count(*) filter (where gf < gc)
      into v_v, v_e, v_d
      from (select case when e.equipo_local = a.equipo then e.goles_local else e.goles_visitante end gf,
                   case when e.equipo_local = a.equipo then e.goles_visitante else e.goles_local end gc
              from encuentros e
             where e.partido_id = p_partido and a.equipo in (e.equipo_local, e.equipo_visitante)) t;

    v_nota := nota_partido(p_partido, a.miembro_id);

    d := jsonb_build_object(
      'jugado',            regla(l.id, 'jugado'),
      'resultado',         v_v * regla(l.id, 'victoria') + v_e * regla(l.id, 'empate'),
      'goles',             a.goles * v_gol,
      'asistencias',       a.asistencias * regla(l.id, 'asistencia'),
      'paradas',           floor(a.paradas_clave / 2.0) * regla(l.id, 'parada_clave_2'),
      'penaltis_parados',  a.penaltis_parados * regla(l.id, 'penalti_parado'),
      'penaltis_fallados', a.penaltis_fallados * regla(l.id, 'penalti_fallado'),
      'autogoles',         a.autogoles * regla(l.id, 'autogol'),
      'valoracion',        puntos_por_nota(v_nota.nota, regla(l.id, 'valoracion_max')),
      'mvp',               0);

    select sum(value::numeric) into v_total from jsonb_each_text(d);

    select coalesce(jsonb_object_agg(aspecto, n), '{}') into v_dest
      from (select aspecto, count(*) n from valoracion_destacados
             where partido_id = p_partido and votado_id = a.miembro_id group by aspecto) t;
    select count(*) into v_votos from votos_mvp where partido_id = p_partido and votado_id = a.miembro_id;
    if coalesce(v_nota.votantes, 0) < 3 then v_dest := '{}'; end if;
    d := d || jsonb_build_object('notas', v_nota.por_aspecto, 'destacados', v_dest, 'votos_mvp', v_votos);

    insert into puntos_fantasy (partido_id, miembro_id, posicion, victorias, empates, derrotas,
                                nota_media, num_votantes, es_mvp, desglose, total)
    values (p_partido, a.miembro_id, posicion_de(a.miembro_id), v_v, v_e, v_d, v_nota.nota, v_nota.votantes,
            false, d, v_total);
  end loop;

  perform decidir_mvp(p_partido);
  update partidos set estado = 'cerrado' where id = p_partido;
end $$;

-- ───────────── Temporadas: herencia del Fantasy ─────────────
drop function if exists cerrar_temporada(uuid, text);
create or replace function cerrar_temporada(p_liga uuid, p_nombre text default null, p_herencia text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_num int; v_desde timestamptz; v_hasta timestamptz; v_n int; v_min int; v_nombre text;
        v_her text; l ligas; rb record;
begin
  if not es_admin(p_liga) then raise exception 'Solo el administrador puede cerrar la temporada'; end if;
  select * into l from ligas where id = p_liga;
  v_her := coalesce(p_herencia, l.herencia_temporada);
  if v_her not in ('ninguna', 'reinicio', 'valor', 'bonus') then raise exception 'Herencia no válida'; end if;
  v_desde := coalesce(inicio_temporada(p_liga), '-infinity'::timestamptz);
  select count(*) into v_n from partidos where liga_id = p_liga and estado = 'cerrado' and fecha_hora >= v_desde;
  if v_n = 0 then raise exception 'Esta temporada aún no tiene partidos cerrados'; end if;
  if exists (select 1 from partidos where liga_id = p_liga and estado in ('jugado', 'post_partido', 'en_revision')
               and fecha_hora >= v_desde) then
    raise exception 'Hay partidos sin cerrar: ciérralos antes de cerrar la temporada';
  end if;
  select greatest(now(), max(fecha_hora) + interval '1 second') into v_hasta
    from partidos where liga_id = p_liga and estado = 'cerrado' and fecha_hora >= v_desde;
  select coalesce(max(numero), 0) + 1 into v_num from temporadas_cerradas where liga_id = p_liga;
  v_nombre := coalesce(nullif(trim(coalesce(p_nombre, '')), ''), 'Temporada ' || v_num);

  create temp table _r on commit drop as select * from rendimiento_periodo(p_liga, nullif(v_desde, '-infinity'), v_hasta);
  insert into temporadas_cerradas (liga_id, numero, nombre, desde, hasta, partidos, clasificacion)
  values (p_liga, v_num, v_nombre,
          coalesce((select min(fecha_hora) from partidos where liga_id = p_liga and estado = 'cerrado' and fecha_hora >= v_desde), now()),
          v_hasta, v_n,
          coalesce((select jsonb_agg(to_jsonb(r) order by r.puntos_total desc) from _r r), '[]'))
  returning id into v_id;

  select ceil(max(partidos) / 2.0) into v_min from _r;
  insert into premios (temporada_id, liga_id, miembro_id, tipo, valor)
  select v_id, p_liga, miembro_id, tipo, valor from (
    select miembro_id, 'campeon' tipo, puntos_total valor, rank() over (order by puntos_total desc) rk from _r
    union all select miembro_id, 'pichichi', goles, rank() over (order by goles desc) from _r where goles > 0
    union all select miembro_id, 'asistente', asistencias, rank() over (order by asistencias desc) from _r where asistencias > 0
    union all select miembro_id, 'mvp', mvps, rank() over (order by mvps desc) from _r where mvps > 0
    union all select miembro_id, 'fiel', partidos, rank() over (order by partidos desc) from _r
    union all select miembro_id, 'mejor_nota', nota_media, rank() over (order by nota_media desc) from _r
               where nota_media is not null and partidos >= v_min
    union all select miembro_id, 'ganador', pct_victorias, rank() over (order by pct_victorias desc) from _r
               where pct_victorias is not null and partidos >= v_min
  ) x where rk = 1;

  -- Fantasy: reinicio total (precios iguales), heredar valor de mercado, o heredar un bonus del 10 % del patrimonio
  if l.fantasy_activo and l.presupuesto_inicial is not null and v_her <> 'ninguna' then
    create temp table _bonus on commit drop as
      select fm.miembro_id, round(0.10 * (fm.saldo + coalesce((select sum(mj.precio) from fichas f
                                                                  join mercado_jugador mj on mj.liga_id = f.liga_id
                                                                                         and mj.miembro_id = f.jugador_id
                                                                 where f.liga_id = p_liga and f.propietario_id = fm.miembro_id), 0)), 2) bonus
        from fantasy_managers fm where fm.liga_id = p_liga;
    delete from subastas where liga_id = p_liga;
    delete from drafts where liga_id = p_liga;
    delete from draft_picks where liga_id = p_liga;
    perform reiniciar_fantasy(p_liga, v_her = 'reinicio');
    if v_her = 'bonus' then
      for rb in select * from _bonus where bonus > 0 loop
        if exists (select 1 from fantasy_managers where liga_id = p_liga and miembro_id = rb.miembro_id) then
          perform mover_saldo(p_liga, rb.miembro_id, rb.bonus, 'herencia_temporada');
        end if;
      end loop;
    end if;
  end if;

  perform notificar((select coalesce(array_agg(perfil_id), '{}') from miembros where liga_id = p_liga and estado = 'activo'),
                    p_liga, 'temporada', v_nombre || ' cerrada 🏆', 'Mira quién se ha llevado los premios', '/palmares');
  return v_id;
end $$;
revoke execute on function cerrar_temporada(uuid, text, text) from public, anon;
grant execute on function cerrar_temporada(uuid, text, text) to authenticated;

-- ───────────── Valor inicial según el historial importado (0053) ─────────────
-- Calidad inicial 35–65 según el percentil de puntos por partido estimados del historial.
create or replace function valorar_por_historial(p_liga uuid) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  perform exigir_admin(p_liga);
  with r as (
    select v.miembro_id, 35 + 30 * percent_rank() over (order by v.puntos_media) as rating
      from v_rendimiento v join historial_importado h on h.miembro_id = v.miembro_id
     where v.liga_id = p_liga and v.partidos > 0)
  update mercado_jugador mj set rating = round(r.rating::numeric, 1),
                                precio = redondear_005(precio_base(p_liga, r.rating)), actualizado_en = now()
    from r where mj.liga_id = p_liga and mj.miembro_id = r.miembro_id;
  get diagnostics k = row_count;
  insert into historial_precios (liga_id, miembro_id, precio, rating)
  select p_liga, mj.miembro_id, mj.precio, mj.rating from mercado_jugador mj
   where mj.liga_id = p_liga and mj.miembro_id in (select miembro_id from historial_importado where liga_id = p_liga);
  return k;
end $$;
revoke execute on function valorar_por_historial(uuid) from public, anon;
grant execute on function valorar_por_historial(uuid) to authenticated;

-- Copias recalculadas con la nueva regla en todas las ligas con mercado
select asegurar_fichas(l.id) from ligas l where exists (select 1 from mercado_jugador where liga_id = l.id);

-- El presupuesto que ven las ligas existentes es el de los nuevos mánagers
update ligas set presupuesto_inicial = presupuesto_liga(id) where presupuesto_inicial is not null;
-- En Supabase (cron): select cron.schedule('ff_subastas', '*/5 * * * *', 'select public.subastas_programadas()');

-- Copias libres de un jugador con su precio (rareza y escasez incluidas), la más barata primero
create or replace function copias_libres(p_liga uuid, p_jugador uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('ficha_id', f.id, 'numero', f.numero, 'precio', precio_ficha(f.id),
                                               'puntos', factor_puntos_copia(l.modo_copias, f.numero))
                            order by precio_ficha(f.id), f.numero desc), '[]')
    from fichas f join ligas l on l.id = f.liga_id
   where f.liga_id = p_liga and f.jugador_id = p_jugador and f.propietario_id is null and es_miembro(p_liga)
     and not exists (select 1 from subastas s where s.ficha_id = f.id and s.estado = 'abierta')
$$;
revoke execute on function copias_libres(uuid, uuid) from public, anon;
grant execute on function copias_libres(uuid, uuid) to authenticated;
