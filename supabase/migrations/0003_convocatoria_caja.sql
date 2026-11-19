-- 0003 · Convocatoria (cupo y lista de espera), equipos y tesorería

-- ───────────── Cupo y lista de espera ─────────────
-- BEFORE: si no hay plaza, el "confirmado" pasa a "espera". También protege equipo y estado del partido.
create or replace function gestionar_cupo() returns trigger
language plpgsql security definer set search_path = public as $$
declare p partidos; v_conf int; v_admin boolean;
begin
  select * into p from partidos where id = new.partido_id for update;   -- serializa altas simultáneas
  v_admin := auth.uid() is null or es_admin(p.liga_id);                 -- null = service_role / tareas internas

  if not v_admin then
    if p.estado not in ('abierto', 'completo', 'equipos_hechos') then
      raise exception 'La convocatoria de este partido ya está cerrada';
    end if;
    if tg_op = 'UPDATE' and new.equipo is distinct from old.equipo then
      raise exception 'Solo un administrador puede cambiar los equipos';
    end if;
    if tg_op = 'INSERT' then new.equipo := null; end if;
  end if;

  if tg_op = 'UPDATE' and old.estado <> 'confirmado' and new.estado = 'confirmado' then
    new.inscrito_en := clock_timestamp();   -- volver a apuntarse = al final de la cola
  end if;

  if new.estado = 'confirmado' and (tg_op = 'INSERT' or old.estado <> 'confirmado') then
    select count(*) into v_conf from convocatorias
     where partido_id = new.partido_id and estado = 'confirmado' and miembro_id <> new.miembro_id;
    if v_conf >= p.plazas then new.estado := 'espera'; end if;
  end if;

  if new.estado <> 'confirmado' then new.equipo := null; end if;
  return new;
end $$;

-- AFTER: si se libera una plaza, sube el primero de la espera; recalcula abierto/completo
create or replace function promover_espera() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_partido uuid := coalesce(new.partido_id, old.partido_id); p partidos; v_conf int;
begin
  select * into p from partidos where id = v_partido;
  if p.id is null then return null; end if;   -- partido borrado en cascada

  if tg_op <> 'INSERT' and old.estado = 'confirmado'
     and (tg_op = 'DELETE' or new.estado <> 'confirmado')
     and p.estado in ('abierto', 'completo', 'equipos_hechos') then
    update convocatorias set estado = 'confirmado'
     where (partido_id, miembro_id) = (
       select partido_id, miembro_id from convocatorias
        where partido_id = v_partido and estado = 'espera'
        order by inscrito_en limit 1);
    -- TODO notificación push "¡Tienes plaza!" (Edge Function escuchando este cambio)
  end if;

  if p.estado in ('abierto', 'completo') then
    select count(*) into v_conf from convocatorias where partido_id = v_partido and estado = 'confirmado';
    update partidos set estado = case when v_conf >= plazas then 'completo'::estado_partido else 'abierto' end
     where id = v_partido and estado in ('abierto', 'completo');
  end if;
  return null;
end $$;

create trigger t_cupo before insert or update of estado, equipo on convocatorias
  for each row execute function gestionar_cupo();
create trigger t_espera after insert or update of estado or delete on convocatorias
  for each row execute function promover_espera();

-- ───────────── Equipos ─────────────
-- p_asignacion: {"<miembro_id>": 1, "<miembro_id>": 2, ...} (resultado del balanceo + ajustes manuales)
create or replace function guardar_equipos(p_partido uuid, p_asignacion jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; v_sin int;
begin
  select * into p from partidos where id = p_partido;
  perform exigir_admin(p.liga_id);
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') then
    raise exception 'Los equipos ya no se pueden cambiar';
  end if;

  update convocatorias c set equipo = (p_asignacion ->> c.miembro_id::text)::smallint
   where c.partido_id = p_partido and c.estado = 'confirmado';

  select count(*) into v_sin from convocatorias
   where partido_id = p_partido and estado = 'confirmado'
     and (equipo is null or equipo > p.num_equipos);
  if v_sin > 0 then raise exception 'Hay % confirmados sin equipo válido', v_sin; end if;

  update partidos set estado = 'equipos_hechos' where id = p_partido;

  -- Con 2 equipos el encuentro es único y se crea solo
  if p.num_equipos = 2 then
    insert into encuentros (partido_id, n, equipo_local, equipo_visitante)
    values (p_partido, 1, 1, 2) on conflict do nothing;
  end if;
end $$;

-- Con 3-4 equipos: lista de enfrentamientos [[1,2],[3,1],...]. Se puede rehacer hasta consolidar.
create or replace function definir_encuentros(p_partido uuid, p_lista jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; i int;
begin
  select * into p from partidos where id = p_partido;
  perform exigir_admin(p.liga_id);
  if p.estado in ('en_revision', 'cerrado', 'cancelado') then
    raise exception 'El acta ya está consolidada';
  end if;
  delete from encuentros where partido_id = p_partido;
  for i in 0 .. jsonb_array_length(p_lista) - 1 loop
    insert into encuentros (partido_id, n, equipo_local, equipo_visitante)
    values (p_partido, i + 1, (p_lista -> i ->> 0)::smallint, (p_lista -> i ->> 1)::smallint);
  end loop;
end $$;

-- ───────────── Tesorería ─────────────
-- Un cargo por confirmado. Coste = suma de facturas del partido si las hay; si no, coste_total.
-- Los céntimos del redondeo van al primer inscrito. Idempotente.
create or replace function generar_cargos(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; n int; v_coste numeric(8,2); cuota numeric(8,2); resto numeric(8,2);
begin
  select * into p from partidos where id = p_partido for update;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.cargos_generados then return 0; end if;

  select coalesce(sum(importe), 0) into v_coste from facturas where partido_id = p_partido;
  if v_coste = 0 then v_coste := p.coste_total; end if;

  select count(*) into n from convocatorias where partido_id = p_partido and estado = 'confirmado';
  if n = 0 or v_coste = 0 then
    update partidos set cargos_generados = true where id = p_partido;
    return 0;
  end if;

  cuota := trunc(v_coste / n, 2);
  resto := v_coste - cuota * n;
  insert into movimientos (liga_id, miembro_id, partido_id, tipo, importe, concepto, registrado_por)
  select p.liga_id, c.miembro_id, p.id, 'cargo',
         -(cuota + case when row_number() over (order by c.inscrito_en) = 1 then resto else 0 end),
         'Partido ' || to_char(p.fecha_hora at time zone 'Europe/Madrid', 'DD/MM'),
         mi_miembro(p.liga_id)
    from convocatorias c
   where c.partido_id = p_partido and c.estado = 'confirmado';

  update partidos set cargos_generados = true where id = p_partido;
  return n;
end $$;

-- Registrar un pago (o un ajuste con signo) de un miembro
create or replace function registrar_pago(p_miembro uuid, p_importe numeric,
                                          p_partido uuid default null, p_concepto text default null,
                                          p_tipo tipo_mov default 'pago')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_liga uuid; v_id uuid;
begin
  select liga_id into v_liga from miembros where id = p_miembro;
  perform exigir_admin(v_liga);
  if p_tipo = 'cargo' then raise exception 'Los cargos los genera el sistema'; end if;
  insert into movimientos (liga_id, miembro_id, partido_id, tipo, importe, concepto, registrado_por)
  values (v_liga, p_miembro, p_partido, p_tipo, p_importe, p_concepto, mi_miembro(v_liga))
  returning id into v_id;
  return v_id;
end $$;

-- Saldo de cada miembro (negativo = debe dinero)
create view v_saldos with (security_invoker = true) as
select m.liga_id, m.id as miembro_id,
       coalesce(sum(mv.importe), 0)                                   as saldo,
       coalesce(-sum(mv.importe) filter (where mv.tipo = 'cargo'), 0) as total_cargado,
       coalesce(sum(mv.importe) filter (where mv.tipo = 'pago'), 0)   as total_pagado
  from miembros m
  left join movimientos mv on mv.miembro_id = m.id
 where m.perfil_id = auth.uid() or es_admin(m.liga_id)    -- cada uno el suyo; admins, todos
 group by m.liga_id, m.id;

-- Estado de pago de cada asistente en cada partido
create view v_pagos_partido with (security_invoker = true) as
select c.partido_id, c.miembro_id,
       coalesce(-sum(mv.importe) filter (where mv.tipo = 'cargo'), 0) as importe,
       coalesce(sum(mv.importe)  filter (where mv.tipo = 'pago'), 0)  as pagado,
       case when coalesce(sum(mv.importe), 0) >= 0 then 'pagado' else 'pendiente' end as estado_pago
  from convocatorias c
  left join movimientos mv on mv.partido_id = c.partido_id and mv.miembro_id = c.miembro_id
 where c.estado = 'confirmado'
 group by c.partido_id, c.miembro_id;
