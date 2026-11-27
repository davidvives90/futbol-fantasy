-- 0061 · Bote de la porra (quiniela), apuestas públicas, presupuesto suficiente, logros de todas las ligas,
--        color y logotipo de la liga.

-- ───────────── Presupuesto: siempre da para la alineación completa + un 10 % ─────────────
-- Precio de referencia: el mayor entre el valor base y la mediana del mercado; con copias «rareza», ×1,25
-- (la primera copia cuesta ×1,5). Nunca baja de un presupuesto fijo que haya puesto el admin.
create or replace function presupuesto_liga(p_liga uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select greatest(
           coalesce(l.presupuesto_fijo, 0),
           ceil(l.jugadores_por_equipo
                * greatest(l.valor_base,
                           coalesce((select percentile_cont(0.5) within group (order by mj.precio)
                                       from mercado_jugador mj where mj.liga_id = l.id), 0)::numeric)
                * case when l.modo_copias = 'rareza' then 1.25 else 1 end
                * 1.10))
    from ligas l where l.id = p_liga
$$;

-- Ligas que se quedaron cortas: cada mánager recibe la diferencia
do $$
declare l record; fm record; v_nuevo numeric; v_dif numeric;
begin
  for l in select id, presupuesto_inicial from ligas where fantasy_activo and presupuesto_inicial is not null loop
    v_nuevo := presupuesto_liga(l.id);
    v_dif := v_nuevo - l.presupuesto_inicial;
    if v_dif > 0 then
      for fm in select miembro_id from fantasy_managers where liga_id = l.id loop
        perform mover_saldo(l.id, fm.miembro_id, v_dif, 'ajuste');
      end loop;
      update ligas set presupuesto_inicial = v_nuevo where id = l.id;
    end if;
  end loop;
end $$;

-- ───────────── Color y logotipo de la liga ─────────────
alter table ligas add column if not exists color text check (color is null or color ~ '^#[0-9A-Fa-f]{6}$'),
                  add column if not exists logo_url text;

create or replace function personalizar_liga(p_liga uuid, p_color text, p_logo_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform exigir_admin(p_liga);
  if p_color is not null and p_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Color no válido'; end if;
  if p_logo_url is not null and p_logo_url !~ '^https://' then raise exception 'Logotipo no válido'; end if;
  update ligas set color = upper(p_color), logo_url = p_logo_url where id = p_liga;
end $$;
revoke execute on function personalizar_liga(uuid, text, text) from public, anon;
grant execute on function personalizar_liga(uuid, text, text) to authenticated;

insert into storage.buckets (id, name, public) values ('logos', 'logos', true) on conflict (id) do nothing;
drop policy if exists logos_leer on storage.objects;
create policy logos_leer on storage.objects for select using (bucket_id = 'logos');
drop policy if exists logos_subir on storage.objects;
create policy logos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'logos' and es_admin(((storage.foldername(name))[1])::uuid));
drop policy if exists logos_cambiar on storage.objects;
create policy logos_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'logos' and es_admin(((storage.foldername(name))[1])::uuid));
drop policy if exists logos_borrar on storage.objects;
create policy logos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'logos' and es_admin(((storage.foldername(name))[1])::uuid));

-- ───────────── Logros de todas las ligas (las que compartes con el jugador), agrupados ─────────────
create or replace function logros_perfil(p_miembro uuid, p_idioma text default 'es') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_liga uuid; v_perfil uuid; v_idi text; v_ids uuid[]; v_met jsonb := '{}'; r record;
begin
  select liga_id, perfil_id into v_liga, v_perfil from miembros where id = p_miembro;
  if v_liga is null or not es_miembro(v_liga) then raise exception 'No perteneces a esta liga'; end if;
  v_idi := case when p_idioma in ('es', 'ca', 'gl', 'eu', 'en', 'de', 'it', 'nl', 'fr') then p_idioma else 'es' end;
  select array_agg(m.id) into v_ids from miembros m
   where (m.id = p_miembro or (v_perfil is not null and m.perfil_id = v_perfil)) and es_miembro(m.liga_id);
  -- El mejor valor de cada métrica entre todas sus ligas
  for r in select key, max(value::numeric) v from unnest(v_ids) i(id), jsonb_each_text(metricas_logros(i.id))
            where value ~ '^-?[0-9.]+$' group by key loop
    v_met := v_met || jsonb_build_object(r.key, r.v);
  end loop;
  return jsonb_build_object(
    'total', (select count(*) from logros_catalogo),
    'conseguidos', (select count(distinct l.tipo) from logros l join logros_catalogo c on c.codigo = l.tipo
                     where l.miembro_id = any(v_ids)),
    'ligas', (select count(*) from unnest(v_ids)),
    'logros', (select jsonb_agg(jsonb_build_object(
                 'codigo', c.codigo, 'familia', c.familia, 'categoria', c.categoria, 'emoji', c.emoji, 'nivel', c.nivel,
                 'umbral', c.umbral, 'oculto', c.oculto,
                 'nombre', f.nombre, 'nivel_nombre', nv.nombre, 'descripcion', f.descripcion || ': ' || c.umbral,
                 'valor', coalesce((v_met ->> c.familia)::numeric, 0),
                 'conseguido_en', (select min(l.conseguido_en) from logros l where l.miembro_id = any(v_ids) and l.tipo = c.codigo),
                 'en_ligas', (select coalesce(jsonb_agg(distinct g.nombre), '[]') from logros l
                                join miembros mm on mm.id = l.miembro_id join ligas g on g.id = mm.liga_id
                               where l.miembro_id = any(v_ids) and l.tipo = c.codigo),
                 'pct', null)
               order by c.orden)
                 from logros_catalogo c
                 join logros_familias_txt f on f.familia = c.familia and f.idioma = v_idi
                 join logros_niveles_txt nv on nv.nivel = c.nivel and nv.idioma = v_idi));
end $$;
grant execute on function logros_perfil(uuid, text) to authenticated;

-- ───────────── Porra: apuestas públicas ─────────────
drop policy if exists apuestas_leer on apuestas;
create policy apuestas_leer on apuestas for select using (es_miembro(liga_id));

-- ───────────── Bote (quiniela del partido) ─────────────
-- Cada mánager paga una entrada y pronostica el resultado. El bote = fondo acumulado de la liga + entradas.
--   · Resultado exacto (pleno): 70 % del bote, a partes iguales entre los que lo aciertan.
--   · Quién gana o empate (1X2): 30 %, entre todos los que lo aciertan (también los del pleno).
--   · Lo que nadie acierta se queda en el bote para el próximo partido.
-- La liga pone un fondo inicial (la mitad del valor base) la primera vez para que haya algo que ganar.
alter table ligas add column if not exists porra_entrada numeric(7,2) check (porra_entrada is null or porra_entrada > 0);

create table if not exists porra_botes (
  liga_id        uuid primary key references ligas on delete cascade,
  acumulado      numeric(10,2) not null default 0,
  fondo_inicial  numeric(10,2) not null default 0,
  creado_en      timestamptz not null default now()
);
create table if not exists quinielas (
  id             uuid primary key default gen_random_uuid(),
  partido_id     uuid not null references partidos on delete cascade,
  liga_id        uuid not null references ligas on delete cascade,
  miembro_id     uuid not null references miembros on delete cascade,
  goles1         smallint not null check (goles1 between 0 and 30),
  goles2         smallint not null check (goles2 between 0 and 30),
  importe        numeric(7,2) not null,
  acierto        text check (acierto in ('pleno', 'signo', 'nada', 'anulada')),
  premio         numeric(10,2) not null default 0,
  creada_en      timestamptz not null default now(),
  unique (partido_id, miembro_id)
);
create index if not exists quinielas_liga on quinielas (liga_id, miembro_id);
create table if not exists porra_bote_partidos (
  partido_id     uuid primary key references partidos on delete cascade,
  liga_id        uuid not null references ligas on delete cascade,
  bote           numeric(10,2) not null,
  entradas       numeric(10,2) not null,
  plenos         int not null,
  signos         int not null,
  premio_pleno   numeric(10,2) not null,
  premio_signo   numeric(10,2) not null,
  arrastre       numeric(10,2) not null,
  goles1         int, goles2 int,
  liquidado_en   timestamptz not null default now()
);
alter table porra_botes enable row level security;
alter table quinielas enable row level security;
alter table porra_bote_partidos enable row level security;
drop policy if exists porra_botes_leer on porra_botes;
create policy porra_botes_leer on porra_botes for select using (es_miembro(liga_id));
drop policy if exists quinielas_leer on quinielas;
create policy quinielas_leer on quinielas for select using (es_miembro(liga_id));
drop policy if exists porra_bote_partidos_leer on porra_bote_partidos;
create policy porra_bote_partidos_leer on porra_bote_partidos for select using (es_miembro(liga_id));
grant select on porra_botes, quinielas, porra_bote_partidos to authenticated;

create or replace function porra_entrada(p_liga uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select round(coalesce(porra_entrada, greatest(valor_base / 50, 0.5)), 2) from ligas where id = p_liga
$$;

-- El bote de la liga (lo crea con el fondo inicial si aún no existe)
create or replace function porra_bote_asegurar(p_liga uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare v numeric;
begin
  select acumulado into v from porra_botes where liga_id = p_liga;
  if found then return v; end if;
  select round(valor_base / 2, 2) into v from ligas where id = p_liga;
  insert into porra_botes (liga_id, acumulado, fondo_inicial) values (p_liga, v, v) on conflict (liga_id) do nothing;
  return (select acumulado from porra_botes where liga_id = p_liga);
end $$;
revoke execute on function porra_bote_asegurar(uuid) from public, anon, authenticated;

create or replace function jugar_quiniela(p_partido uuid, p_goles1 int, p_goles2 int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_m uuid; v_ent numeric; v_saldo numeric; q quinielas;
begin
  select * into p from partidos where id = p_partido;
  if not found or not es_miembro(p.liga_id) then raise exception 'No perteneces a esta liga'; end if;
  select * into l from ligas where id = p.liga_id;
  if l.porra_modo <> 'dinero' then raise exception 'El bote solo existe con la porra en dinero del Fantasy'; end if;
  if not porra_abierta(p_partido) then raise exception 'La porra de este partido está cerrada'; end if;
  if p_goles1 is null or p_goles2 is null or p_goles1 not between 0 and 30 or p_goles2 not between 0 and 30 then
    raise exception 'Pon un resultado válido';
  end if;
  v_m := mi_miembro(p.liga_id);
  select saldo into v_saldo from fantasy_managers where liga_id = l.id and miembro_id = v_m;
  if v_saldo is null then raise exception 'Entra en el Fantasy para jugar el bote'; end if;
  select * into q from quinielas where partido_id = p_partido and miembro_id = v_m for update;
  if found then
    update quinielas set goles1 = p_goles1, goles2 = p_goles2, creada_en = now() where id = q.id;
  else
    v_ent := porra_entrada(l.id);
    if v_saldo < v_ent then raise exception 'No tienes saldo suficiente: la entrada cuesta % M', v_ent; end if;
    perform porra_bote_asegurar(l.id);
    perform mover_saldo(l.id, v_m, -v_ent, 'porra_apuesta', null, p_partido);
    insert into quinielas (partido_id, liga_id, miembro_id, goles1, goles2, importe)
    values (p_partido, l.id, v_m, p_goles1, p_goles2, v_ent);
  end if;
  return porra_bote_json(p_partido);
end $$;
revoke execute on function jugar_quiniela(uuid, int, int) from public, anon;
grant execute on function jugar_quiniela(uuid, int, int) to authenticated;

create or replace function porra_bote_json(p_partido uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p partidos; l ligas; v_acum numeric; v_ent numeric; r porra_bote_partidos;
begin
  select * into p from partidos where id = p_partido;
  select * into l from ligas where id = p.liga_id;
  if l.porra_modo <> 'dinero' then return null; end if;
  select * into r from porra_bote_partidos where partido_id = p_partido;
  v_acum := coalesce((select acumulado from porra_botes where liga_id = l.id), round(l.valor_base / 2, 2));
  v_ent := coalesce((select sum(importe) from quinielas where partido_id = p_partido and acierto is distinct from 'anulada'), 0);
  return jsonb_build_object(
    'entrada', porra_entrada(l.id),
    'acumulado', case when r.partido_id is null then v_acum end,
    'entradas', v_ent,
    'total', coalesce(r.bote, v_acum + v_ent),
    'resultado', case when r.partido_id is not null then to_jsonb(r) end,
    'mia', (select jsonb_build_object('goles1', goles1, 'goles2', goles2, 'acierto', acierto, 'premio', premio)
              from quinielas where partido_id = p_partido and miembro_id = mi_miembro(l.id)),
    'quinielas', coalesce((select jsonb_agg(jsonb_build_object('miembro_id', miembro_id, 'nombre', nombre_miembro(miembro_id),
                                                               'goles1', goles1, 'goles2', goles2, 'acierto', acierto,
                                                               'premio', premio) order by premio desc, creada_en)
                             from quinielas where partido_id = p_partido), '[]'));
end $$;
grant execute on function porra_bote_json(uuid) to authenticated;

create or replace function liquidar_bote(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_g1 int; v_g2 int; v_signo text; v_bote numeric; v_ent numeric; v_plenos int; v_signos int;
        v_pp numeric := 0; v_ps numeric := 0; v_pagado numeric := 0; q record; v_premio numeric; v_acum numeric;
begin
  select * into p from partidos where id = p_partido;
  if not exists (select 1 from quinielas where partido_id = p_partido and acierto is null) then return 0; end if;
  select * into l from ligas where id = p.liga_id;
  if p.estado = 'cancelado' then
    for q in select * from quinielas where partido_id = p_partido and acierto is null loop
      if exists (select 1 from fantasy_managers where liga_id = q.liga_id and miembro_id = q.miembro_id) then
        perform mover_saldo(q.liga_id, q.miembro_id, q.importe, 'porra_devolucion', null, p_partido);
      end if;
      update quinielas set acierto = 'anulada', premio = q.importe where id = q.id;
    end loop;
    return 1;
  end if;
  if p.estado <> 'cerrado' then return 0; end if;

  select coalesce(sum(case when equipo_local = 1 then goles_local when equipo_visitante = 1 then goles_visitante else 0 end), 0),
         coalesce(sum(case when equipo_local = 2 then goles_local when equipo_visitante = 2 then goles_visitante else 0 end), 0)
    into v_g1, v_g2 from encuentros where partido_id = p_partido;
  v_signo := case when v_g1 > v_g2 then '1' when v_g1 = v_g2 then 'X' else '2' end;

  v_acum := porra_bote_asegurar(l.id);
  select sum(importe) into v_ent from quinielas where partido_id = p_partido and acierto is null;
  v_bote := v_acum + v_ent;
  update quinielas set acierto = case when goles1 = v_g1 and goles2 = v_g2 then 'pleno'
                                      when (case when goles1 > goles2 then '1' when goles1 = goles2 then 'X' else '2' end) = v_signo
                                        then 'signo' else 'nada' end
   where partido_id = p_partido and acierto is null;
  select count(*) filter (where acierto = 'pleno'), count(*) filter (where acierto in ('pleno', 'signo'))
    into v_plenos, v_signos from quinielas where partido_id = p_partido;
  if v_plenos > 0 then v_pp := floor(v_bote * 0.70 / v_plenos * 100) / 100; end if;
  if v_signos > 0 then v_ps := floor(v_bote * 0.30 / v_signos * 100) / 100; end if;

  for q in select * from quinielas where partido_id = p_partido and acierto in ('pleno', 'signo') loop
    v_premio := v_ps + case when q.acierto = 'pleno' then v_pp else 0 end;
    update quinielas set premio = v_premio where id = q.id;
    if exists (select 1 from fantasy_managers where liga_id = q.liga_id and miembro_id = q.miembro_id) then
      perform mover_saldo(q.liga_id, q.miembro_id, v_premio, 'porra_premio', null, p_partido);
    end if;
    v_pagado := v_pagado + v_premio;
  end loop;

  update porra_botes set acumulado = v_bote - v_pagado where liga_id = l.id;
  insert into porra_bote_partidos (partido_id, liga_id, bote, entradas, plenos, signos, premio_pleno, premio_signo, arrastre,
                                   goles1, goles2)
  values (p_partido, l.id, v_bote, v_ent, v_plenos, v_signos, v_pp, v_ps, v_bote - v_pagado, v_g1, v_g2)
  on conflict (partido_id) do nothing;

  if coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
    perform notificar((select coalesce(array_agg(m.perfil_id), '{}') from quinielas q2 join miembros m on m.id = q2.miembro_id
                        where q2.partido_id = p_partido and m.perfil_id is not null),
                      l.id, 'porra',
                      case when v_plenos > 0 then '💰 ¡Bote repartido!' when v_signos > 0 then '💰 Bote: premio por el 1X2'
                           else '💰 Bote desierto: se acumula' end,
                      case when v_plenos + v_signos = 0
                           then 'Nadie acertó el ' || v_g1 || '-' || v_g2 || '. El próximo partido hay ' || (v_bote - v_pagado) || ' M en juego'
                           else v_plenos || ' plenos y ' || v_signos || ' aciertos del 1X2 con el ' || v_g1 || '-' || v_g2
                                || '. Siguiente bote: ' || (v_bote - v_pagado) || ' M' end,
                      '/partidos/' || p_partido);
  end if;
  return 1;
end $$;
revoke execute on function liquidar_bote(uuid) from public, anon, authenticated;

create or replace function tras_estado_porra() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform liquidar_porra(new.id);
  perform liquidar_bote(new.id);
  return null;
end $$;

-- porra_partido: boletos de todos siempre visibles (son públicos) y el bote
create or replace function porra_partido(p_partido uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p partidos; l ligas; v_m uuid; v_abierta boolean;
begin
  select * into p from partidos where id = p_partido;
  if not found or not es_miembro(p.liga_id) then raise exception 'No perteneces a esta liga'; end if;
  select * into l from ligas where id = p.liga_id;
  v_m := mi_miembro(p.liga_id);
  v_abierta := porra_abierta(p_partido);
  if v_abierta then perform porra_calcular_cuotas(p_partido); end if;
  return jsonb_build_object(
    'activa', l.porra_activa, 'abierta', v_abierta, 'modo', l.porra_modo, 'tope', porra_tope(l.id),
    'motivo', case when not porra_global() then 'desactivada' when liga_con_menores(l.id) then 'menores' end,
    'max_ganancia', porra_ganancia_max(l.id),
    'apostado', coalesce((select sum(importe) from apuestas where partido_id = p_partido and miembro_id = v_m
                            and estado <> 'anulada'), 0),
    'saldo', (select saldo from fantasy_managers where liga_id = l.id and miembro_id = v_m),
    'cuotas', coalesce((select jsonb_agg(jsonb_build_object('mercado', mercado, 'seleccion', seleccion, 'cuota', cuota,
                                                            'prob', prob) order by mercado, cuota)
                          from porra_cuotas where partido_id = p_partido), '[]'),
    'mias', coalesce((select jsonb_agg(apuesta_json(a.id) order by a.creada_en desc)
                        from apuestas a where a.partido_id = p_partido and a.miembro_id = v_m), '[]'),
    'todas', coalesce((select jsonb_agg(apuesta_json(a.id) order by a.creada_en)
                         from apuestas a where a.partido_id = p_partido and a.miembro_id <> v_m), '[]'),
    'bote', porra_bote_json(p_partido));
end $$;

-- Resumen de cada jugador: boletos y bote
create or replace function ranking_porra(p_liga uuid, p_desde timestamptz default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with b as (
    select a.miembro_id, count(*) boletos, count(*) filter (where a.estado = 'ganada') aciertos,
           sum(a.retorno - a.importe) beneficio, sum(a.importe) apostado
      from apuestas a join partidos p on p.id = a.partido_id
     where a.liga_id = p_liga and a.estado in ('ganada', 'perdida', 'parcial')
       and (p_desde is null or p.fecha_hora >= p_desde)
     group by a.miembro_id),
  q as (
    select qq.miembro_id, count(*) quinielas, count(*) filter (where qq.acierto = 'pleno') plenos,
           count(*) filter (where qq.acierto in ('pleno', 'signo')) signos, sum(qq.premio - qq.importe) neto_bote,
           sum(qq.premio) premios_bote
      from quinielas qq join partidos p on p.id = qq.partido_id
     where qq.liga_id = p_liga and qq.acierto in ('pleno', 'signo', 'nada')
       and (p_desde is null or p.fecha_hora >= p_desde)
     group by qq.miembro_id)
  select case when not es_miembro(p_liga) then '[]'::jsonb else coalesce(jsonb_agg(x order by x.beneficio_total desc, x.aciertos desc), '[]') end
    from (select coalesce(b.miembro_id, q.miembro_id) miembro_id, nombre_miembro(coalesce(b.miembro_id, q.miembro_id)) nombre,
                 coalesce(b.boletos, 0) boletos, coalesce(b.aciertos, 0) aciertos,
                 round(coalesce(b.beneficio, 0), 2) beneficio, round(coalesce(b.apostado, 0), 2) apostado,
                 coalesce(q.quinielas, 0) quinielas, coalesce(q.plenos, 0) plenos, coalesce(q.signos, 0) signos,
                 round(coalesce(q.premios_bote, 0), 2) premios_bote,
                 round(coalesce(b.beneficio, 0) + coalesce(q.neto_bote, 0), 2) beneficio_total
            from b full join q on q.miembro_id = b.miembro_id) x
$$;
