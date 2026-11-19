-- 0018 · v0.3 · Verificación de goles contra el resultado + revisión de MVP (docs/v03_liga.md §6 y §7)
--
-- Regla: goles a favor del equipo A = Σ goles de los jugadores de A + Σ autogoles de los jugadores rivales,
-- y debe ser igual a los goles de A en el resultado. Con 3–4 equipos (varios encuentros) los goles de un jugador no
-- se pueden asignar a un encuentro concreto, así que se comprueba el total del partido:
-- Σ goles + Σ autogoles de todos = Σ goles de todos los encuentros.
--
-- Decisiones:
--  · enviar_parte valida SOLO el parte de quien lo envía (con su propio resultado; si no lo manda en la llamada, el
--    que ya tenga guardado). Los datos "no sé" (null) no suman; la igualdad exacta solo se exige cuando ha indicado
--    los goles de todos los jugadores del equipo y los autogoles de todos los rivales.
--  · En el acta consolidada, un descuadre abre una disputa tipo 'descuadre' (n = nº de equipo; campo
--    goles_equipo_<n>, o goles_total con varios encuentros; valores = {resultado, suma_jugadores}).
--    No se "resuelve" eligiendo valor: el admin corrige datos con fijar_dato y se cierra solo cuando cuadra.
--  · MVP (revisado, sin cambios en la regla): mayor nota con ≥ 3 votantes; desempate goles + asistencias; empate
--    persistente = compartido. v_mvps lista los MVP de cada partido.

-- ───────────── Disputas de tipo descuadre ─────────────
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.disputas'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) like '%tipo%' loop
    execute format('alter table disputas drop constraint %I', c.conname);
  end loop;
end $$;
alter table disputas
  add constraint disputas_tipo_ck check (tipo in ('encuentro', 'jugador', 'descuadre')),
  add constraint disputas_destino_ck check ((tipo = 'encuentro' and n is not null)
                                            or (tipo = 'jugador' and sujeto_id is not null)
                                            or tipo = 'descuadre');

-- Abre disputas de descuadre en el acta consolidada. Interna (la llama consolidar_acta).
create or replace function comprobar_descuadres(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_ne int; e encuentros; t smallint; v_res int; v_suma int; k int := 0; v_rep int;
begin
  select count(*) into v_ne from encuentros where partido_id = p_partido;
  if v_ne = 0 or exists (select 1 from encuentros where partido_id = p_partido
                                                  and (goles_local is null or goles_visitante is null)) then
    return 0;
  end if;
  select count(distinct reportero_id) into v_rep from reportes_encuentro where partido_id = p_partido;

  if v_ne = 1 then
    select * into e from encuentros where partido_id = p_partido;
    foreach t in array array[e.equipo_local, e.equipo_visitante] loop
      v_res := case when t = e.equipo_local then e.goles_local else e.goles_visitante end;
      select coalesce(sum(case when c.equipo = t then a.goles else 0 end), 0)
           + coalesce(sum(case when c.equipo <> t then a.autogoles else 0 end), 0)
        into v_suma
        from acta_jugador a
        join convocatorias c on c.partido_id = a.partido_id and c.miembro_id = a.miembro_id
       where a.partido_id = p_partido and c.equipo in (e.equipo_local, e.equipo_visitante);
      if v_suma <> v_res then
        insert into disputas (partido_id, tipo, n, campo, valores, valor_propuesto, num_reportes)
        values (p_partido, 'descuadre', t, 'goles_equipo_' || t,
                jsonb_build_object('resultado', v_res, 'suma_jugadores', v_suma), v_res, v_rep)
        on conflict do nothing;
        k := k + 1;
      end if;
    end loop;
  else
    select sum(goles_local + goles_visitante) into v_res from encuentros where partido_id = p_partido;
    select coalesce(sum(goles + autogoles), 0) into v_suma from acta_jugador where partido_id = p_partido;
    if v_suma <> v_res then
      insert into disputas (partido_id, tipo, n, campo, valores, valor_propuesto, num_reportes)
      values (p_partido, 'descuadre', null, 'goles_total',
              jsonb_build_object('resultado', v_res, 'suma_jugadores', v_suma), v_res, v_rep)
      on conflict do nothing;
      k := k + 1;
    end if;
  end if;
  return k;
end $$;

-- consolidar_acta: igual que 0004 + comprobación de descuadres al final
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

  -- 3) ¿Cuadran los goles de los jugadores con el resultado? (0018)
  perform comprobar_descuadres(p_partido);

  select count(*) into v_abiertas from disputas where partido_id = p_partido and not resuelta;
  return v_abiertas;
end $$;

-- resolver_disputa: igual que 0004, pero un descuadre no se resuelve eligiendo valor
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
  if d.tipo = 'descuadre' then
    raise exception 'Un descuadre no se resuelve eligiendo un valor: corrige los goles de los jugadores o el resultado (fijar_dato) y se cerrará solo';
  end if;

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

-- ───────────── Corrección de datos por el admin ─────────────
-- Fija el valor final de un dato (de un jugador o del resultado de un encuentro). Prevalece sobre el consenso.
-- Si el partido está en revisión, vuelve a consolidar y, si ya no quedan disputas, calcula los puntos.
-- Todos los parámetros tras p_partido llevan default (la app llama por nombre y omite p_sujeto o p_n)
create or replace function fijar_dato(p_partido uuid, p_sujeto uuid default null, p_n smallint default null,
                                      p_campo text default null, p_valor smallint default null)
returns estado_partido language plpgsql security definer set search_path = public as $$
declare p partidos; v_tipo text; d disputas; v_abiertas int;
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  perform exigir_admin(p.liga_id);
  if p.estado not in ('post_partido', 'en_revision') then raise exception 'El acta ya está cerrada'; end if;
  if p_valor is null or p_valor < 0 then raise exception 'Valor no válido'; end if;
  if p_campo is null then raise exception 'Indica qué dato corriges'; end if;

  if p_sujeto is not null then
    v_tipo := 'jugador';
    if p_campo not in ('goles', 'asistencias', 'autogoles', 'paradas_clave', 'penaltis_parados', 'penaltis_fallados') then
      raise exception 'Dato de jugador no válido: %', p_campo;
    end if;
    if not jugo_partido(p_partido, p_sujeto) then raise exception 'Ese jugador no jugó el partido'; end if;
  elsif p_n is not null then
    v_tipo := 'encuentro';
    if p_campo not in ('goles_local', 'goles_visitante') then
      raise exception 'Dato de encuentro no válido: %', p_campo;
    end if;
    if not exists (select 1 from encuentros where partido_id = p_partido and n = p_n) then
      raise exception 'Encuentro no encontrado';
    end if;
  else
    raise exception 'Indica el jugador o el encuentro';
  end if;

  select * into d from disputas
   where partido_id = p_partido and tipo = v_tipo and campo = p_campo
     and coalesce(n, 0) = coalesce(case when v_tipo = 'encuentro' then p_n end, 0)
     and sujeto_id is not distinct from (case when v_tipo = 'jugador' then p_sujeto end);
  delete from disputas
   where partido_id = p_partido and tipo = v_tipo and campo = p_campo
     and coalesce(n, 0) = coalesce(case when v_tipo = 'encuentro' then p_n end, 0)
     and sujeto_id is not distinct from (case when v_tipo = 'jugador' then p_sujeto end);
  insert into disputas (partido_id, tipo, n, sujeto_id, campo, valores, valor_propuesto, num_reportes,
                        resuelta, valor_final, resuelta_por, resuelta_en)
  values (p_partido, v_tipo, case when v_tipo = 'encuentro' then p_n end,
          case when v_tipo = 'jugador' then p_sujeto end, p_campo,
          coalesce(d.valores, '{}'::jsonb), d.valor_propuesto, coalesce(d.num_reportes, 0),
          true, p_valor, mi_miembro(p.liga_id), now());

  if p.estado = 'en_revision' then
    v_abiertas := consolidar_acta(p_partido);
    if v_abiertas = 0 then
      perform calcular_puntos(p_partido);
      return 'cerrado';
    end if;
  end if;
  return p.estado;
end $$;

-- Vuelve a consolidar y comprobar descuadres. Devuelve las disputas abiertas (en revisión, con 0 calcula puntos).
create or replace function revisar_descuadres(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; v int;
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  perform exigir_admin(p.liga_id);
  if p.estado not in ('post_partido', 'en_revision') then raise exception 'El acta ya está cerrada'; end if;
  v := consolidar_acta(p_partido);
  if p.estado = 'en_revision' and v = 0 then perform calcular_puntos(p_partido); end if;
  return v;
end $$;

-- ───────────── Parte del jugador con validación ─────────────
-- p_resultados: [{"n":1,"goles_local":2,"goles_visitante":1}, …]
-- p_jugadores:  [{"sujeto_id":"…","goles":1,"asistencias":0,"autogoles":0,"paradas_clave":null,
--                 "penaltis_parados":null,"penaltis_fallados":null}, …]   (null = "no sé")
create or replace function enviar_parte(p_partido uuid, p_resultados jsonb, p_jugadores jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; v_m uuid; v_ne int; e encuentros; t smallint; o smallint; v_gl int; v_gv int; v_res int;
        v_fav int; v_todos boolean; k int := 0; k2 int := 0; v_letra text;
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  v_m := mi_miembro(p.liga_id);
  if v_m is null then raise exception 'No perteneces a esta liga'; end if;
  if p.estado <> 'post_partido' then raise exception 'El partido no está en periodo de partes y valoraciones'; end if;

  create temp table if not exists tmp_parte_res (n smallint primary key, goles_local smallint, goles_visitante smallint)
    on commit drop;
  create temp table if not exists tmp_parte_jug (sujeto_id uuid primary key, equipo smallint, goles smallint,
    asistencias smallint, autogoles smallint, paradas_clave smallint, penaltis_parados smallint,
    penaltis_fallados smallint) on commit drop;
  delete from tmp_parte_res; delete from tmp_parte_jug;

  insert into tmp_parte_res
  select x.n, x.goles_local, x.goles_visitante
    from jsonb_to_recordset(coalesce(p_resultados, '[]'::jsonb))
         as x(n smallint, goles_local smallint, goles_visitante smallint);
  if exists (select 1 from tmp_parte_res r
              where not exists (select 1 from encuentros e2 where e2.partido_id = p_partido and e2.n = r.n)) then
    raise exception 'Encuentro no válido en el resultado';
  end if;
  if exists (select 1 from tmp_parte_res where goles_local is null or goles_visitante is null) then
    raise exception 'Indica el marcador completo de cada encuentro';
  end if;
  -- si no lo manda ahora, vale el resultado que ya tenga guardado
  insert into tmp_parte_res
  select r.n, r.goles_local, r.goles_visitante from reportes_encuentro r
   where r.partido_id = p_partido and r.reportero_id = v_m
  on conflict (n) do nothing;

  insert into tmp_parte_jug
  select x.sujeto_id, c.equipo, x.goles, x.asistencias, x.autogoles, x.paradas_clave, x.penaltis_parados,
         x.penaltis_fallados
    from jsonb_to_recordset(coalesce(p_jugadores, '[]'::jsonb))
         as x(sujeto_id uuid, goles smallint, asistencias smallint, autogoles smallint, paradas_clave smallint,
              penaltis_parados smallint, penaltis_fallados smallint)
    left join convocatorias c on c.partido_id = p_partido and c.miembro_id = x.sujeto_id
                             and c.estado = 'confirmado' and c.equipo is not null;
  if exists (select 1 from tmp_parte_jug where equipo is null) then
    raise exception 'Hay jugadores en el parte que no jugaron el partido';
  end if;

  -- Validación
  select count(*) into v_ne from encuentros where partido_id = p_partido;
  if v_ne = 1 then
    select * into e from encuentros where partido_id = p_partido;
    select goles_local, goles_visitante into v_gl, v_gv from tmp_parte_res where n = e.n;
    if v_gl is not null then
      foreach t in array array[e.equipo_local, e.equipo_visitante] loop
        o := case when t = e.equipo_local then e.equipo_visitante else e.equipo_local end;
        v_res := case when t = e.equipo_local then v_gl else v_gv end;
        v_letra := chr(64 + t);
        select coalesce(sum(goles) filter (where equipo = t), 0) + coalesce(sum(autogoles) filter (where equipo = o), 0)
          into v_fav from tmp_parte_jug;
        if v_fav > v_res then
          raise exception 'Has puesto % goles al equipo % pero el resultado que indicas es %-%', v_fav, v_letra, v_gl, v_gv;
        end if;
        select (select count(*) from convocatorias c where c.partido_id = p_partido and c.estado = 'confirmado' and c.equipo = t)
               = (select count(*) from tmp_parte_jug j where j.equipo = t and j.goles is not null)
           and (select count(*) from convocatorias c where c.partido_id = p_partido and c.estado = 'confirmado' and c.equipo = o)
               = (select count(*) from tmp_parte_jug j where j.equipo = o and j.autogoles is not null)
          into v_todos;
        if v_todos and v_fav <> v_res then
          raise exception 'La suma de goles del equipo % (%) no cuadra con el resultado que indicas (%-%)',
            v_letra, v_fav, v_gl, v_gv;
        end if;
      end loop;
    end if;
  elsif v_ne > 1 and (select count(*) from tmp_parte_res) = v_ne then
    select sum(goles_local + goles_visitante) into v_res from tmp_parte_res;
    select coalesce(sum(goles), 0) + coalesce(sum(autogoles), 0) into v_fav from tmp_parte_jug;
    if v_fav > v_res then
      raise exception 'Has puesto % goles en total pero en los resultados que indicas hay %', v_fav, v_res;
    end if;
    select (select count(*) from convocatorias c where c.partido_id = p_partido and c.estado = 'confirmado' and c.equipo is not null)
           = (select count(*) from tmp_parte_jug j where j.goles is not null and j.autogoles is not null)
      into v_todos;
    if v_todos and v_fav <> v_res then
      raise exception 'La suma de goles de los jugadores (%) no cuadra con los resultados que indicas (%)', v_fav, v_res;
    end if;
  end if;

  -- Guardado (los triggers validar_parte comprueban estado y asistencia)
  insert into reportes_encuentro (partido_id, n, reportero_id, goles_local, goles_visitante)
  select p_partido, x.n, v_m, x.goles_local, x.goles_visitante
    from jsonb_to_recordset(coalesce(p_resultados, '[]'::jsonb)) as x(n smallint, goles_local smallint, goles_visitante smallint)
  on conflict (partido_id, n, reportero_id) do update
    set goles_local = excluded.goles_local, goles_visitante = excluded.goles_visitante, creado_en = now();
  get diagnostics k = row_count;

  insert into reportes_jugador (partido_id, reportero_id, sujeto_id, goles, asistencias, autogoles, paradas_clave,
                                penaltis_parados, penaltis_fallados)
  select p_partido, v_m, j.sujeto_id, j.goles, j.asistencias, j.autogoles, j.paradas_clave, j.penaltis_parados,
         j.penaltis_fallados
    from tmp_parte_jug j
  on conflict (partido_id, reportero_id, sujeto_id) do update
    set goles = excluded.goles, asistencias = excluded.asistencias, autogoles = excluded.autogoles,
        paradas_clave = excluded.paradas_clave, penaltis_parados = excluded.penaltis_parados,
        penaltis_fallados = excluded.penaltis_fallados, creado_en = now();
  get diagnostics k2 = row_count;
  return k + k2;
end $$;

-- ───────────── MVP ─────────────
create view v_mvps with (security_invoker = true) as
select pf.partido_id, p.liga_id, p.fecha_hora, pf.miembro_id, pf.nota_media, pf.num_votantes, pf.total
  from puntos_fantasy pf
  join partidos p on p.id = pf.partido_id
 where pf.es_mvp;
