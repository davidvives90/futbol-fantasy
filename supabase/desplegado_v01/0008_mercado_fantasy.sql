-- 0008 · Liga Fantasy de mánagers: encuesta inicial, precios, mercado, plantillas, alineaciones y liquidación
-- Contrato: docs/mercado_fantasy.md
--
-- Decisiones donde la especificación dejaba margen (documentadas también en el README):
--  · Congelación de alineaciones: congelar_alineaciones(partido) fija no_habitual/multiplicador y copia la
--    alineación anterior a quien no guardó. Se ejecuta (idempotente) en el primer momento en que algo lo
--    necesita tras el cierre: recalcular_precios, liquidar_jornada o la tarea programada (pg_cron)
--    congelar_alineaciones_vencidas(). Como el estado "no habitual" solo cambia en recalcular_precios, que
--    congela antes de tocarlo, el valor congelado es siempre el vigente a la hora de cierre, aunque la
--    tarea programada no exista. La visibilidad de alineaciones ajenas depende solo de la hora.
--  · La alineación admite MENOS jugadores que el máximo (media plantilla); nunca más.
--  · Si un jugador pasa a no habitual estando ya en una plantilla, no se obliga a venderlo; el límite de
--    1 no habitual solo bloquea nuevas compras.
--  · El mercado está cerrado si la liga no tiene encuesta general cerrada (no hay precios) o si algún partido
--    no cerrado/cancelado ya pasó su hora de cierre de alineaciones. Un partido olvidado sin cerrar bloquea el
--    mercado hasta que un admin lo cierra o lo cancela.
--  · Venta: precio × (1 − comisión) redondeado a céntimos (no a 0,05).
--  · Los mánagers que llegan después de la encuesta reciben el mismo presupuesto inicial al hacer su primera
--    operación (asegurar_manager). Los jugadores que llegan después entran al mercado con G = 50.

-- ───────────── Parámetros del mercado en cada liga ─────────────
alter table ligas
  add column precio_min              numeric(6,2) not null default 1    check (precio_min > 0),
  add column precio_max              numeric(6,2) not null default 12,
  add column max_plantilla           smallint     not null default 6    check (max_plantilla between 1 and 15),
  add column bonus_no_habitual       numeric(4,2) not null default 1.5  check (bonus_no_habitual >= 1),
  add column horas_cierre_alineacion smallint     not null default 2    check (horas_cierre_alineacion between 0 and 72),
  add column ingreso_por_punto       numeric(6,3) not null default 0.10 check (ingreso_por_punto >= 0),
  add column comision_venta          numeric(4,3) not null default 0.05 check (comision_venta between 0 and 0.5),
  add column k_encuesta              numeric(5,2) not null default 5    check (k_encuesta >= 0),
  add column max_variacion           numeric(4,3) not null default 0.15 check (max_variacion between 0 and 1),
  add column presupuesto_inicial     numeric(8,2),                       -- se fija al cerrar la encuesta general
  add constraint ligas_precios_ck check (precio_max > precio_min);

alter table partidos
  add column alineaciones_congeladas boolean not null default false,
  add column jornada_liquidada       boolean not null default false;

create type atributo_valoracion as enum ('calidad', 'velocidad', 'resistencia', 'defensa', 'regate', 'portero');
create type estado_encuesta     as enum ('abierta', 'cerrada');
create type tipo_tx_fantasy     as enum ('presupuesto_inicial', 'compra', 'venta', 'ingreso_puntos', 'ajuste');

-- ───────────── Tablas ─────────────
create table encuestas_valoracion (
  id          uuid primary key default gen_random_uuid(),
  liga_id     uuid not null references ligas on delete cascade,
  sujeto_id   uuid references miembros on delete cascade,   -- null = encuesta general; si no, mini-encuesta
  estado      estado_encuesta not null default 'abierta',
  creada_en   timestamptz not null default now(),
  cerrada_en  timestamptz
);
create unique index encuesta_abierta_unica on encuestas_valoracion (liga_id, coalesce(sujeto_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where estado = 'abierta';
create unique index encuesta_general_unica on encuestas_valoracion (liga_id) where sujeto_id is null and estado = 'cerrada';

create table respuestas_ranking (
  encuesta_id  uuid not null references encuestas_valoracion on delete cascade,
  evaluador_id uuid not null references miembros on delete cascade,
  atributo     atributo_valoracion not null,
  miembro_id   uuid not null references miembros on delete cascade,
  posicion     smallint not null check (posicion >= 1),
  primary key (encuesta_id, evaluador_id, atributo, miembro_id),
  unique (encuesta_id, evaluador_id, atributo, posicion)
);

create table valoracion_jugador (
  liga_id         uuid not null references ligas on delete cascade,
  miembro_id      uuid not null references miembros on delete cascade,
  calidad         numeric(5,2),
  velocidad       numeric(5,2),
  resistencia     numeric(5,2),
  defensa         numeric(5,2),
  regate          numeric(5,2),
  portero         numeric(5,2),
  general         numeric(5,2) not null,
  num_evaluadores int not null default 0,
  actualizado_en  timestamptz not null default now(),
  primary key (liga_id, miembro_id)
);

create table mercado_jugador (
  liga_id        uuid not null references ligas on delete cascade,
  miembro_id     uuid not null references miembros on delete cascade,
  precio         numeric(6,2) not null check (precio > 0),
  rating         numeric(5,2) not null,
  no_habitual    boolean not null default false,
  actualizado_en timestamptz not null default now(),
  primary key (liga_id, miembro_id)
);

create table historial_precios (
  id          bigint generated always as identity primary key,
  liga_id     uuid not null references ligas on delete cascade,
  miembro_id  uuid not null references miembros on delete cascade,
  partido_id  uuid references partidos on delete set null,   -- null = precio inicial / mini-encuesta
  precio      numeric(6,2) not null,
  rating      numeric(5,2) not null,
  demanda     numeric(5,4),
  creado_en   timestamptz not null default now()
);
create index on historial_precios (liga_id, miembro_id, creado_en desc);
create unique index historial_una_vez_por_jornada on historial_precios (liga_id, miembro_id, partido_id)
  where partido_id is not null;

create table fantasy_managers (
  liga_id         uuid not null references ligas on delete cascade,
  miembro_id      uuid not null references miembros on delete cascade,
  saldo           numeric(8,2) not null check (saldo >= 0),
  puntos_totales  numeric(8,2) not null default 0,
  creado_en       timestamptz not null default now(),
  primary key (liga_id, miembro_id)
);

create table plantillas (
  liga_id        uuid not null references ligas on delete cascade,
  manager_id     uuid not null references miembros on delete cascade,
  jugador_id     uuid not null references miembros on delete cascade,
  precio_compra  numeric(6,2) not null,
  comprado_en    timestamptz not null default now(),
  primary key (manager_id, jugador_id)
);
create index on plantillas (liga_id, jugador_id);

create table transacciones_fantasy (
  id             uuid primary key default gen_random_uuid(),
  liga_id        uuid not null references ligas on delete cascade,
  manager_id     uuid not null references miembros on delete cascade,
  jugador_id     uuid references miembros on delete set null,
  partido_id     uuid references partidos on delete set null,
  tipo           tipo_tx_fantasy not null,
  importe        numeric(8,2) not null,
  saldo_despues  numeric(8,2) not null,
  creado_en      timestamptz not null default clock_timestamp()
);
create index on transacciones_fantasy (manager_id, creado_en desc);

create table alineaciones (
  partido_id     uuid not null references partidos on delete cascade,
  manager_id     uuid not null references miembros on delete cascade,
  jugador_id     uuid not null references miembros on delete cascade,
  no_habitual    boolean,            -- congelado al cierre (null = aún no congelado)
  multiplicador  numeric(4,2),       -- 1 o bonus_no_habitual, congelado al cierre
  copiada        boolean not null default false,   -- copiada de la jornada anterior
  primary key (partido_id, manager_id, jugador_id)
);
create index on alineaciones (manager_id);

create table puntos_manager (
  partido_id  uuid not null references partidos on delete cascade,
  manager_id  uuid not null references miembros on delete cascade,
  puntos      numeric(7,2) not null,
  ingreso     numeric(8,2) not null,
  desglose    jsonb not null,        -- [{"jugador_id":…, "puntos":13, "multiplicador":1.5, "total":19.5}, …]
  primary key (partido_id, manager_id)
);

-- ───────────── Ayudantes ─────────────
create or replace function redondear_005(x numeric) returns numeric
language sql immutable as $$ select round(x * 20) / 20 $$;

-- Precio base cuadrático a partir de un rating 0–100
create or replace function precio_base(p_liga uuid, p_rating numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select l.precio_min + (l.precio_max - l.precio_min) * power(greatest(0, least(100, p_rating)) / 100.0, 2)
    from ligas l where l.id = p_liga
$$;

-- Jugadores que aparecen en el mercado / en la encuesta: activos y pre-creados (no expulsados)
create or replace function jugadores_liga(p_liga uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  select id from miembros where liga_id = p_liga and estado in ('activo', 'pendiente_registro')
$$;

-- No habitual: pre-creado sin cuenta, o < 40 % de los últimos 10 partidos cerrados (si la liga tiene ≥ 5)
create or replace function es_no_habitual(p_miembro uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare m miembros; v_total int; v_jugados int;
begin
  select * into m from miembros where id = p_miembro;
  if m.perfil_id is null then return true; end if;
  select count(*), count(pf.miembro_id) into v_total, v_jugados
    from (select id from partidos where liga_id = m.liga_id and estado = 'cerrado'
           order by fecha_hora desc limit 10) p
    left join puntos_fantasy pf on pf.partido_id = p.id and pf.miembro_id = p_miembro;
  if (select count(*) from partidos where liga_id = m.liga_id and estado = 'cerrado') < 5 then
    return false;
  end if;
  return v_jugados::numeric / nullif(v_total, 0) < 0.4;
end $$;

create or replace function hora_cierre_alineacion(p_partido uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select p.fecha_hora - make_interval(hours => l.horas_cierre_alineacion)
    from partidos p join ligas l on l.id = p.liga_id where p.id = p_partido
$$;

create or replace function alineacion_visible(p_partido uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select now() >= hora_cierre_alineacion(p_partido)
      or (select estado in ('jugado', 'post_partido', 'en_revision', 'cerrado') from partidos where id = p_partido)
$$;

create or replace function mercado_abierto(p_liga uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from encuestas_valoracion
                  where liga_id = p_liga and sujeto_id is null and estado = 'cerrada')
     and not exists (select 1 from partidos p join ligas l on l.id = p.liga_id
                       where p.liga_id = p_liga and p.estado not in ('cerrado', 'cancelado')
                         and now() >= p.fecha_hora - make_interval(hours => l.horas_cierre_alineacion))
$$;

-- Fila de mánager (con el presupuesto inicial) para quien llega después de la encuesta
create or replace function asegurar_manager(p_liga uuid, p_miembro uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_presu numeric;
begin
  if exists (select 1 from fantasy_managers where liga_id = p_liga and miembro_id = p_miembro) then return; end if;
  select presupuesto_inicial into v_presu from ligas where id = p_liga;
  if v_presu is null then raise exception 'El mercado aún no está abierto: falta cerrar la encuesta inicial'; end if;
  insert into fantasy_managers (liga_id, miembro_id, saldo) values (p_liga, p_miembro, v_presu)
  on conflict do nothing;
  if found then
    insert into transacciones_fantasy (liga_id, manager_id, tipo, importe, saldo_despues)
    values (p_liga, p_miembro, 'presupuesto_inicial', v_presu, v_presu);
  end if;
end $$;

-- ───────────── 1. Encuesta inicial de valoración conjunta ─────────────
create or replace function abrir_encuesta(p_liga uuid, p_sujeto uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform exigir_admin(p_liga);
  if p_sujeto is null and exists (select 1 from encuestas_valoracion
                                   where liga_id = p_liga and sujeto_id is null and estado = 'cerrada') then
    raise exception 'La encuesta inicial ya se hizo; para un jugador nuevo abre una mini-encuesta';
  end if;
  if p_sujeto is not null and p_sujeto not in (select jugadores_liga(p_liga)) then
    raise exception 'Ese jugador no está en la liga';
  end if;
  insert into encuestas_valoracion (liga_id, sujeto_id) values (p_liga, p_sujeto) returning id into v_id;
  return v_id;
end $$;

-- Cada mánager envía, por atributo, el orden completo de los jugadores (1.º = mejor)
create or replace function enviar_ranking(p_encuesta uuid, p_atributo text, p_orden uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare e encuestas_valoracion; v_eval uuid; v_attr atributo_valoracion; v_n int;
begin
  select * into e from encuestas_valoracion where id = p_encuesta;
  if not found then raise exception 'Encuesta no encontrada'; end if;
  if e.estado <> 'abierta' then raise exception 'La encuesta está cerrada'; end if;
  v_eval := mi_miembro(e.liga_id);
  if v_eval is null then raise exception 'Solo responden los miembros activos de la liga'; end if;
  begin
    v_attr := p_atributo::atributo_valoracion;
  exception when invalid_text_representation then
    raise exception 'Atributo no válido: %', p_atributo;
  end;

  select count(*) into v_n from jugadores_liga(e.liga_id);
  if coalesce(array_length(p_orden, 1), 0) <> v_n
     or (select count(distinct x) from unnest(p_orden) x) <> v_n
     or exists (select 1 from unnest(p_orden) x where x not in (select jugadores_liga(e.liga_id))) then
    raise exception 'Hay que ordenar a los % jugadores de la liga, sin repetir ninguno', v_n;
  end if;

  delete from respuestas_ranking where encuesta_id = p_encuesta and evaluador_id = v_eval and atributo = v_attr;
  insert into respuestas_ranking (encuesta_id, evaluador_id, atributo, miembro_id, posicion)
  select p_encuesta, v_eval, v_attr, t.x, t.ord::smallint
    from unnest(p_orden) with ordinality as t(x, ord);
end $$;

-- Nota 0–100 de un jugador en un atributo: sin autoevaluación; media recortada con ≥ 5 evaluadores
create or replace function nota_atributo(p_encuesta uuid, p_miembro uuid, p_attr atributo_valoracion,
                                         out nota numeric, out evaluadores int)
language plpgsql stable security definer set search_path = public as $$
declare v_suma numeric; v_max numeric; v_min numeric;
begin
  select count(*), sum(s), max(s), min(s) into evaluadores, v_suma, v_max, v_min
    from (select case when t.n <= 1 then 100.0 else 100.0 * (t.n - r.posicion) / (t.n - 1) end as s
            from respuestas_ranking r
            join (select evaluador_id, count(*) n from respuestas_ranking
                   where encuesta_id = p_encuesta and atributo = p_attr group by evaluador_id) t
              on t.evaluador_id = r.evaluador_id
           where r.encuesta_id = p_encuesta and r.atributo = p_attr
             and r.miembro_id = p_miembro and r.evaluador_id <> p_miembro) x;
  if evaluadores = 0 then nota := null;
  elsif evaluadores >= 5 then nota := (v_suma - v_max - v_min) / (evaluadores - 2);
  else nota := v_suma / evaluadores;
  end if;
end $$;

-- Media general G según posición (portero / campo)
create or replace function media_general(p_pos posicion_campo, cal numeric, vel numeric, res numeric,
                                         def numeric, reg numeric, por numeric) returns numeric
language sql immutable as $$
  select case when p_pos = 'portero'
              then 0.60 * coalesce(por, 50) + 0.20 * coalesce(cal, 50) + 0.20 * coalesce(res, 50)
              else 0.35 * coalesce(cal, 50) + 0.15 * coalesce(vel, 50) + 0.15 * coalesce(res, 50)
                 + 0.15 * coalesce(def, 50) + 0.20 * coalesce(reg, 50) end
$$;

create or replace function cerrar_encuesta(p_encuesta uuid) returns int
language plpgsql security definer set search_path = public as $$
declare e encuestas_valoracion; j uuid; v_cal record; v_vel record; v_res record; v_def record;
        v_reg record; v_por record; v_g numeric; v_precio numeric; v_presu numeric; k int := 0;
        v_jugados int;
begin
  select * into e from encuestas_valoracion where id = p_encuesta for update;
  if not found then raise exception 'Encuesta no encontrada'; end if;
  perform exigir_admin(e.liga_id);
  if e.estado <> 'abierta' then raise exception 'La encuesta ya está cerrada'; end if;

  for j in select x from jugadores_liga(e.liga_id) x
            where e.sujeto_id is null or x = e.sujeto_id loop
    v_cal := nota_atributo(p_encuesta, j, 'calidad');
    v_vel := nota_atributo(p_encuesta, j, 'velocidad');
    v_res := nota_atributo(p_encuesta, j, 'resistencia');
    v_def := nota_atributo(p_encuesta, j, 'defensa');
    v_reg := nota_atributo(p_encuesta, j, 'regate');
    v_por := nota_atributo(p_encuesta, j, 'portero');
    v_g := round(media_general(posicion_de(j), v_cal.nota, v_vel.nota, v_res.nota,
                               v_def.nota, v_reg.nota, v_por.nota), 2);

    insert into valoracion_jugador (liga_id, miembro_id, calidad, velocidad, resistencia, defensa, regate,
                                    portero, general, num_evaluadores, actualizado_en)
    values (e.liga_id, j, round(v_cal.nota, 2), round(v_vel.nota, 2), round(v_res.nota, 2),
            round(v_def.nota, 2), round(v_reg.nota, 2), round(v_por.nota, 2), v_g, v_cal.evaluadores, now())
    on conflict (liga_id, miembro_id) do update
      set calidad = excluded.calidad, velocidad = excluded.velocidad, resistencia = excluded.resistencia,
          defensa = excluded.defensa, regate = excluded.regate, portero = excluded.portero,
          general = excluded.general, num_evaluadores = excluded.num_evaluadores, actualizado_en = now();

    -- Precio: siempre en la encuesta general; en una mini-encuesta solo si aún no ha jugado
    select count(*) into v_jugados from puntos_fantasy pf join partidos p on p.id = pf.partido_id
     where pf.miembro_id = j and p.liga_id = e.liga_id;
    if e.sujeto_id is null or v_jugados = 0 then
      v_precio := redondear_005(precio_base(e.liga_id, v_g));
      insert into mercado_jugador (liga_id, miembro_id, precio, rating, no_habitual)
      values (e.liga_id, j, v_precio, v_g, es_no_habitual(j))
      on conflict (liga_id, miembro_id) do update
        set precio = excluded.precio, rating = excluded.rating, no_habitual = excluded.no_habitual,
            actualizado_en = now();
      insert into historial_precios (liga_id, miembro_id, precio, rating)
      values (e.liga_id, j, v_precio, v_g);
    end if;
    k := k + 1;
  end loop;

  update encuestas_valoracion set estado = 'cerrada', cerrada_en = now() where id = p_encuesta;

  if e.sujeto_id is null then
    -- Presupuesto inicial = 6,5 × precio medio inicial, redondeado a 0,5
    select round(6.5 * avg(precio) * 2) / 2 into v_presu from mercado_jugador where liga_id = e.liga_id;
    update ligas set presupuesto_inicial = v_presu where id = e.liga_id;
    perform asegurar_manager(e.liga_id, m.id)
       from miembros m where m.liga_id = e.liga_id and m.estado = 'activo';
  end if;
  return k;
end $$;

-- Jugadores que llegan con el mercado ya abierto: entran con G = 50
create or replace function alta_jugador_mercado() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_precio numeric;
begin
  if new.estado in ('activo', 'pendiente_registro')
     and exists (select 1 from encuestas_valoracion where liga_id = new.liga_id
                  and sujeto_id is null and estado = 'cerrada')
     and not exists (select 1 from mercado_jugador where liga_id = new.liga_id and miembro_id = new.id) then
    v_precio := redondear_005(precio_base(new.liga_id, 50));
    insert into mercado_jugador (liga_id, miembro_id, precio, rating, no_habitual)
    values (new.liga_id, new.id, v_precio, 50, new.perfil_id is null);
    insert into historial_precios (liga_id, miembro_id, precio, rating) values (new.liga_id, new.id, v_precio, 50);
  end if;
  return null;
end $$;

create trigger t_alta_mercado after insert or update of estado on miembros
  for each row execute function alta_jugador_mercado();

-- ───────────── 5. Alineaciones (congelación) ─────────────
-- Idempotente. Tras la hora de cierre: copia la alineación anterior a quien no guardó y congela no_habitual.
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

  for fm in select miembro_id from fantasy_managers where liga_id = p.liga_id loop
    if not exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id) then
      select a.partido_id into v_prev
        from alineaciones a join partidos pp on pp.id = a.partido_id
       where a.manager_id = fm.miembro_id and pp.liga_id = p.liga_id and pp.fecha_hora < p.fecha_hora
       order by pp.fecha_hora desc limit 1;
      if v_prev is not null then
        insert into alineaciones (partido_id, manager_id, jugador_id, copiada)
        select p_partido, fm.miembro_id, a.jugador_id, true
          from alineaciones a
          join plantillas pl on pl.manager_id = a.manager_id and pl.jugador_id = a.jugador_id
         where a.partido_id = v_prev and a.manager_id = fm.miembro_id
         order by a.jugador_id
         limit v_tam;
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

create or replace function congelar_vencidas_liga(p_liga uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r record; k int := 0;
begin
  for r in select p.id from partidos p
            where p.liga_id = p_liga and not p.alineaciones_congeladas and p.estado <> 'cancelado'
              and now() >= hora_cierre_alineacion(p.id)
            order by p.fecha_hora loop
    if congelar_alineaciones(r.id) then k := k + 1; end if;
  end loop;
  return k;
end $$;

-- Para pg_cron (cada 15 min): select congelar_alineaciones_vencidas();
create or replace function congelar_alineaciones_vencidas() returns int
language plpgsql security definer set search_path = public as $$
declare r record; k int := 0;
begin
  for r in select distinct liga_id from partidos
            where not alineaciones_congeladas and estado <> 'cancelado' loop
    k := k + congelar_vencidas_liga(r.liga_id);
  end loop;
  return k;
end $$;

create or replace function guardar_alineacion(p_partido uuid, p_jugadores uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; v_m uuid; v_tam int; v_n int;
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  v_m := mi_miembro(p.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') or p.alineaciones_congeladas
     or now() >= hora_cierre_alineacion(p_partido) then
    raise exception 'La alineación de este partido ya está cerrada (cierra % h antes del partido)',
      (select horas_cierre_alineacion from ligas where id = p.liga_id);
  end if;
  perform asegurar_manager(p.liga_id, v_m);

  v_tam := p.plazas / p.num_equipos;
  v_n := coalesce(array_length(p_jugadores, 1), 0);
  if v_n > v_tam then
    raise exception 'La alineación es de media plantilla del partido: como máximo % jugadores', v_tam;
  end if;
  if (select count(distinct x) from unnest(p_jugadores) x) <> v_n then
    raise exception 'Hay jugadores repetidos en la alineación';
  end if;
  if exists (select 1 from unnest(p_jugadores) x
              where not exists (select 1 from plantillas where manager_id = v_m and jugador_id = x)) then
    raise exception 'Solo puedes alinear jugadores de tu plantilla';
  end if;

  delete from alineaciones where partido_id = p_partido and manager_id = v_m;
  insert into alineaciones (partido_id, manager_id, jugador_id)
  select p_partido, v_m, x from unnest(p_jugadores) x;
  return v_n;
end $$;

-- ───────────── 3. Mercado ─────────────
create or replace function comprar_jugador(p_liga uuid, p_jugador uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare l ligas; v_m uuid; fm fantasy_managers; mj mercado_jugador; v_n int; v_nh int;
begin
  v_m := mi_miembro(p_liga);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if not mercado_abierto(p_liga) then
    raise exception 'El mercado está cerrado (desde % h antes de un partido hasta que se calculan sus puntos)',
      (select horas_cierre_alineacion from ligas where id = p_liga);
  end if;
  select * into l from ligas where id = p_liga;
  perform asegurar_manager(p_liga, v_m);
  select * into fm from fantasy_managers where liga_id = p_liga and miembro_id = v_m for update;

  select * into mj from mercado_jugador where liga_id = p_liga and miembro_id = p_jugador;
  if not found or p_jugador not in (select jugadores_liga(p_liga)) then
    raise exception 'Ese jugador no está en el mercado';
  end if;
  if exists (select 1 from plantillas where manager_id = v_m and jugador_id = p_jugador) then
    raise exception 'Ya lo tienes en tu plantilla';
  end if;
  select count(*), count(*) filter (where m2.no_habitual) into v_n, v_nh
    from plantillas pl join mercado_jugador m2 on m2.liga_id = pl.liga_id and m2.miembro_id = pl.jugador_id
   where pl.manager_id = v_m;
  if v_n >= l.max_plantilla then
    raise exception 'Tu plantilla está llena (máximo % jugadores)', l.max_plantilla;
  end if;
  if mj.no_habitual and v_nh >= 1 then
    raise exception 'Solo puedes tener un jugador no habitual en la plantilla';
  end if;
  if fm.saldo < mj.precio then
    raise exception 'Saldo insuficiente: tienes % M y cuesta % M', fm.saldo, mj.precio;
  end if;

  update fantasy_managers set saldo = saldo - mj.precio where liga_id = p_liga and miembro_id = v_m;
  insert into plantillas (liga_id, manager_id, jugador_id, precio_compra) values (p_liga, v_m, p_jugador, mj.precio);
  insert into transacciones_fantasy (liga_id, manager_id, jugador_id, tipo, importe, saldo_despues)
  values (p_liga, v_m, p_jugador, 'compra', -mj.precio, fm.saldo - mj.precio);
  return fm.saldo - mj.precio;
end $$;

create or replace function vender_jugador(p_liga uuid, p_jugador uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare l ligas; v_m uuid; fm fantasy_managers; v_precio numeric; v_cobro numeric;
begin
  v_m := mi_miembro(p_liga);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if not mercado_abierto(p_liga) then
    raise exception 'El mercado está cerrado (desde % h antes de un partido hasta que se calculan sus puntos)',
      (select horas_cierre_alineacion from ligas where id = p_liga);
  end if;
  select * into l from ligas where id = p_liga;
  select * into fm from fantasy_managers where liga_id = p_liga and miembro_id = v_m for update;
  if not exists (select 1 from plantillas where manager_id = v_m and jugador_id = p_jugador and liga_id = p_liga) then
    raise exception 'Ese jugador no está en tu plantilla';
  end if;
  select precio into v_precio from mercado_jugador where liga_id = p_liga and miembro_id = p_jugador;
  v_cobro := round(v_precio * (1 - l.comision_venta), 2);

  delete from plantillas where manager_id = v_m and jugador_id = p_jugador;
  update fantasy_managers set saldo = saldo + v_cobro where liga_id = p_liga and miembro_id = v_m;
  insert into transacciones_fantasy (liga_id, manager_id, jugador_id, tipo, importe, saldo_despues)
  values (p_liga, v_m, p_jugador, 'venta', v_cobro, fm.saldo + v_cobro);
  return fm.saldo + v_cobro;
end $$;

-- ───────────── 2. Precios tras cada jornada ─────────────
-- Idempotente por (liga, partido): si ya hay historial de esa jornada no hace nada.
create or replace function recalcular_precios(p_liga uuid, p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare l ligas; v_managers int; v_dmedia numeric; r record; v_rend numeric; v_n int; v_g numeric;
        v_w numeric; v_r numeric; v_d numeric; v_f numeric; v_nuevo numeric; v_lo numeric; v_hi numeric;
        k int := 0;
begin
  if auth.uid() is not null then perform exigir_admin(p_liga); end if;
  if exists (select 1 from historial_precios where liga_id = p_liga and partido_id = p_partido) then
    return 0;
  end if;
  if not exists (select 1 from mercado_jugador where liga_id = p_liga) then return 0; end if;
  perform congelar_vencidas_liga(p_liga);   -- congela con el estado no_habitual previo al cambio
  select * into l from ligas where id = p_liga;

  select count(*) into v_managers from fantasy_managers fm join miembros m on m.id = fm.miembro_id
   where fm.liga_id = p_liga and m.estado = 'activo';
  select avg(coalesce(h.n, 0)::numeric / nullif(v_managers, 0)) into v_dmedia
    from mercado_jugador mj
    left join (select jugador_id, count(*) n from plantillas where liga_id = p_liga group by jugador_id) h
      on h.jugador_id = mj.miembro_id
   where mj.liga_id = p_liga;

  -- Rendimiento: percentil (0–100) de la media de los últimos 5 partidos jugados
  create temp table if not exists tmp_rend (miembro_id uuid primary key, partidos int, pct numeric) on commit drop;
  delete from tmp_rend;
  insert into tmp_rend
  select miembro_id, n,
         case when count(*) over () = 1 then 50 else 100 * percent_rank() over (order by media) end
    from (select h.miembro_id, avg(h.total) media,
                 (select count(*) from puntos_fantasy pf2 join partidos p2 on p2.id = pf2.partido_id
                   where pf2.miembro_id = h.miembro_id and p2.liga_id = p_liga) n
            from (select pf.miembro_id, pf.total,
                         row_number() over (partition by pf.miembro_id order by p.fecha_hora desc) rn
                    from puntos_fantasy pf join partidos p on p.id = pf.partido_id
                   where p.liga_id = p_liga and p.estado = 'cerrado') h
           where h.rn <= 5
           group by h.miembro_id) t;

  for r in select mj.*, coalesce(vj.general, 50) as g,
                  coalesce((select count(*) from plantillas pl where pl.liga_id = p_liga
                             and pl.jugador_id = mj.miembro_id), 0) as holders
             from mercado_jugador mj
             left join valoracion_jugador vj on vj.liga_id = mj.liga_id and vj.miembro_id = mj.miembro_id
            where mj.liga_id = p_liga for update of mj loop
    select partidos, pct into v_n, v_rend from tmp_rend where miembro_id = r.miembro_id;
    v_n := coalesce(v_n, 0);
    v_w := case when l.k_encuesta + v_n = 0 then 1 else l.k_encuesta / (l.k_encuesta + v_n) end;
    v_r := v_w * r.g + (1 - v_w) * coalesce(v_rend, r.g);
    v_d := r.holders::numeric / nullif(v_managers, 0);
    v_f := greatest(0.85, least(1.25, 1 + 0.4 * (coalesce(v_d, 0) - coalesce(v_dmedia, 0))));
    v_lo := r.precio * (1 - l.max_variacion);
    v_hi := r.precio * (1 + l.max_variacion);
    v_nuevo := greatest(v_lo, least(v_hi, precio_base(p_liga, v_r) * v_f));
    v_nuevo := greatest(l.precio_min, least(l.precio_max, v_nuevo));
    v_nuevo := redondear_005(v_nuevo);
    -- el redondeo nunca puede saltarse el tope de variación
    if v_nuevo > v_hi then v_nuevo := floor(v_hi * 20) / 20; end if;
    if v_nuevo < v_lo then v_nuevo := ceil(v_lo * 20) / 20; end if;
    v_nuevo := greatest(v_nuevo, l.precio_min);

    update mercado_jugador
       set precio = v_nuevo, rating = round(v_r, 2), no_habitual = es_no_habitual(r.miembro_id),
           actualizado_en = now()
     where liga_id = p_liga and miembro_id = r.miembro_id;
    insert into historial_precios (liga_id, miembro_id, partido_id, precio, rating, demanda)
    values (p_liga, r.miembro_id, p_partido, v_nuevo, round(v_r, 2), round(coalesce(v_d, 0), 4));
    k := k + 1;
  end loop;
  return k;
end $$;

-- ───────────── 6. Liquidación de la jornada ─────────────
create or replace function liquidar_jornada(p_partido uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; fm record; v_pts numeric; v_ing numeric; v_des jsonb;
begin
  select * into p from partidos where id = p_partido for update;
  if not found then raise exception 'Partido no encontrado'; end if;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado <> 'cerrado' then raise exception 'El partido aún no tiene los puntos calculados'; end if;
  if p.jornada_liquidada then return false; end if;      -- idempotente
  select * into l from ligas where id = p.liga_id;

  perform congelar_alineaciones(p_partido);

  for fm in select * from fantasy_managers where liga_id = p.liga_id for update loop
    select coalesce(sum(coalesce(pf.total, 0) * a.multiplicador), 0),
           coalesce(jsonb_agg(jsonb_build_object(
             'jugador_id', a.jugador_id, 'puntos', coalesce(pf.total, 0),
             'multiplicador', a.multiplicador, 'jugo', pf.miembro_id is not null,
             'total', coalesce(pf.total, 0) * a.multiplicador) order by a.jugador_id), '[]'::jsonb)
      into v_pts, v_des
      from alineaciones a
      left join puntos_fantasy pf on pf.partido_id = a.partido_id and pf.miembro_id = a.jugador_id
     where a.partido_id = p_partido and a.manager_id = fm.miembro_id;

    v_ing := round(greatest(v_pts, 0) * l.ingreso_por_punto, 2);
    insert into puntos_manager (partido_id, manager_id, puntos, ingreso, desglose)
    values (p_partido, fm.miembro_id, v_pts, v_ing, v_des);
    update fantasy_managers set puntos_totales = puntos_totales + v_pts, saldo = saldo + v_ing
     where liga_id = p.liga_id and miembro_id = fm.miembro_id;
    if v_ing > 0 then
      insert into transacciones_fantasy (liga_id, manager_id, partido_id, tipo, importe, saldo_despues)
      values (p.liga_id, fm.miembro_id, p_partido, 'ingreso_puntos', v_ing, fm.saldo + v_ing);
    end if;
  end loop;

  update partidos set jornada_liquidada = true where id = p_partido;
  perform recalcular_precios(p.liga_id, p_partido);
  return true;
end $$;

-- Engancha la liquidación al cierre del partido (calcular_puntos termina poniendo estado = 'cerrado')
create or replace function tras_cerrar_partido() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform liquidar_jornada(new.id);
  return null;
end $$;

create trigger t_liquidar_jornada after update of estado on partidos
  for each row when (new.estado = 'cerrado' and old.estado is distinct from 'cerrado')
  execute function tras_cerrar_partido();

-- ───────────── Vistas ─────────────
-- Vistas "de propietario" (sin security_invoker) para poder agregar plantillas ajenas sin exponerlas:
-- se filtran con es_miembro / mi_miembro.
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
       coalesce(h.n, 0) as num_plantillas,
       round(100.0 * coalesce(h.n, 0) / nullif((select count(*) from fantasy_managers f where f.liga_id = mj.liga_id), 0), 1)
         as pct_plantillas,
       exists (select 1 from plantillas pl where pl.manager_id = mi_miembro(mj.liga_id)
                 and pl.jugador_id = mj.miembro_id) as en_mi_plantilla,
       round(mj.precio * (1 - l.comision_venta), 2) as precio_venta
  from mercado_jugador mj
  join miembros m on m.id = mj.miembro_id
  join ligas l on l.id = mj.liga_id
  left join perfiles pe on pe.id = m.perfil_id
  left join valoracion_jugador vj on vj.liga_id = mj.liga_id and vj.miembro_id = mj.miembro_id
  left join (select jugador_id, count(*) n from plantillas group by jugador_id) h on h.jugador_id = mj.miembro_id
  left join lateral (select hp.precio from historial_precios hp
                      where hp.liga_id = mj.liga_id and hp.miembro_id = mj.miembro_id
                      order by hp.creado_en desc, hp.id desc offset 1 limit 1) prev on true
 where es_miembro(mj.liga_id) and m.estado in ('activo', 'pendiente_registro');

create view v_mi_plantilla as
select pl.liga_id, pl.jugador_id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional) as nombre,
       posicion_de(pl.jugador_id) as posicion,
       pl.precio_compra, mj.precio as precio_actual,
       round(mj.precio * (1 - l.comision_venta), 2) as precio_venta,
       mj.precio - pl.precio_compra as plusvalia,
       mj.no_habitual, pl.comprado_en,
       (select c.estado from partidos p join convocatorias c on c.partido_id = p.id and c.miembro_id = pl.jugador_id
         where p.liga_id = pl.liga_id and p.estado in ('abierto', 'completo', 'equipos_hechos')
         order by p.fecha_hora limit 1) as estado_proximo_partido
  from plantillas pl
  join miembros m on m.id = pl.jugador_id
  join ligas l on l.id = pl.liga_id
  left join perfiles pe on pe.id = m.perfil_id
  left join mercado_jugador mj on mj.liga_id = pl.liga_id and mj.miembro_id = pl.jugador_id
 where pl.manager_id = mi_miembro(pl.liga_id);

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
  left join (select pl.manager_id, sum(mj.precio) valor
               from plantillas pl join mercado_jugador mj on mj.liga_id = pl.liga_id and mj.miembro_id = pl.jugador_id
              group by pl.manager_id) v on v.manager_id = fm.miembro_id
 where es_miembro(fm.liga_id) and m.estado = 'activo';

-- Puntos de cada mánager por jornada (mejor alineación de la jornada = posicion 1)
create view v_jornada_managers as
select p.liga_id, pm.partido_id, p.fecha_hora, pm.manager_id,
       coalesce(pe.apodo, pe.nombre, m.nombre_provisional) as nombre,
       pm.puntos, pm.ingreso, pm.desglose,
       rank() over (partition by pm.partido_id order by pm.puntos desc) as posicion
  from puntos_manager pm
  join partidos p on p.id = pm.partido_id
  join miembros m on m.id = pm.manager_id
  left join perfiles pe on pe.id = m.perfil_id
 where es_miembro(p.liga_id);

-- Progreso de la encuesta (cuántos han respondido los 6 atributos), sin revelar respuestas
create view v_progreso_encuesta as
select e.id as encuesta_id, e.liga_id, e.sujeto_id, e.estado,
       (select count(*) from miembros m where m.liga_id = e.liga_id and m.estado = 'activo') as managers,
       (select count(*) from (select evaluador_id from respuestas_ranking r where r.encuesta_id = e.id
                               group by evaluador_id having count(distinct atributo) = 6) t) as completadas,
       (select array_agg(distinct atributo::text) from respuestas_ranking r
         where r.encuesta_id = e.id and r.evaluador_id = mi_miembro(e.liga_id)) as mis_atributos
  from encuestas_valoracion e
 where es_miembro(e.liga_id);

-- Rating para el generador de equipos: rating dinámico del mercado, o la encuesta, o 50
create view v_rating_balanceo as
select m.liga_id, m.id as miembro_id,
       coalesce(mj.rating, vj.general, 50) as rating,
       vj.general as rating_encuesta,
       coalesce(r.partidos, 0) as partidos
  from miembros m
  left join mercado_jugador mj on mj.liga_id = m.liga_id and mj.miembro_id = m.id
  left join valoracion_jugador vj on vj.liga_id = m.liga_id and vj.miembro_id = m.id
  left join (select pf.miembro_id, count(*) partidos from puntos_fantasy pf group by pf.miembro_id) r
    on r.miembro_id = m.id
 where es_miembro(m.liga_id) and m.estado in ('activo', 'pendiente_registro');
