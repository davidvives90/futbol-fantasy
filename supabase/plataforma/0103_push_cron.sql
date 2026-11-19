-- Push: pg_net + cron cada minuto que llama a la Edge Function enviar-push solo si hay avisos pendientes.
-- Desplegado el 19-11-2026. El secreto FCM_SERVICE_ACCOUNT se configura en Supabase → Edge Functions → Secrets.
create extension if not exists pg_net with schema extensions;
update notificaciones set push_estado = 'no_push' where push_estado = 'pendiente' and creado_en < now() - interval '30 minutes';
select cron.schedule('ff_push', '* * * * *', $c$
  select net.http_post(url := 'https://wyybdsxnmxgfntyrzjmq.supabase.co/functions/v1/enviar-push',
                       headers := '{"Content-Type":"application/json"}'::jsonb, body := '{}'::jsonb)
   where exists (select 1 from public.notificaciones where push_estado = 'pendiente')
$c$);
