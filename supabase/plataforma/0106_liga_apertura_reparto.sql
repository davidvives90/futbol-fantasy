-- Desplegado el 20-11-2026 (solo producción): la liga existente pasa a convocatoria con apertura,
-- se quitan las inscripciones automáticas de fijos, se reinicia el Fantasy con reparto y se programa la caducidad
-- de protecciones.
update ligas set modo_convocatoria = 'apertura', duracion_partido_min = 60, horas_apertura_convocatoria = 2,
                 horas_reserva_fijos = 24, reparto_inicial = 5, factor_presupuesto = 1.5, proteccion_dias = 7;
delete from convocatorias c using partidos p
 where c.partido_id = p.id and p.estado in ('abierto', 'completo')
   and abs(extract(epoch from c.inscrito_en - p.creado_en)) < 5;
delete from convocatorias c using partidos p
 where c.partido_id = p.id and p.estado in ('abierto', 'completo')
   and convocatoria_abre_en(p.id) > now();
update partidos p set estado = 'abierto'
 where estado = 'completo'
   and (select count(*) from convocatorias c where c.partido_id = p.id and c.estado = 'confirmado') < p.plazas;
select reiniciar_fantasy(id) from ligas where presupuesto_inicial is not null;
select cron.schedule('ff_protecciones', '*/15 * * * *', $c$select public.caducar_protecciones()$c$);
