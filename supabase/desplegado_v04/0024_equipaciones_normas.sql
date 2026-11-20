-- 0024 · Equipaciones elegibles por liga y normas de la liga (texto libre del admin)
--  · ligas.equipaciones: una por equipo, en orden (equipo 1, 2, 3, 4): [{"nombre":"Blanco","color":"#F4F4F2"}, …].
--    color null = «de color» sin especificar (la app usa su color por defecto).
--  · ligas.normas: lo que habéis acordado (puntualidad, pagos, bajas…). Se muestra en la Guía de la liga.
alter table ligas
  add column equipaciones jsonb not null default
    '[{"nombre":"Blanco","color":"#F4F4F2"},{"nombre":"Color","color":null},{"nombre":"Negro","color":"#1E1E1E"},{"nombre":"Petos","color":"#E8C21A"}]'
    constraint ligas_equipaciones_ck check (jsonb_typeof(equipaciones) = 'array' and jsonb_array_length(equipaciones) between 2 and 4),
  add column normas text constraint ligas_normas_ck check (length(normas) <= 6000);
