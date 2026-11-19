-- La Edge Function enviar-push usa service_role: necesita leer/actualizar avisos y borrar tokens caducados.
grant select, update on notificaciones to service_role;
grant select, delete on dispositivos to service_role;
