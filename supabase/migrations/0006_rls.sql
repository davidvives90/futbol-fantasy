-- 0006 · Seguridad: Row Level Security, permisos y Storage
-- Principio: las escrituras sensibles pasan por funciones (security definer) que validan;
-- las políticas solo abren lo que la app hace directamente.

alter table perfiles            enable row level security;
alter table ligas               enable row level security;
alter table miembros            enable row level security;
alter table partidos            enable row level security;
alter table encuentros          enable row level security;
alter table convocatorias       enable row level security;
alter table facturas            enable row level security;
alter table movimientos         enable row level security;
alter table acta_jugador        enable row level security;
alter table reglas_puntuacion   enable row level security;
alter table puntos_fantasy      enable row level security;
alter table aspectos_valoracion enable row level security;
alter table reportes_encuentro  enable row level security;
alter table reportes_jugador    enable row level security;
alter table valoraciones        enable row level security;
alter table disputas            enable row level security;

-- ───────────── Permisos base ─────────────
revoke all on all tables in schema public from anon, public;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Tokens y contactos de miembros: solo vía enlaces_invitacion() (admins)
revoke select, insert, update, delete on miembros from authenticated;
grant select (id, liga_id, perfil_id, nombre_provisional, posicion, rol, estado, invitado_por, unido_en)
  on miembros to authenticated;
grant update (posicion) on miembros to authenticated;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
-- Internas: no se llaman desde la app
revoke execute on function decidir_campo, consolidar_acta, cerrar_ventanas_vencidas,
                           liberar_plazas_futuras from authenticated;
-- (consolidar_acta queda accesible vía cerrar_post_partido / resolver_disputa)

-- ───────────── Perfiles ─────────────
create policy perfil_leer on perfiles for select to authenticated
  using (id = auth.uid() or comparte_liga(id));
create policy perfil_crear on perfiles for insert to authenticated with check (id = auth.uid());
create policy perfil_editar on perfiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ───────────── Ligas ─────────────
create policy liga_leer on ligas for select to authenticated
  using (visibilidad = 'publica' or es_miembro(id)
         or exists (select 1 from miembros m where m.liga_id = ligas.id and m.perfil_id = auth.uid()
                      and m.estado = 'solicitud'));
create policy liga_editar on ligas for update to authenticated
  using (es_admin(id)) with check (es_admin(id));
create policy liga_borrar on ligas for delete to authenticated using (es_admin(id));
-- alta: crear_liga()

-- ───────────── Miembros ─────────────
create policy miembro_leer on miembros for select to authenticated
  using (perfil_id = auth.uid() or es_miembro(liga_id));
create policy miembro_posicion on miembros for update to authenticated
  using (perfil_id = auth.uid() or es_admin(liga_id))
  with check (perfil_id = auth.uid() or es_admin(liga_id));
-- altas, roles, expulsiones: funciones de 0002

-- ───────────── Partidos y encuentros ─────────────
create policy partido_leer on partidos for select to authenticated using (es_miembro(liga_id));
create policy partido_editar on partidos for update to authenticated
  using (es_admin(liga_id)) with check (es_admin(liga_id));
create policy partido_borrar on partidos for delete to authenticated
  using (es_admin(liga_id) and estado in ('abierto', 'completo', 'cancelado'));
-- alta: crear_partido(); cambios de estado: funciones

create policy encuentro_leer on encuentros for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));
-- escritura: guardar_equipos / definir_encuentros / consolidar_acta

-- ───────────── Convocatorias ─────────────
create policy conv_leer on convocatorias for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));
create policy conv_apuntarse on convocatorias for insert to authenticated
  with check (miembro_id = mi_miembro(liga_de_partido(partido_id))
              or (es_admin(liga_de_partido(partido_id))
                  and exists (select 1 from miembros m where m.id = miembro_id
                                and m.liga_id = liga_de_partido(partido_id)
                                and m.estado in ('activo', 'pendiente_registro'))));
create policy conv_cambiar on convocatorias for update to authenticated
  using (miembro_id = mi_miembro(liga_de_partido(partido_id)) or es_admin(liga_de_partido(partido_id)))
  with check (miembro_id = mi_miembro(liga_de_partido(partido_id)) or es_admin(liga_de_partido(partido_id)));
create policy conv_borrar on convocatorias for delete to authenticated
  using (es_admin(liga_de_partido(partido_id)));
-- el trigger gestionar_cupo impide a no-admins tocar equipos o partidos cerrados

-- ───────────── Tesorería ─────────────
create policy factura_leer on facturas for select to authenticated using (es_miembro(liga_id));
create policy factura_admin on facturas for all to authenticated
  using (es_admin(liga_id)) with check (es_admin(liga_id));

create policy mov_leer on movimientos for select to authenticated
  using (miembro_id = mi_miembro(liga_id) or es_admin(liga_id));
create policy mov_admin_corregir on movimientos for delete to authenticated using (es_admin(liga_id));
-- altas: registrar_pago() / generar_cargos(); sin update: los errores se corrigen con un ajuste

-- ───────────── Acta, puntos, reglas y aspectos ─────────────
create policy acta_leer on acta_jugador for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));
create policy puntos_leer on puntos_fantasy for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));

create policy reglas_leer on reglas_puntuacion for select to authenticated using (es_miembro(liga_id));
create policy reglas_admin on reglas_puntuacion for all to authenticated
  using (es_admin(liga_id)) with check (es_admin(liga_id));

create policy aspectos_leer on aspectos_valoracion for select to authenticated using (es_miembro(liga_id));
create policy aspectos_admin on aspectos_valoracion for all to authenticated
  using (es_admin(liga_id)) with check (es_admin(liga_id));

-- ───────────── Partes post-partido ─────────────
-- Cada uno escribe y lee los suyos (el trigger validar_parte comprueba estado y asistencia).
-- Los admins leen todos los partes de su liga para resolver disputas.
create policy rep_enc_propio on reportes_encuentro for all to authenticated
  using (reportero_id = mi_miembro(liga_de_partido(partido_id)))
  with check (reportero_id = mi_miembro(liga_de_partido(partido_id)));
create policy rep_enc_admin on reportes_encuentro for select to authenticated
  using (es_admin(liga_de_partido(partido_id)));

create policy rep_jug_propio on reportes_jugador for all to authenticated
  using (reportero_id = mi_miembro(liga_de_partido(partido_id)))
  with check (reportero_id = mi_miembro(liga_de_partido(partido_id)));
create policy rep_jug_admin on reportes_jugador for select to authenticated
  using (es_admin(liga_de_partido(partido_id)));

-- Valoraciones: anónimas. Solo el votante ve las suyas; NI los admins leen votos ajenos.
create policy val_propia on valoraciones for all to authenticated
  using (votante_id = mi_miembro(liga_de_partido(partido_id)))
  with check (votante_id = mi_miembro(liga_de_partido(partido_id)));

create policy disputa_leer on disputas for select to authenticated
  using (es_miembro(liga_de_partido(partido_id)));
-- resolución: resolver_disputa()

-- ───────────── Storage: bucket privado de facturas ─────────────
-- Ruta de cada archivo: <liga_id>/<factura_id>.<ext>
insert into storage.buckets (id, name, public) values ('facturas', 'facturas', false)
on conflict (id) do nothing;

create policy facturas_leer on storage.objects for select to authenticated
  using (bucket_id = 'facturas' and es_miembro(((storage.foldername(name))[1])::uuid));
create policy facturas_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'facturas' and es_admin(((storage.foldername(name))[1])::uuid));
create policy facturas_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'facturas' and es_admin(((storage.foldername(name))[1])::uuid));

-- ───────────── Realtime ─────────────
-- En Supabase, publicar los cambios que la app escucha en vivo:
--   alter publication supabase_realtime add table convocatorias, partidos, encuentros, disputas;
