-- Solo en Supabase (no en las pruebas locales): realtime de la bandeja y recordatorios cada 15 min.
alter publication supabase_realtime add table notificaciones;
select cron.schedule('ff_recordatorios', '*/15 * * * *', $c$select public.enviar_recordatorios()$c$);
-- Push (cuando estén las credenciales de Firebase): ver functions/enviar-push y 0103.
