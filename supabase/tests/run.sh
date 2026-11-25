#!/usr/bin/env bash
# Reproduce producción y prueba la ampliación encima, con datos de la versión 0.1 ya existentes.
#  1. stubs de Supabase + desplegado_v01/ (0001–0009, copia exacta de producción) + plataforma/0101
#  2. escenarios de la 0.1 (escenario.sql, escenario_mercado.sql): dejan ligas con plantillas y alineaciones
#  3. permisos por defecto como en Supabase (tablas nuevas: todo a anon/authenticated; funciones: authenticated)
#  4. desplegado_v02/ (0010–0014, copia exacta de producción) y escenario_ampliacion.sql
#  5. migraciones nuevas migrations/0015+ (aditivas) y escenario_v03.sql
# Uso: PGHOST=/tmp PGUSER=postgres bash tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
psql -q -d postgres -c "drop database if exists ff_test" -c "create database ff_test"
aplicar() { echo "== $1"; psql -q -d ff_test -v ON_ERROR_STOP=1 -f "$1"; }

aplicar tests/00_stubs.sql
for f in desplegado_v01/*.sql; do aplicar "$f"; done
aplicar plataforma/0101_endurecer_funciones.sql
aplicar tests/escenario.sql
aplicar tests/escenario_mercado.sql

echo "== permisos por defecto de Supabase"
psql -q -d ff_test -v ON_ERROR_STOP=1 <<'SQL'
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;
alter default privileges in schema public grant execute on functions to authenticated;
SQL

for f in desplegado_v02/*.sql; do aplicar "$f"; done
aplicar tests/escenario_ampliacion.sql

# 5. v0.3: migraciones nuevas (0015+) sobre los datos de todos los escenarios anteriores
for f in migrations/00*.sql; do
  n=$(basename "$f" | cut -c1-4)
  # 0041+ cambia la convocatoria (fijos pendientes): se aplica tras las pruebas antiguas
  if [ "$n" -ge 15 ] && [ "$n" -le 40 ] 2>/dev/null; then aplicar "$f"; fi
done
# Pruebas antiguas: ligas nuevas en modo clásico (fijos inscritos solos); escenario_apertura prueba el modo nuevo
psql -q -d ff_test -c "alter table ligas alter column modo_convocatoria set default 'clasica'" \
  -c "alter table ligas alter column reparto_inicial set default 0" -c "alter table ligas alter column factor_presupuesto set default 6.5" \
  -c "update ligas set reparto_inicial = 0, factor_presupuesto = 6.5"
aplicar tests/escenario_v03.sql
aplicar tests/escenario_votacion.sql
aplicar tests/escenario_master.sql
aplicar tests/escenario_notif.sql
aplicar tests/escenario_perfil.sql
aplicar tests/escenario_ligas_v042.sql
aplicar tests/escenario_mvp_pocos.sql
aplicar tests/escenario_apertura.sql
aplicar tests/escenario_reparto.sql
aplicar tests/escenario_xg.sql
aplicar tests/escenario_errores.sql
aplicar tests/escenario_estadisticas.sql
aplicar tests/escenario_eliminar.sql
aplicar tests/escenario_reglamento.sql
aplicar tests/escenario_temporadas.sql
aplicar tests/escenario_extras.sql
aplicar tests/escenario_idioma.sql
aplicar tests/escenario_fantasy_sencillo.sql
aplicar tests/escenario_mas_sencillo.sql
aplicar tests/escenario_responder_aviso.sql
# 6. v0.6: convocatoria sencilla (0041+)
for f in migrations/00*.sql; do
  n=$(basename "$f" | cut -c1-4)
  if [ "$n" -ge 41 ] 2>/dev/null; then aplicar "$f"; fi
done
aplicar tests/escenario_convocatoria_sencilla.sql
aplicar tests/escenario_agenda.sql
aplicar tests/escenario_fantasy_valor.sql
aplicar tests/escenario_tienda.sql
aplicar tests/escenario_postpartido_ponderado.sql
aplicar tests/escenario_modos.sql
aplicar tests/escenario_fase1.sql
aplicar tests/escenario_fase2.sql
