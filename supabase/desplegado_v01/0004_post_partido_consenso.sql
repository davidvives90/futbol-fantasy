-- 0004 · Post-partido: partes de los jugadores, valoraciones por aspectos y consolidación por consenso
--
-- Flujo:  equipos_hechos ──marcar_jugado()──▶ post_partido (ventana de N horas: cada asistente envía su parte)
--         ──cerrar_post_partido()──▶ consolidar_acta()
--              ├─ sin disputas ─▶ calcular_puntos() ─▶ cerrado
--              └─ con disputas ─▶ en_revision ──resolver_disputa() (admin) ×N──▶ calcular_puntos() ─▶ cerrado

-- ───────────── Tablas ─────────────
create table aspectos_valoracion (
  liga_id     uuid references ligas on delete cascade,
  clave       text check (clave ~ '^[a-z_]+$'),
  nombre      text not null,
  descripcion text,
  orden       smallint not null default 0,
  aplica_a    text not null default 'todos' check (aplica_a in ('todos', 'porteros', 'campo')),
  activo      boolean not null default true,
  primary key (liga_id, clave)
);

-- Resultado que cada reportero cree que hubo en cada encuentro
create table reportes_encuentro (
  partido_id      uuid not null,
  n               smallint not null,
  reportero_id    uuid not null references miembros on delete cascade,
  goles_local     smallint not null check (goles_local between 0 and 99),
  goles_visitante smallint not null check (goles_visitante between 0 and 99),
  creado_en       timestamptz not null default now(),
  primary key (partido_id, n, reportero_id),
  foreign key (partido_id, n) references encuentros on delete cascade
);

-- Lo que cada reportero recuerda de cada jugador. null = "no lo sé".
create table reportes_jugador (
  partido_id        uuid not null references partidos on delete cascade,
  reportero_id      uuid not null references miembros on delete cascade,
  sujeto_id         uuid not null references miembros on delete cascade,
  goles             smallint check (goles between 0 and 50),
  asistencias       smallint check (asistencias between 0 and 50),
  autogoles         smallint check (autogoles between 0 and 20),
  paradas_clave     smallint check (paradas_clave between 0 and 50),
  penaltis_parados  smallint check (penaltis_parados between 0 and 10),
  penaltis_fallados smallint check (penaltis_fallados between 0 and 10),
  creado_en         timestamptz not null default now(),
  primary key (partido_id, reportero_id, sujeto_id)
);

-- Valoraciones subjetivas por aspecto, anónimas (nadie lee las ajenas; solo se publican medias)
create table valoraciones (
  partido_id uuid not null references partidos on delete cascade,
  liga_id    uuid not null,                       -- lo rellena el trigger
  votante_id uuid not null references miembros on delete cascade,
  votado_id  uuid not null references miembros on delete cascade,
  aspecto    text not null,
  nota       smallint not null check (nota between 1 and 10),
  creado_en  timestamptz not null default now(),
  primary key (partido_id, votante_id, votado_id, aspecto),
  foreign key (liga_id, aspecto) references aspectos_valoracion (liga_id, clave),
  check (votante_id <> votado_id)
);

create table disputas (
  id            uuid primary key default gen_random_uuid(),
  partido_id    uuid not null references partidos on delete cascade,
  tipo          text not null check (tipo in ('encuentro', 'jugador')),
  n             smallint,                 -- encuentro (tipo = 'encuentro')
  sujeto_id     uuid references miembros on delete cascade,   -- jugador (tipo = 'jugador')
  campo         text not null,            -- goles_local, goles, asistencias...
  valores       jsonb not null,           -- {"2": 5, "3": 1}: valor reportado → nº de reportes
  valor_propuesto smallint,               -- el que saldría por consenso
  num_reportes  int not null,
  resuelta      boolean not null default false,
  valor_final   smallint,
  resuelta_por  uuid references miembros on delete set null,
  resuelta_en   timestamptz,
  creada_en     timestamptz not null default now(),
  check ((tipo = 'encuentro' and n is not null) or (tipo = 'jugador' and sujeto_id is not null))
);
create unique index disputas_unica on disputas
  (partido_id, tipo, coalesce(n, 0), coalesce(sujeto_id, '00000000-0000-0000-0000-000000000000'), campo);

create index on reportes_jugador (partido_id, sujeto_id);
create index on valoraciones (partido_id, votado_id);

-- ───────────── Validación de partes y valoraciones ─────────────
-- ¿Puede este miembro enviar parte de este partido? Asistente confirmado, o admin de la liga.
create or replace function puede_reportar(p_partido uuid, p_miembro uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from convocatorias
                  where partido_id = p_partido and miembro_id = p_miembro and estado = 'confirmado')
      or exists (select 1 from miembros m join partidos p on p.liga_id = m.liga_id
                  where p.id = p_partido and m.id = p_miembro and m.rol = 'admin' and m.estado = 'activo')
$$;

create or replace function jugo_partido(p_partido uuid, p_miembro uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from convocatorias
                  where partido_id = p_partido and miembro_id = p_miembro
                    and estado = 'confirmado' and equipo is not null)
$$;

create or replace function validar_parte() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_estado estado_partido; v_aplica text; v_pos posicion_campo;
begin
  select estado into v_estado from partidos where id = new.partido_id;
  if v_estado <> 'post_partido' then
    raise exception 'El partido no está en periodo de partes y valoraciones';
  end if;

  if tg_table_name = 'valoraciones' then
    if not jugo_partido(new.partido_id, new.votante_id) then
      raise exception 'Solo valoran quienes jugaron el partido';
    end if;
    if not jugo_partido(new.partido_id, new.votado_id) then
      raise exception 'Ese jugador no jugó el partido';
    end if;
    new.liga_id := liga_de_partido(new.partido_id);
    select aplica_a into v_aplica from aspectos_valoracion
     where liga_id = new.liga_id and clave = new.aspecto and activo;
    if v_aplica is null then raise exception 'Aspecto de valoración no válido'; end if;
    v_pos := posicion_de(new.votado_id);
    if (v_aplica = 'porteros' and v_pos is distinct from 'portero')
       or (v_aplica = 'campo' and v_pos = 'portero') then
      raise exception 'El aspecto % no se aplica a este jugador', new.aspecto;
    end if;
  elsif tg_table_name = 'reportes_jugador' then
    if not puede_reportar(new.partido_id, new.reportero_id) then
      raise exception 'Solo envían parte los asistentes o un administrador';
    end if;
    if not jugo_partido(new.partido_id, new.sujeto_id) then
      raise exception 'Ese jugador no jugó el partido';
    end if;
  else -- reportes_encuentro
    if not puede_reportar(new.partido_id, new.reportero_id) then
      raise exception 'Solo envían parte los asistentes o un administrador';
    end if;
  end if;
  return new;
end $$;

create trigger t_validar before insert or update on reportes_encuentro
  for each row execute function validar_parte();
create trigger t_validar before insert or update on reportes_jugador
  for each row execute function validar_parte();
create trigger t_validar before insert or update on valoraciones
  for each row execute function validar_parte();

-- ───────────── Consenso ─────────────
-- Moda de los valores no nulos (empate de modas → mediana redondeada de todos);
-- con p_mediana = true usa directamente la mediana (para conteos dispersos como paradas).
-- confianza = % de reportes que coinciden con el valor elegido.
create or replace function consenso(p_vals smallint[], p_mediana boolean default false,
                                    out valor smallint, out confianza numeric, out n int, out conteo jsonb)
language plpgsql immutable as $$
declare v_top int; v_modas int;
begin
  select count(*)::int into n from unnest(p_vals) v where v is not null;
  if n = 0 then valor := null; confianza := null; conteo := '{}'; return; end if;

  select jsonb_object_agg(v::text, c) into conteo
    from (select v, count(*) c from unnest(p_vals) v where v is not null group by v) t;

  if not p_mediana then
    select max(c) into v_top
      from (select count(*) c from unnest(p_vals) v where v is not null group by v) t;
    select count(*) into v_modas
      from (select count(*) c from unnest(p_vals) v where v is not null group by v) t where c = v_top;
    if v_modas = 1 then
      select v into valor from unnest(p_vals) v where v is not null
       group by v order by count(*) desc limit 1;
    end if;
  end if;

  if valor is null then
    select round(percentile_cont(0.5) within group (order by v))::smallint into valor
      from unnest(p_vals) v where v is not null;
  end if;

  confianza := round(100.0 * (select count(*) from unnest(p_vals) v where v = valor) / n, 2);
end $$;

-- Valor ya decidido por un admin para un campo (tiene prioridad sobre el consenso)
create or replace function valor_resuelto(p_partido uuid, p_tipo text, p_n smallint, p_sujeto uuid, p_campo text)
returns smallint language sql stable security definer set search_path = public as $$
  select valor_final from disputas
   where partido_id = p_partido and tipo = p_tipo and campo = p_campo and resuelta
     and coalesce(n, 0) = coalesce(p_n, 0)
     and coalesce(sujeto_id, '00000000-0000-0000-0000-000000000000')
         = coalesce(p_sujeto, '00000000-0000-0000-0000-000000000000')
$$;

-- Decide el valor de un campo y abre disputa si no hay acuerdo suficiente.
-- Reglas de disputa:
--   · resultado de un encuentro: menos de 3 partes o confianza < 60 %
--   · conteos por mediana (paradas): solo si 1-2 partes dicen algo distinto de 0
--   · dato de un jugador: nadie lo indica → 0 sin disputa; 1-2 partes que dicen algo distinto de 0 → disputa
--     (hace falta corroborarlo); 3 o más partes con confianza < 60 % → disputa
create or replace function decidir_campo(p_partido uuid, p_tipo text, p_n smallint, p_sujeto uuid,
                                         p_campo text, p_vals smallint[], p_mediana boolean default false,
                                         out valor smallint, out confianza numeric, out n int, out disputado boolean)
language plpgsql security definer set search_path = public as $$
declare c record; v_res smallint;
begin
  c := consenso(p_vals, p_mediana);
  n := c.n; confianza := c.confianza; valor := coalesce(c.valor, 0); disputado := false;

  v_res := valor_resuelto(p_partido, p_tipo, p_n, p_sujeto, p_campo);
  if v_res is not null then valor := v_res; confianza := 100; return; end if;

  if p_tipo = 'encuentro' then
    disputado := c.n < 3 or c.confianza < 60;
  elsif p_mediana then
    -- conteos aproximados (paradas): la dispersión es normal, solo se exige corroboración
    disputado := c.n between 1 and 2 and c.valor <> 0;
  else
    disputado := (c.n between 1 and 2 and c.valor <> 0) or (c.n >= 3 and c.confianza < 60);
  end if;

  if disputado then
    insert into disputas (partido_id, tipo, n, sujeto_id, campo, valores, valor_propuesto, num_reportes)
    values (p_partido, p_tipo, p_n, p_sujeto, p_campo, c.conteo, c.valor, c.n);
  end if;
end $$;

-- Consolida el acta a partir de todos los partes. Recalculable. Devuelve nº de disputas abiertas.
create or replace function consolidar_acta(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; e record; j record; gl record; gv record;
        f_g record; f_a record; f_ag record; f_pc record; f_pp record; f_pf record;
        v_abiertas int;
begin
  select * into p from partidos where id = p_partido for update;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado not in ('post_partido', 'en_revision') then
    raise exception 'Solo se consolida tras el partido (estado actual: %)', p.estado;
  end if;

  delete from disputas where partido_id = p_partido and not resuelta;

  -- 1) Resultado de cada encuentro
  for e in select * from encuentros where partido_id = p_partido order by n loop
    gl := decidir_campo(p_partido, 'encuentro', e.n, null, 'goles_local',
            (select array_agg(goles_local) from reportes_encuentro where partido_id = p_partido and n = e.n));
    gv := decidir_campo(p_partido, 'encuentro', e.n, null, 'goles_visitante',
            (select array_agg(goles_visitante) from reportes_encuentro where partido_id = p_partido and n = e.n));
    update encuentros
       set goles_local = gl.valor, goles_visitante = gv.valor,
           confianza = least(gl.confianza, gv.confianza),
           num_reportes = greatest(gl.n, gv.n),
           en_disputa = gl.disputado or gv.disputado
     where partido_id = p_partido and n = e.n;
  end loop;

  -- 2) Datos de cada jugador
  delete from acta_jugador where partido_id = p_partido;
  for j in select c.miembro_id, c.equipo from convocatorias c
            where c.partido_id = p_partido and c.estado = 'confirmado' and c.equipo is not null loop
    f_g  := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'goles',
              (select array_agg(goles) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id));
    f_a  := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'asistencias',
              (select array_agg(asistencias) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id));
    f_ag := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'autogoles',
              (select array_agg(autogoles) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id));
    f_pc := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'paradas_clave',
              (select array_agg(paradas_clave) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id),
              true);   -- mediana: nadie cuenta las paradas igual
    f_pp := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'penaltis_parados',
              (select array_agg(penaltis_parados) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id));
    f_pf := decidir_campo(p_partido, 'jugador', null, j.miembro_id, 'penaltis_fallados',
              (select array_agg(penaltis_fallados) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id));

    insert into acta_jugador (partido_id, miembro_id, goles, asistencias, autogoles, paradas_clave,
                              penaltis_parados, penaltis_fallados, porterias_cero, goles_encajados,
                              confianza, num_reportes, en_disputa)
    select p_partido, j.miembro_id, f_g.valor, f_a.valor, f_ag.valor, f_pc.valor, f_pp.valor, f_pf.valor,
           coalesce(count(*) filter (where contra = 0), 0),
           coalesce(sum(contra), 0),
           (select min(x) from unnest(array[f_g.confianza, f_a.confianza, f_ag.confianza,
                                            f_pp.confianza, f_pf.confianza]) x),
           (select count(*) from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id),
           f_g.disputado or f_a.disputado or f_ag.disputado or f_pc.disputado or f_pp.disputado or f_pf.disputado
      from (select case when en.equipo_local = j.equipo then en.goles_visitante else en.goles_local end as contra
              from encuentros en
             where en.partido_id = p_partido and j.equipo in (en.equipo_local, en.equipo_visitante)) t;
  end loop;

  select count(*) into v_abiertas from disputas where partido_id = p_partido and not resuelta;
  return v_abiertas;
end $$;

-- ───────────── Transiciones del partido ─────────────
-- Admin: el partido se ha jugado → genera cargos y abre la ventana de partes y valoraciones
create or replace function marcar_jugado(p_partido uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p partidos; v_horas int;
begin
  select * into p from partidos where id = p_partido for update;
  perform exigir_admin(p.liga_id);
  if p.estado <> 'equipos_hechos' then raise exception 'Primero hay que confirmar los equipos'; end if;
  if not exists (select 1 from encuentros where partido_id = p_partido) then
    raise exception 'Define los encuentros (quién juega contra quién) antes de cerrar el partido';
  end if;
  select horas_post_partido into v_horas from ligas where id = p.liga_id;

  update partidos set estado = 'jugado' where id = p_partido;
  perform generar_cargos(p_partido);
  update partidos set estado = 'post_partido', votacion_cierra = now() + make_interval(hours => v_horas)
   where id = p_partido;
end $$;

-- Cierre de la ventana (admin o tarea programada): consolida; si hay disputas pasa a revisión
create or replace function cerrar_post_partido(p_partido uuid) returns estado_partido
language plpgsql security definer set search_path = public as $$
declare p partidos; v_abiertas int;
begin
  select * into p from partidos where id = p_partido;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado <> 'post_partido' then raise exception 'El partido no está en periodo post-partido'; end if;

  v_abiertas := consolidar_acta(p_partido);
  if v_abiertas > 0 then
    update partidos set estado = 'en_revision' where id = p_partido;
    -- TODO push a los admins: "Hay % datos sin acuerdo en el partido"
    return 'en_revision';
  end if;
  perform calcular_puntos(p_partido);
  return 'cerrado';
end $$;

-- Admin decide el valor de un dato en disputa. Al resolver la última, se calculan los puntos.
create or replace function resolver_disputa(p_disputa uuid, p_valor smallint) returns estado_partido
language plpgsql security definer set search_path = public as $$
declare d disputas; p partidos; v_abiertas int;
begin
  select * into d from disputas where id = p_disputa;
  if not found then raise exception 'Disputa no encontrada'; end if;
  select * into p from partidos where id = d.partido_id;
  perform exigir_admin(p.liga_id);
  if p.estado not in ('post_partido', 'en_revision') then raise exception 'El acta ya está cerrada'; end if;
  if p_valor < 0 then raise exception 'Valor no válido'; end if;

  update disputas set resuelta = true, valor_final = p_valor,
                      resuelta_por = mi_miembro(p.liga_id), resuelta_en = now()
   where id = p_disputa;

  if p.estado = 'en_revision' then
    v_abiertas := consolidar_acta(p.id);     -- aplica los valores resueltos
    if v_abiertas = 0 then
      perform calcular_puntos(p.id);
      return 'cerrado';
    end if;
  end if;
  return p.estado;
end $$;

-- Para pg_cron / Edge Function: cierra todas las ventanas vencidas
create or replace function cerrar_ventanas_vencidas() returns int
language plpgsql security definer set search_path = public as $$
declare r record; k int := 0;
begin
  for r in select id from partidos where estado = 'post_partido' and votacion_cierra <= now() loop
    perform cerrar_post_partido(r.id);
    k := k + 1;
  end loop;
  return k;
end $$;
-- En Supabase:  select cron.schedule('cerrar-post-partido', '*/15 * * * *', 'select cerrar_ventanas_vencidas()');

-- ───────────── Vistas de control ─────────────
-- Progreso de la ventana post-partido (cuántos han enviado parte y valoraciones), sin revelar contenido
create view v_progreso_post_partido as
select p.id as partido_id,
       (select count(*) from convocatorias c where c.partido_id = p.id and c.estado = 'confirmado' and c.equipo is not null) as asistentes,
       (select count(distinct reportero_id) from reportes_encuentro r where r.partido_id = p.id) as partes_resultado,
       (select count(distinct reportero_id) from reportes_jugador r where r.partido_id = p.id) as partes_jugadores,
       (select count(distinct votante_id) from valoraciones v where v.partido_id = p.id) as votantes,
       p.votacion_cierra
  from partidos p
 where es_miembro(p.liga_id);

-- ¿Cuadran los goles de los jugadores con el resultado? (solo partidos de un único encuentro)
create view v_descuadres as
select e.partido_id, e.goles_local, e.goles_visitante,
       sum(case when c.equipo = e.equipo_local then a.goles else 0 end)
     + sum(case when c.equipo = e.equipo_visitante then a.autogoles else 0 end) as goles_local_jugadores,
       sum(case when c.equipo = e.equipo_visitante then a.goles else 0 end)
     + sum(case when c.equipo = e.equipo_local then a.autogoles else 0 end) as goles_visitante_jugadores
  from encuentros e
  join convocatorias c on c.partido_id = e.partido_id and c.estado = 'confirmado'
  join acta_jugador a on a.partido_id = c.partido_id and a.miembro_id = c.miembro_id
 where es_miembro(liga_de_partido(e.partido_id))
   and (select count(*) from encuentros e2 where e2.partido_id = e.partido_id) = 1
 group by e.partido_id, e.goles_local, e.goles_visitante;

-- Fiabilidad de cada reportero: % de sus datos que coinciden con el acta final (partidos cerrados).
-- security_invoker: cada jugador ve la suya; los admins, la de toda la liga.
-- TODO: usarla para ponderar votos (p. ej. peso 0,5 a reporteros con fiabilidad < 50 %).
create view v_fiabilidad with (security_invoker = true) as
with datos as (
  select r.reportero_id, (r.goles_local = e.goles_local)::int + (r.goles_visitante = e.goles_visitante)::int as aciertos, 2 as total
    from reportes_encuentro r
    join encuentros e using (partido_id, n)
    join partidos p on p.id = r.partido_id and p.estado = 'cerrado'
  union all
  select r.reportero_id,
         coalesce((r.goles = a.goles)::int, 0) + coalesce((r.asistencias = a.asistencias)::int, 0)
         + coalesce((r.autogoles = a.autogoles)::int, 0),
         (r.goles is not null)::int + (r.asistencias is not null)::int + (r.autogoles is not null)::int
    from reportes_jugador r
    join acta_jugador a on a.partido_id = r.partido_id and a.miembro_id = r.sujeto_id
    join partidos p on p.id = r.partido_id and p.estado = 'cerrado'
)
select m.liga_id, d.reportero_id as miembro_id,
       sum(d.total) as datos_reportados,
       round(100.0 * sum(d.aciertos) / nullif(sum(d.total), 0), 1) as pct_acierto
  from datos d join miembros m on m.id = d.reportero_id
 group by m.liga_id, d.reportero_id;
