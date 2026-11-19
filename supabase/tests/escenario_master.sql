-- Escenario 0021 · Cuenta máster y códigos promocionales
\set ON_ERROR_STOP 1
\pset pager off
reset role;

create or replace function t_como_uid(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, false) $$;
grant execute on function t_como_uid to authenticated;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000aaaa', 'master@test');
insert into masters (perfil_id, nota) values ('00000000-0000-0000-0000-00000000aaaa', 'test');

-- dos mánagers de una liga con Fantasy, y otra liga distinta
select fm.liga_id as lfa, (array_agg(m.perfil_id order by m.id))[1] as u1, (array_agg(m.perfil_id order by m.id))[2] as u2,
       (array_agg(m.perfil_id order by m.id))[3] as u3,
       (array_agg(fm.miembro_id order by m.id))[1] as m1
  from fantasy_managers fm join miembros m on m.id = fm.miembro_id
 where m.perfil_id is not null and m.estado = 'activo'
 group by fm.liga_id having count(*) >= 3 limit 1 \gset
select id as lotra from ligas where id <> :'lfa' limit 1 \gset
select t_check(:'lfa' is not null and :'lotra' is not null, 'hay ligas de prueba');

set role authenticated;
-- ═════ No máster
select t_como_uid(:'u1');
select t_check(not es_master(), 'un jugador no es máster');
select t_debe_fallar('select master_resumen()', 'un jugador no ve el panel máster');
select t_debe_fallar(format('select master_crear_codigo(%L, 10)', 'HACK'), 'un jugador no crea códigos');
select t_debe_fallar(format('insert into masters (perfil_id) values (%L)', :'u1'), 'nadie se hace máster desde la app');
select t_check((select count(*) from codigos_promo) = 0, 'un jugador no lista los códigos');

-- ═════ Máster
select t_como_uid('00000000-0000-0000-0000-00000000aaaa');
select t_check(es_master(), 'la cuenta máster es máster');
select t_check(es_admin(:'lfa') and es_admin(:'lotra') and es_miembro(:'lotra'), 'el máster es admin de todas las ligas');
select t_check((select count(*) from miembros where liga_id = :'lotra') > 0, 'el máster lee cualquier liga (RLS)');
select t_check((master_resumen() ->> 'ligas')::int = (select count(*) from ligas), 'resumen: nº de ligas');
select t_check(jsonb_array_length(master_ligas()) = (select count(*) from ligas), 'master_ligas lista todas');
select t_check(jsonb_array_length(master_usuarios('master')) = 1, 'buscar usuarios por email');

select master_crear_codigo('bienvenida', 50, null, 2, null, 'lanzamiento') as cod \gset
select master_crear_codigo('SOLOOTRA', 30, :'lotra') as cod2 \gset
select master_crear_codigo('VIEJO', 30, null, null, now() - interval '1 day') as cod3 \gset
select t_debe_fallar(format('select master_crear_codigo(%L, 10)', 'con espacios'), 'formato de código no válido');
select t_debe_fallar(format('select master_crear_codigo(%L, 5000)', 'MUCHO'), 'importe máximo 1000');
select t_check(jsonb_array_length(master_codigos()) = 3, 'master_codigos lista los 3');

-- ═════ Canje
select t_como_uid(:'u1');
select saldo as s0 from fantasy_managers where liga_id = :'lfa' and miembro_id = mi_miembro(:'lfa') \gset
select t_check(canjear_codigo(:'lfa', ' bienvenida ') = :'s0'::numeric + 50, 'canjear suma 50 al saldo');
select t_debe_fallar(format('select canjear_codigo(%L, %L)', :'lfa', 'BIENVENIDA'), 'no se canjea dos veces');
select t_debe_fallar(format('select canjear_codigo(%L, %L)', :'lfa', 'SOLOOTRA'), 'código de otra liga');
select t_debe_fallar(format('select canjear_codigo(%L, %L)', :'lfa', 'VIEJO'), 'código caducado');
select t_debe_fallar(format('select canjear_codigo(%L, %L)', :'lfa', 'NOEXISTE'), 'código inexistente');
select t_check((select count(*) from canjes_promo) = 1, 'cada uno ve solo sus canjes');
select t_check(exists (select 1 from transacciones_fantasy where manager_id = mi_miembro(:'lfa') and tipo = 'ajuste' and importe = 50),
               'el canje queda como transacción');
select t_como_uid(:'u2');
select canjear_codigo(:'lfa', 'BIENVENIDA');
select t_como_uid(:'u3');
select t_debe_fallar(format('select canjear_codigo(%L, %L)', :'lfa', 'BIENVENIDA'), 'límite de usos alcanzado');

-- ═════ Ajustes y partidos
select t_como_uid('00000000-0000-0000-0000-00000000aaaa');
select t_check(jsonb_array_length(master_managers(:'lfa')) >= 3, 'master_managers');
select t_check(master_ajustar_saldo(:'lfa', :'m1', 25, 'compensación') = :'s0'::numeric + 75, 'ajuste +25');
select t_debe_fallar(format('select master_ajustar_saldo(%L, %L, -999999, %L)', :'lfa', :'m1', 'x'), 'el saldo no queda negativo');
select t_debe_fallar(format('select master_ajustar_saldo(%L, %L, 5, %L)', :'lfa', :'m1', ''), 'exige motivo');
select master_activar_codigo(:'cod', false);
select t_check(not (select activo from codigos_promo where id = :'cod'), 'desactivar código');

select id as pc from partidos where estado = 'cerrado' limit 1 \gset
select t_debe_fallar(format('select master_forzar_estado(%L, %L, %L)', :'pc', 'post_partido', 'x'), 'un partido cerrado no se reabre');
select id as pa from partidos where estado not in ('cerrado') limit 1 \gset
select master_forzar_estado(:'pa', 'cancelado', 'lluvia');
select t_check((select estado from partidos where id = :'pa') = 'cancelado', 'forzar estado');
select t_check(jsonb_array_length(master_partidos(:'lfa')) > 0, 'master_partidos');
select t_check(jsonb_array_length(master_auditoria()) >= 6, 'todo queda auditado');

reset role;
set role anon;
select t_debe_fallar('select master_resumen()', 'anon no entra');
select t_debe_fallar(format('select canjear_codigo(%L, %L)', :'lfa', 'X'), 'anon no canjea');
reset role;
\echo '══════ ESCENARIO MÁSTER COMPLETADO SIN ERRORES ══════'
