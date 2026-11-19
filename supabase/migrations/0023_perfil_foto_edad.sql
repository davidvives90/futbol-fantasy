-- 0023 · Perfil: fecha de nacimiento (se muestra solo la edad) y foto (bucket público «avatares», ver plataforma/0105)
alter table perfiles add column fecha_nacimiento date
  constraint perfiles_fecha_nacimiento_ck check (fecha_nacimiento between date '1930-01-01' and current_date - interval '10 years');
