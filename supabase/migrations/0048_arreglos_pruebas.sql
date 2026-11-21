-- 0048 · Arreglos de la versión de pruebas
--  · enviar_parte: los DELETE de las tablas temporales llevan WHERE (la API exige WHERE en todo DELETE:
--    «DELETE requires a WHERE clause» al enviar el post-partido).
--  · Fotos de perfil: subir con «upsert» necesita poder leer el propio archivo; faltaba la política SELECT.

do $$ begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists avatares_leer on storage.objects;
    create policy avatares_leer on storage.objects for select to authenticated
      using (bucket_id = 'avatares' and (storage.foldername(name))[1] = auth.uid()::text);
  end if;
end $$;

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
  delete from tmp_parte_res where true; delete from tmp_parte_jug where true;

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
        -- 0047: cada asistencia es de un gol del equipo
        if (select coalesce(sum(asistencias), 0) from tmp_parte_jug where equipo = t)
           > v_res - (select coalesce(sum(autogoles), 0) from tmp_parte_jug where equipo = o) then
          raise exception 'Has puesto más asistencias al equipo % que goles marcó (%-%)', v_letra, v_gl, v_gv;
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
    if (select coalesce(sum(asistencias), 0) from tmp_parte_jug) > v_res then
      raise exception 'Has puesto más asistencias (%) que goles hubo (%)',
        (select coalesce(sum(asistencias), 0) from tmp_parte_jug), v_res;
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
