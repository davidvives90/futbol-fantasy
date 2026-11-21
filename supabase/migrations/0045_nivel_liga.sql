-- 0045: nivel de la liga (básico · medio · avanzado). Es un ajuste de presentación:
-- decide qué opciones se ven en Ajustes y qué módulos se activan al crearla.
alter table ligas add column if not exists nivel text;
update ligas set nivel = 'avanzado' where nivel is null;   -- las ligas que ya existen lo ven todo
alter table ligas alter column nivel set default 'medio';
alter table ligas alter column nivel set not null;
do $$ begin
  alter table ligas add constraint ligas_nivel_chk check (nivel in ('basico', 'medio', 'avanzado'));
exception when duplicate_object then null; end $$;
