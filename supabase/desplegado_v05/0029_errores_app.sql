-- 0029 · Registro de errores de la app (en lugar de Crashlytics): la app envía cada error no controlado
-- y el máster los ve en su panel. Límite: 30 por usuario y hora; mensajes recortados.
create table errores_app (
  id         bigint generated always as identity primary key,
  perfil_id  uuid,
  version    text,
  plataforma text,
  pantalla   text,
  mensaje    text not null,
  traza      text,
  veces      int not null default 1,
  creado_en  timestamptz not null default now(),
  ultimo_en  timestamptz not null default now()
);
create index on errores_app (ultimo_en desc);
alter table errores_app enable row level security;
revoke all on errores_app from anon, public, authenticated;

create or replace function registrar_error(p_mensaje text, p_traza text default null, p_pantalla text default null,
                                           p_version text default null, p_plataforma text default 'android')
returns void language plpgsql security definer set search_path = public as $$
declare v_msg text := left(coalesce(p_mensaje, '?'), 500); v_id bigint;
begin
  if auth.uid() is null then return; end if;
  if (select count(*) from errores_app where perfil_id = auth.uid() and ultimo_en > now() - interval '1 hour') >= 30 then
    return;
  end if;
  -- mismo error del mismo usuario en las últimas 24 h: se cuenta en vez de duplicar
  select id into v_id from errores_app
   where perfil_id = auth.uid() and mensaje = v_msg and coalesce(version, '') = coalesce(left(p_version, 30), '')
     and ultimo_en > now() - interval '24 hours' limit 1;
  if v_id is not null then
    update errores_app set veces = veces + 1, ultimo_en = now() where id = v_id;
  else
    insert into errores_app (perfil_id, version, plataforma, pantalla, mensaje, traza)
    values (auth.uid(), left(p_version, 30), left(p_plataforma, 20), left(p_pantalla, 120), v_msg, left(p_traza, 4000));
  end if;
end $$;

create or replace function master_errores(p_limite int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform exigir_master();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', e.id, 'mensaje', e.mensaje, 'traza', e.traza, 'pantalla', e.pantalla, 'version', e.version,
      'veces', e.veces, 'ultimo_en', e.ultimo_en, 'quien', (select email from auth.users where id = e.perfil_id))
      order by e.ultimo_en desc)
      from (select * from errores_app order by ultimo_en desc limit least(greatest(p_limite, 1), 500)) e), '[]');
end $$;

revoke execute on function registrar_error(text, text, text, text, text), master_errores(int) from public, anon;
grant execute on function registrar_error(text, text, text, text, text), master_errores(int) to authenticated;
