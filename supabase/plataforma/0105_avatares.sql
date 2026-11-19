-- Fotos de perfil: bucket público (las fotos se ven en listas), cada usuario solo escribe en su carpeta <uid>/
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatares', 'avatares', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;
create policy avatares_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'avatares' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatares_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatares_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = auth.uid()::text);
