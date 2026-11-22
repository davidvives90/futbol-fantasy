-- 0052 · Cuentas de prueba admin1…admin5 (entrar escribiendo «admin1» en el email, sin código)
--  · Solo funcionan con config_pruebas.activo = true. Apagar antes de publicar en Google Play:
--      update config_pruebas set activo = false;
--  · Son usuarios normales (NO máster): solo ven las ligas en las que estén.
--  · La tabla solo la lee el servidor (RLS sin políticas).

create table if not exists config_pruebas (
  id       smallint primary key default 1 check (id = 1),
  activo   boolean not null default false,
  cambiado timestamptz not null default now()
);
alter table config_pruebas enable row level security;
revoke all on config_pruebas from anon, authenticated;
insert into config_pruebas (id, activo) values (1, true)
on conflict (id) do update set activo = true, cambiado = now();
grant select on config_pruebas to service_role;
-- Los perfiles de admin1…admin5 se crearon a mano (Admin 1…5) y están en la liga «Prueba» (código DFDAF7).
