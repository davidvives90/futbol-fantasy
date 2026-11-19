#!/usr/bin/env bash
# Aplica stubs + migraciones en una base limpia "ff_test" y ejecuta el escenario.
# Uso: PGHOST=/tmp PGUSER=postgres bash tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
psql -q -d postgres -c "drop database if exists ff_test" -c "create database ff_test"
for f in tests/00_stubs.sql migrations/*.sql; do
  echo "== $f"
  psql -q -d ff_test -v ON_ERROR_STOP=1 -f "$f"
done
echo "== tests/escenario.sql"
psql -q -d ff_test -v ON_ERROR_STOP=1 -f tests/escenario.sql
echo "== tests/escenario_mercado.sql"
psql -q -d ff_test -v ON_ERROR_STOP=1 -f tests/escenario_mercado.sql
