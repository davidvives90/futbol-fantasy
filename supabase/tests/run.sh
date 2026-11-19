#!/usr/bin/env bash
# Reproduce producción y prueba la ampliación encima, con datos de la versión 0.1 ya existentes.
#  1. stubs de Supabase + desplegado_v01/ (0001–0009, copia exacta de producción) + plataforma/0101
#  2. escenarios de la 0.1 (escenario.sql, escenario_mercado.sql): dejan ligas con plantillas y alineaciones
#  3. permisos por defecto como en Supabase (tablas nuevas: todo a anon/authenticated; funciones: authenticated)
#  4. migraciones nuevas migrations/0010…0099 (aditivas) y escenario_ampliacion.sql
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

for f in migrations/00[1-9][0-9]_*.sql; do aplicar "$f"; done
aplicar tests/escenario_ampliacion.sql
