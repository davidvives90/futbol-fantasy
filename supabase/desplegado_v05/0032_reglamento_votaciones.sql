-- 0032 · Post-partido simple por defecto, reglamento estandarizado por modalidad y votaciones de la liga.

-- ── Post-partido: lo avanzado (destacados, más datos, valoración por aspectos, «no le vi») es opcional
alter table ligas add column if not exists valoracion_avanzada boolean not null default false;
update ligas set modo_valoracion = 'rapida' where not valoracion_avanzada and modo_valoracion = 'detallada';

-- ── Reglamento
alter table ligas add column if not exists modalidad text not null default 'f7'
  check (modalidad in ('f3', 'sala', 'f7', 'f8', 'f11'));
alter table ligas add column if not exists reglamento jsonb not null default '{}'::jsonb;

create or replace function modalidad_por_jugadores(n int) returns text language sql immutable as $$
  select case when n <= 3 then 'f3' when n <= 5 then 'sala' when n <= 7 then 'f7' when n = 8 then 'f8' else 'f11' end $$;
update ligas set modalidad = modalidad_por_jugadores(jugadores_por_equipo) where reglamento = '{}'::jsonb;

-- Ligas nuevas: la modalidad sale de los jugadores por equipo (luego el admin puede cambiarla)
create or replace function liga_modalidad_inicial() returns trigger language plpgsql set search_path = public as $$
begin
  new.modalidad := modalidad_por_jugadores(new.jugadores_por_equipo);
  return new;
end $$;
drop trigger if exists liga_modalidad_inicial on ligas;
create trigger liga_modalidad_inicial before insert on ligas for each row execute function liga_modalidad_inicial();

create table if not exists reglas_juego (
  clave        text primary key,
  orden        int  not null,
  grupo        text not null,                 -- 'partido' | 'juego' | 'convivencia'
  titulo       text not null,
  descripcion  text,
  tipo         text not null check (tipo in ('si_no', 'opcion', 'numero')),
  opciones     jsonb,                         -- [{"valor": "...", "texto": "..."}] para tipo opcion
  unidad       text,
  minimo       int,
  maximo       int,
  modalidades  text[] not null,               -- en qué modalidades aplica
  defecto      jsonb not null                 -- {"f7": true, ...}
);
alter table reglas_juego enable row level security;
drop policy if exists reglas_juego_leer on reglas_juego;
create policy reglas_juego_leer on reglas_juego for select to authenticated using (true);
grant select on reglas_juego to authenticated;

insert into reglas_juego (clave, orden, grupo, titulo, descripcion, tipo, opciones, unidad, minimo, maximo, modalidades, defecto) values
('partes', 20, 'partido', 'Partes', null, 'numero', null, 'partes', 1, 4,
  '{f3,sala,f7,f8,f11}', '{"f3":1,"sala":2,"f7":2,"f8":2,"f11":2}'),
('minutos_parte', 30, 'partido', 'Minutos por parte', 'A reloj corrido.', 'numero', null, 'min', 5, 60,
  '{f3,sala,f7,f8,f11}', '{"f3":30,"sala":25,"f7":25,"f8":30,"f11":40}'),
('portero', 40, 'partido', 'Portero', null, 'opcion',
  '[{"valor":"fijo","texto":"Fijo"},{"valor":"rotativo","texto":"Rotativo (por turnos)"},{"valor":"sin_portero","texto":"Sin portero"}]',
  null, null, null, '{f3,sala,f7,f8,f11}', '{"f3":"sin_portero","sala":"rotativo","f7":"rotativo","f8":"rotativo","f11":"fijo"}'),
('cambios', 50, 'partido', 'Cambios', null, 'opcion',
  '[{"valor":"volantes","texto":"Ilimitados y volantes (sin parar)"},{"valor":"parado","texto":"Ilimitados con el balón parado"},{"valor":"limitados","texto":"Limitados (máx. 5)"}]',
  null, null, null, '{f3,sala,f7,f8,f11}', '{"f3":"volantes","sala":"volantes","f7":"volantes","f8":"volantes","f11":"parado"}'),
('rotacion', 60, 'partido', 'Si hay 3 o más equipos', null, 'opcion',
  '[{"valor":"ganador_sigue","texto":"El que gana se queda"},{"valor":"liguilla","texto":"Liguilla: todos contra todos"},{"valor":"por_tiempo","texto":"Por tiempo fijo"}]',
  null, null, null, '{f3,sala,f7,f8,f11}', '{"f3":"ganador_sigue","sala":"ganador_sigue","f7":"ganador_sigue","f8":"ganador_sigue","f11":"liguilla"}'),
('desempate', 70, 'partido', 'Si acaba en empate', null, 'opcion',
  '[{"valor":"empate","texto":"Se queda en empate"},{"valor":"penaltis","texto":"Tanda de penaltis"},{"valor":"gol_de_oro","texto":"Gol de oro"}]',
  null, null, null, '{f3,sala,f7,f8,f11}', '{"f3":"gol_de_oro","sala":"empate","f7":"empate","f8":"empate","f11":"empate"}'),

('cesion', 110, 'juego', 'Cesión al portero', 'Si el portero puede coger con la mano un pase con el pie de un compañero.', 'si_no', null,
  null, null, null, '{sala,f7,f8,f11}', '{"sala":false,"f7":false,"f8":false,"f11":false}'),
('fuera_de_juego', 120, 'juego', 'Fuera de juego', null, 'si_no', null,
  null, null, null, '{f7,f8,f11}', '{"f7":false,"f8":false,"f11":true}'),
('saque_banda', 130, 'juego', 'Saque de banda', null, 'opcion',
  '[{"valor":"mano","texto":"Con la mano"},{"valor":"pie","texto":"Con el pie"}]',
  null, null, null, '{sala,f7,f8,f11}', '{"sala":"pie","f7":"mano","f8":"mano","f11":"mano"}'),
('saque_portero', 140, 'juego', 'Saque del portero', null, 'opcion',
  '[{"valor":"libre","texto":"Libre (mano o pie, a cualquier zona)"},{"valor":"mano","texto":"Solo con la mano"},{"valor":"no_pasa_medio","texto":"No puede pasar del medio campo por el aire"}]',
  null, null, null, '{sala,f7,f8,f11}', '{"sala":"mano","f7":"libre","f8":"libre","f11":"libre"}'),
('paredes', 150, 'juego', 'Paredes y vallas en juego', 'El balón sigue vivo si rebota en la pared o la valla.', 'si_no', null,
  null, null, null, '{f3,sala}', '{"f3":true,"sala":false}'),
('gol_campo_propio', 160, 'juego', 'Gol desde el propio campo', 'Si vale marcar desde tu mitad.', 'si_no', null,
  null, null, null, '{f3,sala,f7}', '{"f3":false,"sala":true,"f7":true}'),
('entradas', 170, 'juego', 'Entradas al suelo', 'Segadas y entradas deslizándose.', 'si_no', null,
  null, null, null, '{f3,sala,f7,f8,f11}', '{"f3":false,"sala":false,"f7":false,"f8":false,"f11":true}'),
('faltas_acumuladas', 180, 'juego', 'Faltas acumuladas', 'A partir de la 6.ª falta por parte, tiro libre directo sin barrera.', 'si_no', null,
  null, null, null, '{sala}', '{"sala":false}'),
('penalti_metros', 190, 'juego', 'Distancia del penalti', null, 'numero', null, 'm', 3, 11,
  '{f3,sala,f7,f8,f11}', '{"f3":5,"sala":6,"f7":9,"f8":9,"f11":11}'),
('balon', 200, 'juego', 'Balón', null, 'opcion',
  '[{"valor":"futsal","texto":"De fútbol sala (bote bajo)"},{"valor":"talla4","texto":"Talla 4"},{"valor":"talla5","texto":"Talla 5"}]',
  null, null, null, '{f3,sala,f7,f8,f11}', '{"f3":"talla5","sala":"futsal","f7":"talla5","f8":"talla5","f11":"talla5"}'),
('arbitro', 210, 'juego', 'Arbitraje', null, 'opcion',
  '[{"valor":"autoarbitraje","texto":"Nos arbitramos nosotros"},{"valor":"arbitro","texto":"Árbitro"}]',
  null, null, null, '{f3,sala,f7,f8,f11}', '{"f3":"autoarbitraje","sala":"autoarbitraje","f7":"autoarbitraje","f8":"autoarbitraje","f11":"autoarbitraje"}'),

('calzado', 310, 'convivencia', 'Calzado', null, 'opcion',
  '[{"valor":"cualquiera","texto":"Cualquiera"},{"valor":"multitaco","texto":"Multitaco o zapatilla"},{"valor":"sala","texto":"Zapatilla de sala"},{"valor":"tacos","texto":"Tacos"}]',
  null, null, null, '{f3,sala,f7,f8,f11}', '{"f3":"multitaco","sala":"sala","f7":"multitaco","f8":"multitaco","f11":"tacos"}'),
('dos_camisetas', 320, 'convivencia', 'Traer camiseta clara y oscura', 'Para hacer los equipos sin petos.', 'si_no', null,
  null, null, null, '{f3,sala,f7,f8,f11}', '{"f3":true,"sala":true,"f7":true,"f8":true,"f11":true}'),
('puntualidad', 330, 'convivencia', 'Llegar antes de la hora', null, 'numero', null, 'min antes', 0, 60,
  '{f3,sala,f7,f8,f11}', '{"f3":10,"sala":10,"f7":10,"f8":10,"f11":15}'),
('aviso_baja', 340, 'convivencia', 'Avisar de una baja con', 'Antelación mínima para borrarse de la convocatoria.', 'numero', null, 'h', 0, 72,
  '{f3,sala,f7,f8,f11}', '{"f3":24,"sala":24,"f7":24,"f8":24,"f11":24}'),
('pago', 350, 'convivencia', 'Cuándo se paga', null, 'opcion',
  '[{"valor":"antes","texto":"Antes del partido"},{"valor":"dia","texto":"El día del partido"},{"valor":"mensual","texto":"A final de mes"}]',
  null, null, null, '{f3,sala,f7,f8,f11}', '{"f3":"dia","sala":"dia","f7":"dia","f8":"dia","f11":"dia"}')
on conflict (clave) do update set orden = excluded.orden, grupo = excluded.grupo, titulo = excluded.titulo,
  descripcion = excluded.descripcion, tipo = excluded.tipo, opciones = excluded.opciones, unidad = excluded.unidad,
  minimo = excluded.minimo, maximo = excluded.maximo, modalidades = excluded.modalidades, defecto = excluded.defecto;

-- Valida un valor contra el catálogo (lanza excepción si no vale).
create or replace function validar_regla(p_clave text, p_valor jsonb) returns void
language plpgsql stable set search_path = public as $$
declare r reglas_juego;
begin
  select * into r from reglas_juego where clave = p_clave;
  if not found then raise exception 'Regla desconocida: %', p_clave; end if;
  if r.tipo = 'si_no' and jsonb_typeof(p_valor) <> 'boolean' then raise exception 'Valor no válido para «%»', r.titulo; end if;
  if r.tipo = 'numero' and (jsonb_typeof(p_valor) <> 'number'
       or (p_valor)::numeric < coalesce(r.minimo, -1e9) or (p_valor)::numeric > coalesce(r.maximo, 1e9)) then
    raise exception 'Valor no válido para «%» (entre % y %)', r.titulo, r.minimo, r.maximo;
  end if;
  if r.tipo = 'opcion' and not exists (select 1 from jsonb_array_elements(r.opciones) o where o -> 'valor' = p_valor) then
    raise exception 'Opción no válida para «%»', r.titulo;
  end if;
end $$;

-- Reglamento efectivo de una liga: [{clave, titulo, ..., valor, personalizada}]
create or replace function reglamento_liga(p_liga uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l ligas;
begin
  if not es_miembro(p_liga) then raise exception 'No perteneces a esta liga'; end if;
  select * into l from ligas where id = p_liga;
  return coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object(
            'valor', coalesce(l.reglamento -> r.clave, r.defecto -> l.modalidad),
            'personalizada', l.reglamento ? r.clave) order by r.orden)
     from reglas_juego r where l.modalidad = any(r.modalidades)), '[]');
end $$;

-- Admin: cambia una regla (null = volver al valor estándar de la modalidad)
create or replace function cambiar_regla(p_liga uuid, p_clave text, p_valor jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not es_admin(p_liga) then raise exception 'Solo el administrador puede cambiar el reglamento'; end if;
  if p_valor is null or p_valor = 'null'::jsonb then
    update ligas set reglamento = reglamento - p_clave where id = p_liga;
  else
    perform validar_regla(p_clave, p_valor);
    update ligas set reglamento = reglamento || jsonb_build_object(p_clave, p_valor) where id = p_liga;
  end if;
end $$;

-- Admin: cambia la modalidad. Las reglas personalizadas se conservan si existen en la nueva modalidad.
create or replace function cambiar_modalidad(p_liga uuid, p_modalidad text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not es_admin(p_liga) then raise exception 'Solo el administrador puede cambiar la modalidad'; end if;
  update ligas set modalidad = p_modalidad,
         reglamento = coalesce((select jsonb_object_agg(k, v) from jsonb_each(reglamento) e(k, v)
                                  join reglas_juego r on r.clave = e.k and p_modalidad = any(r.modalidades)), '{}')
   where id = p_liga;
end $$;

-- ── Votaciones (las crea el admin; votan los miembros activos)
create table if not exists votaciones (
  id             uuid primary key default gen_random_uuid(),
  liga_id        uuid not null references ligas on delete cascade,
  creada_por     uuid references miembros on delete set null,
  titulo         text not null check (length(titulo) between 3 and 140),
  descripcion    text check (length(descripcion) <= 1000),
  opciones       jsonb not null,               -- ["Sí", "No"] (el índice es el id de la opción)
  regla_clave    text references reglas_juego on delete set null,
  regla_valores  jsonb,                        -- valor de la regla para cada opción, mismo orden que opciones
  anonima        boolean not null default true,
  cierra_en      timestamptz not null,
  estado         text not null default 'abierta' check (estado in ('abierta', 'cerrada', 'cancelada')),
  ganadora       int,
  aplicada       boolean not null default false,
  creada_en      timestamptz not null default now(),
  cerrada_en     timestamptz,
  check (jsonb_typeof(opciones) = 'array' and jsonb_array_length(opciones) between 2 and 6)
);
create index if not exists votaciones_liga on votaciones (liga_id, estado, cierra_en);
create table if not exists votos_votacion (
  votacion_id uuid not null references votaciones on delete cascade,
  miembro_id  uuid not null references miembros on delete cascade,
  opcion      int not null,
  votado_en   timestamptz not null default now(),
  primary key (votacion_id, miembro_id)
);
alter table votaciones enable row level security;
alter table votos_votacion enable row level security;
drop policy if exists votaciones_leer on votaciones;
create policy votaciones_leer on votaciones for select to authenticated using (es_miembro(liga_id));
-- los votos no se leen directamente (pueden ser anónimos): solo con votacion_resultados
revoke all on votos_votacion from anon, authenticated;
revoke insert, update, delete on votaciones from anon, authenticated;
grant select on votaciones to authenticated;

create or replace function crear_votacion(p_liga uuid, p_titulo text, p_descripcion text, p_opciones jsonb,
                                          p_cierra_en timestamptz, p_regla_clave text default null,
                                          p_regla_valores jsonb default null, p_anonima boolean default true) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v jsonb;
begin
  if not es_admin(p_liga) then raise exception 'Solo el administrador puede crear votaciones'; end if;
  if p_cierra_en < now() + interval '1 hour' or p_cierra_en > now() + interval '30 days' then
    raise exception 'La votación debe durar entre 1 hora y 30 días';
  end if;
  if exists (select 1 from jsonb_array_elements(p_opciones) o where jsonb_typeof(o) <> 'string' or length(trim(o #>> '{}')) = 0) then
    raise exception 'Las opciones no pueden estar vacías';
  end if;
  if p_regla_clave is not null then
    if jsonb_typeof(p_regla_valores) <> 'array' or jsonb_array_length(p_regla_valores) <> jsonb_array_length(p_opciones) then
      raise exception 'Cada opción necesita su valor de la regla';
    end if;
    for v in select * from jsonb_array_elements(p_regla_valores) loop
      if v <> 'null'::jsonb then perform validar_regla(p_regla_clave, v); end if;
    end loop;
  end if;
  insert into votaciones (liga_id, creada_por, titulo, descripcion, opciones, regla_clave, regla_valores, anonima, cierra_en)
  values (p_liga, mi_miembro(p_liga), trim(p_titulo), nullif(trim(coalesce(p_descripcion, '')), ''), p_opciones,
          p_regla_clave, p_regla_valores, coalesce(p_anonima, true), p_cierra_en)
  returning id into v_id;
  perform notificar((select coalesce(array_agg(perfil_id), '{}') from miembros where liga_id = p_liga and estado = 'activo'
                       and perfil_id is distinct from auth.uid()),
                    p_liga, 'votacion', 'Nueva votación 🗳️', trim(p_titulo), '/votaciones');
  return v_id;
end $$;

create or replace function votar_votacion(p_votacion uuid, p_opcion int) returns void
language plpgsql security definer set search_path = public as $$
declare v votaciones; v_m uuid;
begin
  select * into v from votaciones where id = p_votacion;
  if not found or not es_miembro(v.liga_id) then raise exception 'Votación no encontrada'; end if;
  if v.estado <> 'abierta' or v.cierra_en <= now() then raise exception 'La votación ya está cerrada'; end if;
  if p_opcion < 0 or p_opcion >= jsonb_array_length(v.opciones) then raise exception 'Opción no válida'; end if;
  v_m := mi_miembro(v.liga_id);
  if v_m is null or not exists (select 1 from miembros where id = v_m and estado = 'activo') then
    raise exception 'Solo votan los miembros activos';
  end if;
  insert into votos_votacion (votacion_id, miembro_id, opcion) values (p_votacion, v_m, p_opcion)
  on conflict (votacion_id, miembro_id) do update set opcion = excluded.opcion, votado_en = now();
end $$;

-- Cierre (interno): ganadora = la más votada (empate → sin ganadora) y, si toca, aplica la regla.
create or replace function _cerrar_votacion(p_votacion uuid, p_estado text default 'cerrada') returns void
language plpgsql security definer set search_path = public as $$
declare v votaciones; v_gan int; v_max int; v_n int; v_valor jsonb;
begin
  select * into v from votaciones where id = p_votacion for update;
  if v.estado <> 'abierta' then return; end if;
  if p_estado = 'cancelada' then
    update votaciones set estado = 'cancelada', cerrada_en = now() where id = p_votacion;
    return;
  end if;
  select max(n) into v_max from (select count(*) n from votos_votacion where votacion_id = p_votacion group by opcion) s;
  select count(*) into v_n from (select opcion from votos_votacion where votacion_id = p_votacion
                                  group by opcion having count(*) = v_max) s;
  if v_max is not null and v_n = 1 then
    select opcion into v_gan from votos_votacion where votacion_id = p_votacion group by opcion having count(*) = v_max;
  end if;
  update votaciones set estado = 'cerrada', cerrada_en = now(), ganadora = v_gan where id = p_votacion;
  if v_gan is not null and v.regla_clave is not null then
    v_valor := v.regla_valores -> v_gan;
    if v_valor is not null and v_valor <> 'null'::jsonb then
      update ligas set reglamento = reglamento || jsonb_build_object(v.regla_clave, v_valor) where id = v.liga_id;
      update votaciones set aplicada = true where id = p_votacion;
    end if;
  end if;
  perform notificar((select coalesce(array_agg(perfil_id), '{}') from miembros where liga_id = v.liga_id and estado = 'activo'),
                    v.liga_id, 'votacion', 'Votación cerrada',
                    v.titulo || ': ' || coalesce('ganó «' || (v.opciones ->> v_gan) || '»', 'empate, sin ganadora'), '/votaciones');
end $$;
revoke execute on function _cerrar_votacion(uuid, text) from public, anon, authenticated;

create or replace function cerrar_votacion(p_votacion uuid, p_cancelar boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare v_liga uuid;
begin
  select liga_id into v_liga from votaciones where id = p_votacion;
  if v_liga is null or not es_admin(v_liga) then raise exception 'Solo el administrador puede cerrar votaciones'; end if;
  perform _cerrar_votacion(p_votacion, case when p_cancelar then 'cancelada' else 'cerrada' end);
end $$;

create or replace function cerrar_votaciones_vencidas() returns int
language plpgsql security definer set search_path = public as $$
declare r record; k int := 0;
begin
  for r in select id from votaciones where estado = 'abierta' and cierra_en <= now() loop
    perform _cerrar_votacion(r.id);
    k := k + 1;
  end loop;
  return k;
end $$;
revoke execute on function cerrar_votaciones_vencidas() from public, anon, authenticated;

-- Resultados: recuento por opción, mi voto y, si no es anónima, quién votó qué.
create or replace function votacion_resultados(p_votacion uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v votaciones;
begin
  select * into v from votaciones where id = p_votacion;
  if not found or not es_miembro(v.liga_id) then raise exception 'Votación no encontrada'; end if;
  return jsonb_build_object(
    'mi_voto', (select opcion from votos_votacion where votacion_id = p_votacion and miembro_id = mi_miembro(v.liga_id)),
    'total', (select count(*) from votos_votacion where votacion_id = p_votacion),
    'censo', (select count(*) from miembros where liga_id = v.liga_id and estado = 'activo'),
    'votos', (select coalesce(jsonb_agg(jsonb_build_object('opcion', i,
                 'n', (select count(*) from votos_votacion where votacion_id = p_votacion and opcion = i),
                 'miembros', case when v.anonima then '[]'::jsonb else
                    (select coalesce(jsonb_agg(miembro_id), '[]') from votos_votacion where votacion_id = p_votacion and opcion = i) end)
                 order by i), '[]')
                from generate_series(0, jsonb_array_length(v.opciones) - 1) i));
end $$;

revoke execute on function validar_regla(text, jsonb), reglamento_liga(uuid), cambiar_regla(uuid, text, jsonb),
  cambiar_modalidad(uuid, text), crear_votacion(uuid, text, text, jsonb, timestamptz, text, jsonb, boolean),
  votar_votacion(uuid, int), cerrar_votacion(uuid, boolean), votacion_resultados(uuid) from public, anon;
grant execute on function reglamento_liga(uuid), cambiar_regla(uuid, text, jsonb), cambiar_modalidad(uuid, text),
  crear_votacion(uuid, text, text, jsonb, timestamptz, text, jsonb, boolean), votar_votacion(uuid, int),
  cerrar_votacion(uuid, boolean), votacion_resultados(uuid) to authenticated;
