-- 0013 · Roles en la alineación, liquidación con cesiones y precios sin rendimiento hasta 3 partidos
-- (ampliación 0.2, docs/mercado_fantasy.md §9.5, §10.2 y §2 modificado)
--
-- Decisiones:
--  · alineaciones.rol: POR | DEF | MED | DEL. Las filas existentes reciben POR (el primero por jugador_id de cada
--    alineación) y MED el resto.
--  · guardar_alineacion pasa a tener p_roles text[] opcional (por defecto: el primero POR, el resto MED). Se borra
--    la firma de 2 parámetros para que una llamada con nombre desde la app 0.1 no sea ambigua.
--  · Exactamente 1 POR si la alineación tiene al menos un jugador.
--  · El bonus de rol solo se suma si el jugador jugó (tiene puntos ese partido) y se multiplica, igual que sus puntos,
--    por el ×1,5 de no habitual.
--  · "Menos goleado": media de goles encajados por encuentro de su equipo = la mínima del partido (empates: todos).
--  · Al congelar (cierre de alineaciones = cierre del mercado) se retiran las cesiones ofrecidas sin aceptar de ese
--    partido y caducan todas las ofertas pendientes de la liga.
--  · Tras liquidar: cesiones aceptadas → finalizada (la ficha vuelve al dueño), protección −1 jornada,
--    cláusulas por debajo del nuevo precio se suben al precio, y C se recalcula (solo al alza).
--  · Demanda para el precio: d = fichas con dueño / C (antes: plantillas / mánagers).

-- ───────────── Roles ─────────────
alter table alineaciones
  add column rol       text not null default 'MED' check (rol in ('POR', 'DEF', 'MED', 'DEL')),
  add column bonus_rol numeric(6,2);

update alineaciones a set rol = 'POR'
  from (select distinct on (partido_id, manager_id) partido_id, manager_id, jugador_id
          from alineaciones order by partido_id, manager_id, jugador_id) x
 where a.partido_id = x.partido_id and a.manager_id = x.manager_id and a.jugador_id = x.jugador_id;

-- ───────────── Guardar alineación ─────────────
drop function if exists guardar_alineacion(uuid, uuid[]);

create or replace function guardar_alineacion(p_partido uuid, p_jugadores uuid[], p_roles text[] default null)
returns int language plpgsql security definer set search_path = public as $$
declare p partidos; v_m uuid; v_tam int; v_n int; v_roles text[];
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

  -- Fichas propias que he cedido para ese partido: no las puedo alinear
  if exists (select 1 from unnest(p_jugadores) x
               join fichas f on f.jugador_id = x and f.propietario_id = v_m
               join cesiones c on c.ficha_id = f.id and c.estado = 'aceptada') then
    raise exception 'Ese jugador está cedido esta jornada: no puedes alinearlo';
  end if;
  -- Cada jugador: ficha propia, o la ficha recibida en cesión para este partido
  if exists (select 1 from unnest(p_jugadores) x
              where not exists (select 1 from fichas f where f.propietario_id = v_m and f.jugador_id = x)
                and not exists (select 1 from cesiones c join fichas f on f.id = c.ficha_id
                                 where c.cesionario_id = v_m and c.partido_id = p_partido
                                   and c.estado = 'aceptada' and f.jugador_id = x)) then
    raise exception 'Solo puedes alinear jugadores de tu plantilla (o el que tengas cedido esta jornada)';
  end if;

  if p_roles is null then
    v_roles := array(select case when k = 1 then 'POR' else 'MED' end from generate_series(1, v_n) k);
  else
    if coalesce(array_length(p_roles, 1), 0) <> v_n then
      raise exception 'Hay que indicar un rol por jugador (POR, DEF, MED o DEL)';
    end if;
    v_roles := array(select upper(trim(r)) from unnest(p_roles) r);
    if exists (select 1 from unnest(v_roles) r where r is null or r not in ('POR', 'DEF', 'MED', 'DEL')) then
      raise exception 'Rol no válido: usa POR, DEF, MED o DEL';
    end if;
  end if;
  if v_n >= 1 and (select count(*) from unnest(v_roles) r where r = 'POR') <> 1 then
    raise exception 'La alineación lleva exactamente un portero (POR)';
  end if;

  delete from alineaciones where partido_id = p_partido and manager_id = v_m;
  insert into alineaciones (partido_id, manager_id, jugador_id, rol)
  select p_partido, v_m, t.x, v_roles[t.k] from unnest(p_jugadores) with ordinality as t(x, k);
  return v_n;
end $$;

-- ───────────── Congelación (cierre de alineaciones y del mercado) ─────────────
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

  -- Se cierra el mercado: cesiones sin aceptar de este partido se retiran y las ofertas pendientes caducan
  update cesiones set estado = 'cancelada' where partido_id = p_partido and estado = 'ofrecida';
  update ofertas set estado = 'caducada', resuelta_en = now() where liga_id = p.liga_id and estado = 'pendiente';

  for fm in select miembro_id from fantasy_managers where liga_id = p.liga_id loop
    if not exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id) then
      select a.partido_id into v_prev
        from alineaciones a join partidos pp on pp.id = a.partido_id
       where a.manager_id = fm.miembro_id and pp.liga_id = p.liga_id and pp.fecha_hora < p.fecha_hora
       order by pp.fecha_hora desc limit 1;
      if v_prev is not null then
        -- Solo jugadores que siguen siendo suyos y que no ha cedido para este partido; se conservan los roles
        insert into alineaciones (partido_id, manager_id, jugador_id, rol, copiada)
        select p_partido, fm.miembro_id, a.jugador_id, a.rol, true
          from alineaciones a
          join fichas f on f.propietario_id = a.manager_id and f.jugador_id = a.jugador_id
         where a.partido_id = v_prev and a.manager_id = fm.miembro_id
           and not exists (select 1 from cesiones c where c.ficha_id = f.id and c.estado = 'aceptada')
         order by (a.rol = 'POR') desc, a.jugador_id
         limit v_tam;
        -- Si el portero copiado ya no está, el primero pasa a POR
        if exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id)
           and not exists (select 1 from alineaciones where partido_id = p_partido and manager_id = fm.miembro_id
                                                         and rol = 'POR') then
          update alineaciones set rol = 'POR'
           where partido_id = p_partido and manager_id = fm.miembro_id
             and jugador_id = (select min(jugador_id::text)::uuid from alineaciones
                                where partido_id = p_partido and manager_id = fm.miembro_id);
        end if;
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

-- ───────────── Bonus de rol ─────────────
create or replace function bonus_rol(p_partido uuid, p_jugador uuid, p_rol text) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare l ligas; v_eq smallint; v_enc numeric; v_n int; v_min numeric; a acta_jugador;
begin
  select lg.* into l from ligas lg join partidos p on p.liga_id = lg.id where p.id = p_partido;
  if not found or not l.bonus_roles or p_rol is null then return 0; end if;
  select equipo into v_eq from convocatorias
   where partido_id = p_partido and miembro_id = p_jugador and estado = 'confirmado' and equipo is not null;
  if v_eq is null then return 0; end if;
  select * into a from acta_jugador where partido_id = p_partido and miembro_id = p_jugador;

  if p_rol = 'MED' then return coalesce(a.asistencias, 0) * regla(l.id, 'rol_med_asistencia'); end if;
  if p_rol = 'DEL' then return coalesce(a.goles, 0) * regla(l.id, 'rol_del_gol'); end if;

  -- Goles encajados por cada equipo del partido (y media por encuentro jugado)
  with t as (
    select eq, sum(contra)::numeric enc, count(*) n
      from (select equipo_local eq, coalesce(goles_visitante, 0) contra from encuentros where partido_id = p_partido
            union all
            select equipo_visitante, coalesce(goles_local, 0) from encuentros where partido_id = p_partido) x
     group by eq)
  select t.enc, t.n, (select min(t2.enc / t2.n) from t t2) into v_enc, v_n, v_min from t where t.eq = v_eq;
  if v_n is null or v_n = 0 then return 0; end if;

  if p_rol = 'POR' then
    return (case when v_enc = 0 then regla(l.id, 'rol_por_porteria_cero') else 0 end)
         + (case when v_enc / v_n = v_min then regla(l.id, 'rol_por_menos_goleado') else 0 end)
         + floor(v_enc / 3) * regla(l.id, 'rol_por_encajados_3');
  elsif p_rol = 'DEF' then
    return case when v_enc / v_n = v_min then regla(l.id, 'rol_def_menos_goleado') else 0 end;
  end if;
  return 0;
end $$;

-- ───────────── Precios: demanda por fichas y rendimiento solo desde N partidos ─────────────
create or replace function recalcular_precios(p_liga uuid, p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare l ligas; v_dmedia numeric; r record; v_rend numeric; v_n int;
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

  -- Demanda: fichas con dueño / C
  select avg(coalesce(h.n, 0)::numeric / l.copias_por_jugador) into v_dmedia
    from mercado_jugador mj
    left join (select jugador_id, count(*) n from fichas
                where liga_id = p_liga and propietario_id is not null group by jugador_id) h
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
                  (select count(*) from fichas f where f.liga_id = p_liga and f.jugador_id = mj.miembro_id
                                                   and f.propietario_id is not null) as duenos
             from mercado_jugador mj
             left join valoracion_jugador vj on vj.liga_id = mj.liga_id and vj.miembro_id = mj.miembro_id
            where mj.liga_id = p_liga for update of mj loop
    select partidos, pct into v_n, v_rend from tmp_rend where miembro_id = r.miembro_id;
    v_n := coalesce(v_n, 0);
    if v_n < l.partidos_min_rendimiento then
      v_w := 1;                                    -- con pocos partidos solo cuenta la encuesta
    else
      v_w := case when l.k_encuesta + v_n = 0 then 1 else l.k_encuesta / (l.k_encuesta + v_n) end;
    end if;
    v_r := v_w * r.g + (1 - v_w) * coalesce(v_rend, r.g);
    v_d := r.duenos::numeric / l.copias_por_jugador;
    v_f := greatest(0.85, least(1.25, 1 + 0.4 * (coalesce(v_d, 0) - coalesce(v_dmedia, 0))));
    v_lo := r.precio * (1 - l.max_variacion);
    v_hi := r.precio * (1 + l.max_variacion);
    v_nuevo := greatest(v_lo, least(v_hi, precio_base(p_liga, v_r) * v_f));
    v_nuevo := greatest(l.precio_min, least(l.precio_max, v_nuevo));
    v_nuevo := redondear_005(v_nuevo);
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

-- ───────────── Liquidación de la jornada ─────────────
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

  -- Bonus de rol de cada alineado que jugó
  update alineaciones a
     set bonus_rol = case when exists (select 1 from puntos_fantasy pf
                                         where pf.partido_id = a.partido_id and pf.miembro_id = a.jugador_id)
                          then bonus_rol(a.partido_id, a.jugador_id, a.rol) else 0 end
   where a.partido_id = p_partido;

  for fm in select * from fantasy_managers where liga_id = p.liga_id for update loop
    select coalesce(sum((coalesce(pf.total, 0) + coalesce(a.bonus_rol, 0)) * a.multiplicador), 0),
           coalesce(jsonb_agg(jsonb_build_object(
             'jugador_id', a.jugador_id, 'rol', a.rol, 'puntos', coalesce(pf.total, 0),
             'bonus_rol', coalesce(a.bonus_rol, 0), 'multiplicador', a.multiplicador,
             'jugo', pf.miembro_id is not null,
             'cedido', exists (select 1 from cesiones c join fichas f on f.id = c.ficha_id
                                where c.partido_id = p_partido and c.cesionario_id = fm.miembro_id
                                  and c.estado = 'aceptada' and f.jugador_id = a.jugador_id),
             'total', (coalesce(pf.total, 0) + coalesce(a.bonus_rol, 0)) * a.multiplicador)
             order by (a.rol = 'POR') desc, a.rol, a.jugador_id), '[]'::jsonb)
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

  -- Fin de la jornada: las cedidas vuelven, la protección baja, caducan ofertas vencidas
  update cesiones set estado = 'finalizada' where partido_id = p_partido and estado = 'aceptada';
  update cesiones set estado = 'cancelada'  where partido_id = p_partido and estado = 'ofrecida';
  update fichas set protegida_jornadas = protegida_jornadas - 1
   where liga_id = p.liga_id and protegida_jornadas > 0;
  perform caducar_ofertas(p.liga_id);

  update partidos set jornada_liquidada = true where id = p_partido;
  perform recalcular_precios(p.liga_id, p_partido);

  -- La cláusula nunca queda por debajo del nuevo valor de mercado
  update fichas f set clausula = mj.precio
    from mercado_jugador mj
   where f.liga_id = p.liga_id and f.propietario_id is not null
     and mj.liga_id = f.liga_id and mj.miembro_id = f.jugador_id and f.clausula < mj.precio;
  perform asegurar_fichas(p.liga_id);
  return true;
end $$;
