-- Borra los errores de más de 90 días (lo promete la política de privacidad).
select cron.schedule('ff_limpiar_errores', '17 4 * * *', $$delete from public.errores_app where creado_en < now() - interval '90 days'$$);
