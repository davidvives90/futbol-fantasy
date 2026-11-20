-- 0040 · Responder «Voy / No voy» desde la notificación, sin abrir la app
--  · tokens_aviso: clave secreta por jugador (tabla sin acceso para la app; solo el servidor la lee).
--  · token_aviso_de(miembro): la crea si no existe (la usa la Edge Function «enviar-push»).
--  · responder_aviso(token, partido, 'voy'|'no'): la usa la Edge Function «responder».

create table if not exists tokens_aviso (
  miembro_id uuid primary key references miembros on delete cascade,
  token      text not null unique,
  creado_en  timestamptz not null default now()
);
alter table tokens_aviso enable row level security;
revoke all on tokens_aviso from anon, authenticated;

create or replace function token_aviso_de(p_miembro uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v text;
begin
  select token into v from tokens_aviso where miembro_id = p_miembro;
  if v is null then
    v := md5(random()::text || clock_timestamp()::text || p_miembro::text) || md5(random()::text || p_miembro::text);
    insert into tokens_aviso (miembro_id, token) values (p_miembro, v)
    on conflict (miembro_id) do nothing;
    select token into v from tokens_aviso where miembro_id = p_miembro;
  end if;
  return v;
end $$;

create or replace function responder_aviso(p_token text, p_partido uuid, p_respuesta text) returns text
language plpgsql security definer set search_path = public as $$
declare m miembros; p partidos; v_estado text; v_final text;
begin
  if p_token is null or length(p_token) < 32 then return 'no_valido'; end if;
  select * into p from partidos where id = p_partido;
  if not found then return 'no_valido'; end if;
  select mi.* into m from miembros mi join tokens_aviso t on t.miembro_id = mi.id
   where t.token = p_token and mi.liga_id = p.liga_id and mi.estado = 'activo';
  if not found then return 'no_valido'; end if;
  if p.estado not in ('abierto', 'completo', 'equipos_hechos') then return 'cerrado'; end if;
  v_estado := case lower(p_respuesta) when 'voy' then 'confirmado' when 'no' then 'baja' else null end;
  if v_estado is null then return 'no_valido'; end if;
  insert into convocatorias (partido_id, miembro_id, estado) values (p_partido, m.id, v_estado::estado_inscr)
  on conflict (partido_id, miembro_id) do update set estado = excluded.estado;
  select estado::text into v_final from convocatorias where partido_id = p_partido and miembro_id = m.id;
  return v_final;
end $$;

revoke execute on function responder_aviso(text, uuid, text), token_aviso_de(uuid) from public, anon, authenticated;
grant execute on function responder_aviso(text, uuid, text), token_aviso_de(uuid) to service_role;
