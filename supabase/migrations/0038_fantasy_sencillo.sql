-- 0038 · Fantasy sencillo: sin encuesta obligatoria
--  · Todos los jugadores empiezan con un valor parecido (valoración al azar entre 45 y 55) y el precio
--    se mueve partido a partido según goles, notas y MVP.
--  · El Fantasy arranca solo la primera vez que alguien entra (entrar_fantasy): sin esperar al admin.
--  · La encuesta queda como opción: si se cierra antes de empezar fija los precios iniciales (como antes);
--    si se cierra después, solo afina las valoraciones (equipos equilibrados y evolución del precio).
--  · reiniciar_fantasy(liga, igualar): el admin puede empezar de cero con todos al mismo precio.

create or replace function mercado_abierto(p_liga uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select (select presupuesto_inicial is not null from ligas where id = p_liga)
     and not exists (select 1 from partidos p join ligas l on l.id = p.liga_id
                       where p.liga_id = p_liga and p.estado not in ('cerrado', 'cancelado')
                         and now() >= p.fecha_hora - make_interval(hours => l.horas_cierre_alineacion))
$$;

-- Valoración inicial: parecida para todos, con un poco de azar (45–55) para que no salgan todos iguales
create or replace function rating_inicial() returns numeric
language sql volatile set search_path = public as $$ select round((45 + random() * 10)::numeric, 1) $$;

-- Precios iniciales parecidos para los jugadores que aún no tienen precio (o para todos si p_todos)
create or replace function igualar_precios(p_liga uuid, p_todos boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  if p_todos then
    update mercado_jugador set rating = rating_inicial(), actualizado_en = now() where liga_id = p_liga;
    update mercado_jugador set precio = redondear_005(precio_base(p_liga, rating)) where liga_id = p_liga;
    insert into historial_precios (liga_id, miembro_id, precio, rating)
    select p_liga, miembro_id, precio, rating from mercado_jugador where liga_id = p_liga;
  end if;
  insert into mercado_jugador (liga_id, miembro_id, precio, rating, no_habitual)
  select p_liga, j, redondear_005(precio_base(p_liga, r)), r, es_no_habitual(j)
    from (select j, rating_inicial() r from jugadores_liga(p_liga) j) t
   where not exists (select 1 from mercado_jugador where liga_id = p_liga and miembro_id = t.j);
  get diagnostics k = row_count;
  insert into historial_precios (liga_id, miembro_id, precio, rating)
  select p_liga, mj.miembro_id, mj.precio, mj.rating from mercado_jugador mj
   where mj.liga_id = p_liga and not exists (select 1 from historial_precios h
                                              where h.liga_id = p_liga and h.miembro_id = mj.miembro_id);
  return k;
end $$;

-- Entrar al Fantasy: si la liga aún no ha empezado, empieza (todos al mismo precio); después crea
-- mi equipo (dinero + jugadores repartidos). Idempotente: se llama cada vez que se abre el Fantasy.
create or replace function entrar_fantasy(p_liga uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_yo uuid; l ligas;
begin
  select * into l from ligas where id = p_liga for update;
  if not found then raise exception 'Liga no encontrada'; end if;
  if not l.fantasy_activo then return false; end if;
  select id into v_yo from miembros
   where liga_id = p_liga and perfil_id = (select auth.uid()) and estado = 'activo';
  if v_yo is null then raise exception 'No eres miembro de esta liga'; end if;
  if l.presupuesto_inicial is null then
    perform igualar_precios(p_liga);
    update ligas set presupuesto_inicial = presupuesto_liga(p_liga) where id = p_liga;
  end if;
  perform asegurar_manager(p_liga, v_yo);
  return true;
end $$;

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
  delete from tmp_rend where true;
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

  for r in select mj.*, coalesce(vj.general, (select h.rating from historial_precios h where h.liga_id = mj.liga_id and h.miembro_id = mj.miembro_id and h.partido_id is null order by h.creado_en desc, h.id desc limit 1), 50) as g, (vj.general is not null) as con_encuesta,
                  (select count(*) from fichas f where f.liga_id = p_liga and f.jugador_id = mj.miembro_id
                                                   and f.propietario_id is not null) as duenos
             from mercado_jugador mj
             left join valoracion_jugador vj on vj.liga_id = mj.liga_id and vj.miembro_id = mj.miembro_id
            where mj.liga_id = p_liga for update of mj loop
    select partidos, pct into v_n, v_rend from tmp_rend where miembro_id = r.miembro_id;
    v_n := coalesce(v_n, 0);
    if not r.con_encuesta then
      -- Sin encuesta: todos parten de su valor inicial (45–55) y cada partido cuenta desde el primero
      v_w := 2.0 / (2 + v_n);
    elsif v_n < l.partidos_min_rendimiento then
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

create or replace function cerrar_encuesta(p_encuesta uuid) returns int
language plpgsql security definer set search_path = public as $$
declare e encuestas_valoracion; j uuid; v_cal record; v_vel record; v_res record; v_def record;
        v_reg record; v_por record; v_g numeric; v_precio numeric; v_presu numeric; k int := 0;
        v_jugados int; v_iniciado boolean;
begin
  select * into e from encuestas_valoracion where id = p_encuesta for update;
  if not found then raise exception 'Encuesta no encontrada'; end if;
  perform exigir_admin(e.liga_id);
  if e.estado <> 'abierta' then raise exception 'La encuesta ya está cerrada'; end if;
  v_iniciado := (select presupuesto_inicial is not null from ligas where id = e.liga_id);

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
    -- Si el Fantasy ya empezó (todos al mismo precio), la encuesta no toca precios: solo afina valoraciones
    if (e.sujeto_id is null and not v_iniciado) or (e.sujeto_id is not null and v_jugados = 0) then
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

  if e.sujeto_id is null and not v_iniciado then
    -- Presupuesto inicial = 6,5 × precio medio inicial, redondeado a 0,5
    select round(6.5 * avg(precio) * 2) / 2 into v_presu from mercado_jugador where liga_id = e.liga_id;
    update ligas set presupuesto_inicial = v_presu where id = e.liga_id;
    perform asegurar_manager(e.liga_id, m.id)
       from miembros m where m.liga_id = e.liga_id and m.estado = 'activo';
  end if;
  return k;
end $$;

create or replace function alta_jugador_mercado() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_precio numeric; v_r numeric := rating_inicial();
begin
  if new.estado in ('activo', 'pendiente_registro')
     and (select presupuesto_inicial is not null from ligas where id = new.liga_id)
     and not exists (select 1 from mercado_jugador where liga_id = new.liga_id and miembro_id = new.id) then
    v_precio := redondear_005(precio_base(new.liga_id, v_r));
    insert into mercado_jugador (liga_id, miembro_id, precio, rating, no_habitual)
    values (new.liga_id, new.id, v_precio, v_r, new.rango = 'invitado');
    insert into historial_precios (liga_id, miembro_id, precio, rating) values (new.liga_id, new.id, v_precio, v_r);
  end if;
  return null;
end $$;

drop function if exists reiniciar_fantasy(uuid);
create or replace function reiniciar_fantasy(p_liga uuid, p_igualar boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare k int := 0; m record;
begin
  if auth.uid() is not null then perform exigir_admin(p_liga); end if;
  delete from ofertas where liga_id = p_liga;
  delete from cesiones where liga_id = p_liga;
  delete from alineaciones a using partidos p where a.partido_id = p.id and p.liga_id = p_liga;
  delete from puntos_manager pm using partidos p where pm.partido_id = p.id and p.liga_id = p_liga;
  delete from transacciones_fantasy where liga_id = p_liga;
  update fichas set propietario_id = null, precio_compra = null, clausula = null, adquirida_en = null,
                    protegida_jornadas = 0, protegida_hasta = null
   where liga_id = p_liga;
  delete from fantasy_managers where liga_id = p_liga;
  perform igualar_precios(p_liga, p_igualar);
  update ligas set presupuesto_inicial = presupuesto_liga(p_liga) where id = p_liga;
  for m in select id from miembros where liga_id = p_liga and estado = 'activo' and perfil_id is not null loop
    perform asegurar_manager(p_liga, m.id);
    k := k + 1;
  end loop;
  return k;
end $$;

revoke execute on function igualar_precios(uuid, boolean), rating_inicial() from public, anon, authenticated;
revoke execute on function entrar_fantasy(uuid), reiniciar_fantasy(uuid, boolean) from public, anon;
grant execute on function entrar_fantasy(uuid), reiniciar_fantasy(uuid, boolean) to authenticated;
