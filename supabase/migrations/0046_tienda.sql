-- 0046 · Tienda y códigos
--  · Los códigos promocionales pueden ser de dinero Fantasy (como hasta ahora) o «sin anuncios»
--    (X días o para siempre). Los crea la cuenta máster.
--  · ventajas: hasta cuándo un usuario no ve anuncios (no la puede escribir la app, solo las RPC).
--  · canjear(): un único canje para los dos tipos. canjear_codigo() se mantiene por compatibilidad.
--  · ligas.compras_dinero: el admin decide si en su liga se puede conseguir dinero Fantasy con códigos/compras.

alter table codigos_promo add column if not exists tipo text not null default 'dinero';
alter table codigos_promo add column if not exists dias int;
alter table codigos_promo alter column importe drop not null;
alter table codigos_promo drop constraint if exists codigos_promo_importe_check;
do $$ begin
  alter table codigos_promo add constraint codigos_promo_tipo_chk check (
    (tipo = 'dinero' and importe > 0 and importe <= 1000 and dias is null)
    or (tipo = 'sin_anuncios' and importe is null and (dias is null or dias between 1 and 3650)));
exception when duplicate_object then null; end $$;

alter table ligas add column if not exists compras_dinero boolean not null default true;

create table if not exists ventajas (
  perfil_id          uuid primary key references auth.users on delete cascade,
  sin_anuncios_hasta timestamptz,
  actualizado        timestamptz not null default now()
);
alter table ventajas enable row level security;
revoke all on ventajas from anon, public, authenticated;
grant select on ventajas to authenticated;
drop policy if exists ventajas_leer on ventajas;
create policy ventajas_leer on ventajas for select to authenticated using (perfil_id = auth.uid() or es_master());

create table if not exists canjes_ventajas (
  codigo_id uuid not null references codigos_promo on delete cascade,
  perfil_id uuid not null references auth.users on delete cascade,
  creado_en timestamptz not null default now(),
  primary key (codigo_id, perfil_id)
);
alter table canjes_ventajas enable row level security;
revoke all on canjes_ventajas from anon, public, authenticated;

-- Estado del usuario: ¿ve anuncios? (el máster nunca)
create or replace function mis_ventajas() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'sin_anuncios', es_master() or coalesce(v.sin_anuncios_hasta > now(), false),
    'hasta', case when v.sin_anuncios_hasta = 'infinity' then null else v.sin_anuncios_hasta end,
    'para_siempre', es_master() or coalesce(v.sin_anuncios_hasta = 'infinity', false))
  from (select 1) x left join ventajas v on v.perfil_id = auth.uid()
$$;

create or replace function dar_sin_anuncios(p_perfil uuid, p_dias int) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v_hasta timestamptz;
begin
  insert into ventajas (perfil_id, sin_anuncios_hasta)
  values (p_perfil, case when p_dias is null then 'infinity'::timestamptz else now() + make_interval(days => p_dias) end)
  on conflict (perfil_id) do update set
    sin_anuncios_hasta = case
      when p_dias is null or ventajas.sin_anuncios_hasta = 'infinity' then 'infinity'::timestamptz
      else greatest(coalesce(ventajas.sin_anuncios_hasta, now()), now()) + make_interval(days => p_dias) end,
    actualizado = now()
  returning sin_anuncios_hasta into v_hasta;
  return v_hasta;
end $$;

-- Canje único: dinero Fantasy (en la liga indicada) o sin anuncios (en la cuenta)
create or replace function canjear(p_codigo text, p_liga uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c codigos_promo; v_m uuid; v_saldo numeric; v_hasta timestamptz;
begin
  if auth.uid() is null then raise exception 'Inicia sesión para canjear'; end if;
  select * into c from codigos_promo where codigo = upper(trim(p_codigo)) for update;
  if not found or not c.activo or (c.caduca is not null and c.caduca < now())
     or (c.usos_max is not null and c.usos >= c.usos_max) then
    raise exception 'Código no válido o caducado';
  end if;

  if c.tipo = 'sin_anuncios' then
    if exists (select 1 from canjes_ventajas where codigo_id = c.id and perfil_id = auth.uid()) then
      raise exception 'Ya has canjeado este código';
    end if;
    insert into canjes_ventajas (codigo_id, perfil_id) values (c.id, auth.uid());
    update codigos_promo set usos = usos + 1 where id = c.id;
    v_hasta := dar_sin_anuncios(auth.uid(), c.dias);
    return jsonb_build_object('tipo', 'sin_anuncios', 'para_siempre', v_hasta = 'infinity',
                              'hasta', case when v_hasta = 'infinity' then null else v_hasta end);
  end if;

  -- Dinero Fantasy
  if p_liga is null then raise exception 'Este código es de dinero Fantasy: elige antes tu liga'; end if;
  if c.liga_id is not null and c.liga_id <> p_liga then raise exception 'Código no válido o caducado'; end if;
  if not coalesce((select compras_dinero from ligas where id = p_liga), true) then
    raise exception 'En esta liga el admin no permite conseguir dinero Fantasy con códigos';
  end if;
  v_m := mi_miembro(p_liga);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if not exists (select 1 from fantasy_managers where liga_id = p_liga and miembro_id = v_m) then
    raise exception 'Aún no participas en el Fantasy de esta liga';
  end if;
  if exists (select 1 from canjes_promo where codigo_id = c.id and manager_id = v_m) then
    raise exception 'Ya has canjeado este código';
  end if;
  insert into canjes_promo (codigo_id, liga_id, manager_id, importe) values (c.id, p_liga, v_m, c.importe);
  update codigos_promo set usos = usos + 1 where id = c.id;
  v_saldo := mover_saldo(p_liga, v_m, c.importe, 'ajuste');
  return jsonb_build_object('tipo', 'dinero', 'importe', c.importe, 'saldo', v_saldo);
end $$;

-- Máster: crear códigos de los dos tipos (sustituye a la versión de 0021)
drop function if exists master_crear_codigo(text, numeric, uuid, int, timestamptz, text);
create or replace function master_crear_codigo(p_codigo text, p_importe numeric default null, p_liga uuid default null,
                                               p_usos_max int default null, p_caduca timestamptz default null,
                                               p_nota text default null, p_tipo text default 'dinero',
                                               p_dias int default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_cod text := upper(trim(p_codigo));
begin
  perform exigir_master();
  insert into codigos_promo (codigo, tipo, importe, dias, liga_id, usos_max, caduca, nota, creado_por)
  values (v_cod, p_tipo, case when p_tipo = 'dinero' then round(p_importe, 2) end,
          case when p_tipo = 'sin_anuncios' then p_dias end,
          case when p_tipo = 'dinero' then p_liga end, p_usos_max, p_caduca, p_nota, auth.uid())
  returning id into v_id;
  perform auditar_master('crear_codigo', p_liga,
    jsonb_build_object('codigo', v_cod, 'tipo', p_tipo, 'importe', p_importe, 'dias', p_dias,
                       'usos_max', p_usos_max, 'caduca', p_caduca));
  return v_id;
end $$;

create or replace function master_codigos() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_master();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'codigo', c.codigo, 'tipo', c.tipo, 'importe', c.importe, 'dias', c.dias, 'liga_id', c.liga_id,
      'liga', (select nombre from ligas where id = c.liga_id), 'usos', c.usos, 'usos_max', c.usos_max,
      'caduca', c.caduca, 'activo', c.activo, 'nota', c.nota, 'creado_en', c.creado_en)
      order by c.creado_en desc) from codigos_promo c), '[]');
end $$;

-- canjear_codigo (0021) respeta también el permiso de la liga
create or replace function canjear_codigo(p_liga uuid, p_codigo text) returns numeric
language plpgsql security definer set search_path = public as $$
begin
  return ((canjear(p_codigo, p_liga)) ->> 'saldo')::numeric;
end $$;

revoke execute on function mis_ventajas(), dar_sin_anuncios(uuid, int), canjear(text, uuid),
  master_crear_codigo(text, numeric, uuid, int, timestamptz, text, text, int) from public, anon;
revoke execute on function dar_sin_anuncios(uuid, int) from authenticated;
grant execute on function mis_ventajas(), canjear(text, uuid),
  master_crear_codigo(text, numeric, uuid, int, timestamptz, text, text, int) to authenticated;
