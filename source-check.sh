#!/usr/bin/env bash
set -euo pipefail

DBZ_PASS="${1:-}"
if [ -z "$DBZ_PASS" ]; then
  echo "Usage: $0 <dbz_password>"
  echo "Example: $0 'your_dbz_password'"
  exit 1
fi

REMOTE="ansible@192.168.29.213"
CONNECTOR_NAME="inventory-source-connector"

printf '\n== 1) Validate source DB connectivity from Connect ==\n'
ssh -o StrictHostKeyChecking=no "$REMOTE" "PGPASSWORD='$DBZ_PASS' psql \"host=192.168.29.211 port=5432 dbname=inventory user=dbzuser sslmode=prefer\" -Atqc \"SELECT current_database(), current_user, now();\""

printf '\n== 2) Create Debezium PostgreSQL source connector ==\n'
curl -sS -X POST http://192.168.29.213:8083/connectors \
  -H 'Content-Type: application/json' \
  --data @- <<JSON
{
  "name": "${CONNECTOR_NAME}",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",
    "database.hostname": "192.168.29.211",
    "database.port": "5432",
    "database.user": "dbzuser",
    "database.password": "${DBZ_PASS}",
    "database.dbname": "inventory",
    "database.server.name": "inventory",
    "plugin.name": "pgoutput",
    "slot.name": "debezium_inventory_slot",
    "publication.name": "dbz_publication",
    "publication.autocreate.mode": "filtered",
    "table.include.list": "public.*",
    "topic.prefix": "inventory",
    "schema.include.list": "public",
    "snapshot.mode": "initial"
  }
}
JSON

printf '\n== 3) Check connector status ==\n'
curl -sS http://192.168.29.213:8083/connectors/${CONNECTOR_NAME}/status

printf '\n== 4) List active connectors ==\n'
curl -sS http://192.168.29.213:8083/connectors
