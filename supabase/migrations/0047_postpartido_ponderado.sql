-- 0047 · Post-partido sin fricción: se consolida solo, ponderando, y solo se pregunta lo que está en conflicto.
--
--  · Cada parte pesa 1 (el de un admin, 1,5).
--  · Resultado de cada encuentro: si una mayoría (más de la mitad del peso) dice lo mismo, vale eso. Si no,
--    la mediana ponderada de cada marcador. Solo es conflicto si, sin mayoría, los partes difieren en 2 o más
--    goles o no se ponen de acuerdo en quién ganó. Con un solo parte, vale ese parte.
--  · Goles y asistencias de cada jugador: media ponderada de lo que dicen los partes (un valor «esperado»).
--    Después se reparte respetando el marcador: los goles de un equipo no pasan de los que marcó (menos los
--    autogoles a favor) y sus asistencias no pasan de sus goles. Si los partes suman de más se reduce en
--    proporción; si suman de menos, no se inventan goleadores. Reparto por restos mayores (enteros exactos).
--  · Conflicto de un jugador: solo si al menos 2 partes hablan de él y el valor final lo respalda la mitad
--    o menos del peso. El admin confirma con un toque (valor propuesto).
--  · Ya no hay «descuadres»: el reparto los evita.
--  · enviar_parte rechaza más asistencias que goles.

create or replace function peso_parte(p_partido uuid, p_reportero uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when exists (select 1 from miembros m join partidos p on p.liga_id = m.liga_id
                            where p.id = p_partido and m.id = p_reportero and m.rol = 'admin')
              then 1.5 else 1 end
$$;

create or replace function mediana_ponderada(p_v numeric[], p_w numeric[]) returns numeric
language sql immutable as $$
  select v from (select v, sum(w) over (order by v rows unbounded preceding) acum, sum(w) over () tot
                   from unnest(p_v, p_w) t(v, w) where v is not null) x
   where acum >= tot / 2 order by v limit 1
$$;

-- Reparte p_total unidades entre los «esperados» de tmp_reparto (restos mayores). Escribe tmp_reparto.valor.
create or replace function repartir_enteros(p_total int) returns void
language plpgsql as $$
declare v_s numeric; v_t int; v_f numeric;
begin
  select coalesce(sum(esperado), 0) into v_s from tmp_reparto;
  v_t := greatest(0, least(coalesce(p_total, round(v_s)::int), round(v_s)::int));
  v_f := case when v_s > v_t and v_s > 0 then v_t / v_s else 1 end;
  update tmp_reparto r set valor = x.base + case when x.rk <= x.resto then 1 else 0 end
    from (select miembro_id, floor(q)::int base,
                 row_number() over (order by q - floor(q) desc, q desc, miembro_id) rk,
                 v_t - sum(floor(q)::int) over () resto
            from (select miembro_id, esperado * v_f q from tmp_reparto) y) x
   where r.miembro_id = x.miembro_id;
end $$;

create or replace function consolidar_acta(p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare p partidos; e record; v_ne int; v_n int; v_tot numeric; v_top numeric; t_gl smallint; t_gv smallint;
        m_gl smallint; m_gv smallint; r_gl smallint; r_gv smallint; v_conf boolean; v_signo int; v_contra numeric;
        g record; v_cap int; v_fijos int; v_abiertas int; j record;
begin
  select * into p from partidos where id = p_partido for update;
  if auth.uid() is not null then perform exigir_admin(p.liga_id); end if;
  if p.estado not in ('post_partido', 'en_revision') then
    raise exception 'Solo se consolida tras el partido (estado actual: %)', p.estado;
  end if;
  delete from disputas where partido_id = p_partido and not resuelta;
  select count(*) into v_ne from encuentros where partido_id = p_partido;

  -- ───── 1) Resultado de cada encuentro
  for e in select * from encuentros where partido_id = p_partido order by n loop
    r_gl := valor_resuelto(p_partido, 'encuentro', e.n, null, 'goles_local');
    r_gv := valor_resuelto(p_partido, 'encuentro', e.n, null, 'goles_visitante');
    select count(*), sum(peso_parte(p_partido, reportero_id)) into v_n, v_tot
      from reportes_encuentro where partido_id = p_partido and n = e.n;
    v_conf := false; v_top := v_tot;
    if v_n = 0 then
      t_gl := null; t_gv := null;
      v_conf := r_gl is null or r_gv is null;          -- nadie lo ha puesto: hay que decirlo
    else
      select goles_local, goles_visitante, sum(peso_parte(p_partido, reportero_id))
        into t_gl, t_gv, v_top
        from reportes_encuentro where partido_id = p_partido and n = e.n
       group by goles_local, goles_visitante order by 3 desc, 1, 2 limit 1;
      if v_n > 1 and v_top <= v_tot / 2 then
        -- Sin mayoría: mediana ponderada de cada marcador
        select mediana_ponderada(array_agg(goles_local::numeric), array_agg(peso_parte(p_partido, reportero_id))),
               mediana_ponderada(array_agg(goles_visitante::numeric), array_agg(peso_parte(p_partido, reportero_id)))
          into m_gl, m_gv
          from reportes_encuentro where partido_id = p_partido and n = e.n;
        v_signo := sign(m_gl - m_gv);
        select coalesce(sum(peso_parte(p_partido, reportero_id)) filter (where sign(goles_local - goles_visitante) <> v_signo), 0)
          into v_contra from reportes_encuentro where partido_id = p_partido and n = e.n;
        v_conf := (select max(goles_local) - min(goles_local) >= 2 or max(goles_visitante) - min(goles_visitante) >= 2
                     from reportes_encuentro where partido_id = p_partido and n = e.n)
                  or v_contra >= v_tot / 3;
        t_gl := m_gl; t_gv := m_gv;
      end if;
    end if;
    if v_conf and r_gl is null then
      insert into disputas (partido_id, tipo, n, campo, valores, valor_propuesto, num_reportes)
      select p_partido, 'encuentro', e.n, 'goles_local', coalesce(jsonb_object_agg(v::text, c), '{}'), t_gl, v_n
        from (select goles_local v, count(*) c from reportes_encuentro where partido_id = p_partido and n = e.n group by 1) x;
    end if;
    if v_conf and r_gv is null then
      insert into disputas (partido_id, tipo, n, campo, valores, valor_propuesto, num_reportes)
      select p_partido, 'encuentro', e.n, 'goles_visitante', coalesce(jsonb_object_agg(v::text, c), '{}'), t_gv, v_n
        from (select goles_visitante v, count(*) c from reportes_encuentro where partido_id = p_partido and n = e.n group by 1) x;
    end if;
    update encuentros
       set goles_local = coalesce(r_gl, t_gl), goles_visitante = coalesce(r_gv, t_gv),
           confianza = case when v_tot > 0 then round(100 * v_top / v_tot, 2) end,
           num_reportes = v_n,
           en_disputa = v_conf and (r_gl is null or r_gv is null)
     where partido_id = p_partido and n = e.n;
  end loop;

  -- ───── 2) Datos de cada jugador: esperado ponderado y valores ya resueltos por el admin
  create temp table if not exists tmp_acta (
    miembro_id uuid primary key, equipo smallint, grupo smallint, n int,
    e_g numeric, e_a numeric, e_ag numeric, e_pp numeric, e_pf numeric, m_pc numeric,
    r_g smallint, r_a smallint, r_ag smallint, r_pc smallint, r_pp smallint, r_pf smallint,
    g int, a int, ag int, pc int, pp int, pf int) on commit drop;
  create temp table if not exists tmp_reparto (miembro_id uuid primary key, esperado numeric, valor int) on commit drop;
  delete from tmp_acta where true;

  insert into tmp_acta (miembro_id, equipo, grupo, n, e_g, e_a, e_ag, e_pp, e_pf, m_pc,
                        r_g, r_a, r_ag, r_pc, r_pp, r_pf)
  select c.miembro_id, c.equipo, case when v_ne = 1 then c.equipo else 0 end,
         count(rj.reportero_id),
         sum(rj.goles * w) / nullif(sum(w) filter (where rj.goles is not null), 0),
         sum(rj.asistencias * w) / nullif(sum(w) filter (where rj.asistencias is not null), 0),
         sum(rj.autogoles * w) / nullif(sum(w) filter (where rj.autogoles is not null), 0),
         sum(rj.penaltis_parados * w) / nullif(sum(w) filter (where rj.penaltis_parados is not null), 0),
         sum(rj.penaltis_fallados * w) / nullif(sum(w) filter (where rj.penaltis_fallados is not null), 0),
         mediana_ponderada(array_agg(rj.paradas_clave::numeric), array_agg(w)),
         valor_resuelto(p_partido, 'jugador', null, c.miembro_id, 'goles'),
         valor_resuelto(p_partido, 'jugador', null, c.miembro_id, 'asistencias'),
         valor_resuelto(p_partido, 'jugador', null, c.miembro_id, 'autogoles'),
         valor_resuelto(p_partido, 'jugador', null, c.miembro_id, 'paradas_clave'),
         valor_resuelto(p_partido, 'jugador', null, c.miembro_id, 'penaltis_parados'),
         valor_resuelto(p_partido, 'jugador', null, c.miembro_id, 'penaltis_fallados')
    from convocatorias c
    left join lateral (select r.*, peso_parte(p_partido, r.reportero_id) w from reportes_jugador r
                        where r.partido_id = p_partido and r.sujeto_id = c.miembro_id) rj on true
   where c.partido_id = p_partido and c.estado = 'confirmado' and c.equipo is not null
   group by c.miembro_id, c.equipo;

  update tmp_acta set ag = coalesce(r_ag, round(coalesce(e_ag, 0))),
                      pc = coalesce(r_pc, round(coalesce(m_pc, 0))),
                      pp = coalesce(r_pp, round(coalesce(e_pp, 0))),
                      pf = coalesce(r_pf, round(coalesce(e_pf, 0)))
   where true;

  -- ───── 3) Goles y asistencias repartidos respetando el marcador (por equipo; con varios encuentros, en total)
  for g in select distinct grupo from tmp_acta loop
    -- goles disponibles para los jugadores del grupo = marcador − autogoles de los rivales
    if v_ne = 1 then
      select case when e2.equipo_local = g.grupo then e2.goles_local else e2.goles_visitante end
        into v_cap from encuentros e2 where e2.partido_id = p_partido;
      v_cap := v_cap - (select coalesce(sum(ag), 0) from tmp_acta where grupo <> g.grupo);
    else
      select sum(goles_local + goles_visitante) into v_cap from encuentros where partido_id = p_partido;
      v_cap := v_cap - (select coalesce(sum(ag), 0) from tmp_acta);
    end if;
    select coalesce(sum(r_g), 0) into v_fijos from tmp_acta where grupo = g.grupo and r_g is not null;
    delete from tmp_reparto where true;
    insert into tmp_reparto select miembro_id, coalesce(e_g, 0), 0 from tmp_acta where grupo = g.grupo and r_g is null;
    perform repartir_enteros(case when v_cap is null then null else greatest(0, v_cap - v_fijos) end);
    update tmp_acta t set g = coalesce(t.r_g, x.valor)
      from (select ta.miembro_id, r.valor from tmp_acta ta left join tmp_reparto r using (miembro_id)
             where ta.grupo = g.grupo) x
     where t.miembro_id = x.miembro_id;

    -- asistencias: como mucho, una por gol de los jugadores del grupo
    select coalesce(sum(t.g), 0) into v_cap from tmp_acta t where t.grupo = g.grupo;
    select coalesce(sum(r_a), 0) into v_fijos from tmp_acta where grupo = g.grupo and r_a is not null;
    delete from tmp_reparto where true;
    insert into tmp_reparto select miembro_id, coalesce(e_a, 0), 0 from tmp_acta where grupo = g.grupo and r_a is null;
    perform repartir_enteros(greatest(0, v_cap - v_fijos));
    update tmp_acta t set a = coalesce(t.r_a, x.valor)
      from (select ta.miembro_id, r.valor from tmp_acta ta left join tmp_reparto r using (miembro_id)
             where ta.grupo = g.grupo) x
     where t.miembro_id = x.miembro_id;
  end loop;

  -- ───── 4) Conflictos de jugadores: ≥ 2 partes y el valor final lo respalda la mitad o menos del peso
  for j in select t.*,
                  (select sum(peso_parte(p_partido, r.reportero_id)) from reportes_jugador r
                    where r.partido_id = p_partido and r.sujeto_id = t.miembro_id) tot,
                  (select coalesce(sum(peso_parte(p_partido, r.reportero_id)), 0) from reportes_jugador r
                    where r.partido_id = p_partido and r.sujeto_id = t.miembro_id and r.goles = t.g) apoyo_g,
                  (select coalesce(sum(peso_parte(p_partido, r.reportero_id)), 0) from reportes_jugador r
                    where r.partido_id = p_partido and r.sujeto_id = t.miembro_id and r.asistencias = t.a) apoyo_a
             from tmp_acta t where t.n >= 2 loop
    if j.r_g is null and j.apoyo_g <= j.tot / 2 then
      insert into disputas (partido_id, tipo, sujeto_id, campo, valores, valor_propuesto, num_reportes)
      select p_partido, 'jugador', j.miembro_id, 'goles', coalesce(jsonb_object_agg(v::text, c), '{}'), j.g, j.n
        from (select goles v, count(*) c from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id
               and goles is not null group by 1) x;
    end if;
    if j.r_a is null and j.apoyo_a <= j.tot / 2 then
      insert into disputas (partido_id, tipo, sujeto_id, campo, valores, valor_propuesto, num_reportes)
      select p_partido, 'jugador', j.miembro_id, 'asistencias', coalesce(jsonb_object_agg(v::text, c), '{}'), j.a, j.n
        from (select asistencias v, count(*) c from reportes_jugador where partido_id = p_partido and sujeto_id = j.miembro_id
               and asistencias is not null group by 1) x;
    end if;
  end loop;

  -- ───── 5) Acta
  delete from acta_jugador where partido_id = p_partido;
  insert into acta_jugador (partido_id, miembro_id, goles, asistencias, autogoles, paradas_clave,
                            penaltis_parados, penaltis_fallados, porterias_cero, goles_encajados,
                            confianza, num_reportes, en_disputa)
  select p_partido, t.miembro_id, t.g, t.a, t.ag, t.pc, t.pp, t.pf,
         coalesce((select count(*) filter (where contra = 0) from (
                     select case when en.equipo_local = t.equipo then en.goles_visitante else en.goles_local end contra
                       from encuentros en where en.partido_id = p_partido
                        and t.equipo in (en.equipo_local, en.equipo_visitante)) z), 0),
         coalesce((select sum(contra) from (
                     select case when en.equipo_local = t.equipo then en.goles_visitante else en.goles_local end contra
                       from encuentros en where en.partido_id = p_partido
                        and t.equipo in (en.equipo_local, en.equipo_visitante)) z), 0),
         100, t.n,
         exists (select 1 from disputas d where d.partido_id = p_partido and not d.resuelta and d.sujeto_id = t.miembro_id)
    from tmp_acta t;

  select count(*) into v_abiertas from disputas where partido_id = p_partido and not resuelta;
  return v_abiertas;
end $$;

-- El admin confirma de una vez todo lo propuesto (valor propuesto de cada conflicto abierto) y se cierra.
create or replace function aceptar_propuestas(p_partido uuid) returns estado_partido
language plpgsql security definer set search_path = public as $$
declare p partidos; d disputas; v_m uuid;
begin
  select * into p from partidos where id = p_partido;
  if not found then raise exception 'Partido no encontrado'; end if;
  perform exigir_admin(p.liga_id);
  if p.estado not in ('post_partido', 'en_revision') then raise exception 'El acta ya está cerrada'; end if;
  v_m := mi_miembro(p.liga_id);
  for d in select * from disputas where partido_id = p_partido and not resuelta and tipo <> 'descuadre' loop
    if d.valor_propuesto is null then
      raise exception 'Falta el resultado de algún encuentro: indícalo a mano';
    end if;
    update disputas set resuelta = true, valor_final = d.valor_propuesto, resuelta_por = v_m, resuelta_en = now()
     where id = d.id;
  end loop;
  update disputas set resuelta = true, resuelta_por = v_m, resuelta_en = now()
   where partido_id = p_partido and not resuelta and tipo = 'descuadre';
  if p.estado = 'en_revision' then
    if consolidar_acta(p_partido) = 0 then
      perform calcular_puntos(p_partido);
      return 'cerrado';
    end if;
    return 'en_revision';
  end if;
  return cerrar_post_partido(p_partido);
end $$;

revoke execute on function peso_parte(uuid, uuid), repartir_enteros(int), aceptar_propuestas(uuid) from public, anon;
revoke execute on function peso_parte(uuid, uuid), repartir_enteros(int) from authenticated;
grant execute on function aceptar_propuestas(uuid) to authenticated;

-- enviar_parte (0018) + asistencias ≤ goles
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
