-- Configuración propia de Supabase (no se aplica en las pruebas locales con stubs).

-- 1. Bucket privado para las facturas (las políticas están en 0006_rls.sql)
insert into storage.buckets (id, name, public)
values ('facturas', 'facturas', false)
on conflict (id) do nothing;

-- 2. Tiempo real en las tablas que la app escucha
do $$
declare t text;
begin
  foreach t in array array['convocatorias','partidos','encuentros','disputas'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- 3. Tareas programadas: cerrar ventanas post-partido vencidas y congelar alineaciones
create extension if not exists pg_cron;
select cron.schedule('ff_cerrar_ventanas', '*/15 * * * *', $$select public.cerrar_ventanas_vencidas()$$);
select cron.schedule('ff_congelar_alineaciones', '*/5 * * * *', $$select public.congelar_alineaciones_vencidas()$$);
