#!/usr/bin/env bash
set -euo pipefail

CONNECT_HOST="${CDC_CONNECT_HOST:-192.168.29.213}"
CONNECT_URL="${CDC_CONNECT_URL:-http://$CONNECT_HOST:8083}"
CONNECTOR_NAME="inventory-source-connector"
state_file="${CDC_STATE_DIR:-.cdc-test-state}/latest"

pass() { printf 'CDC processing: PASS\n'; }
fail() { printf 'CDC processing: FAIL\n%s\n' "$*" >&2; exit 1; }

service="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ansible@"$CONNECT_HOST" \
  "systemctl is-active kafka-connect.service")" || fail "Kafka Connect service is not reachable."
[ "$service" = "active" ] || fail "Kafka Connect service is $service."
curl -fsS "$CONNECT_URL/" >/dev/null || fail "Kafka Connect REST API is unavailable."

status="$(curl -fsS "$CONNECT_URL/connectors/$CONNECTOR_NAME/status")" || fail "Connector $CONNECTOR_NAME is not configured."
connector_state="$(printf '%s' "$status" | jq -r '.connector.state')"
task_count="$(printf '%s' "$status" | jq '.tasks | length')"
task_state="$(printf '%s' "$status" | jq -r '.tasks[0].state // "NONE"')"

printf 'DEBEZIUM CHECK\n--------------\nKafka Connect: RUNNING\nREST API: OK\nConnector: %s\nConnector state: %s\nTasks: %s\nTask count: %s\n' \
  "$CONNECTOR_NAME" "$connector_state" "$task_state" "$task_count"

if [ "$connector_state" != "RUNNING" ] || [ "$task_state" != "RUNNING" ]; then
  printf 'Error: %s\n' "$(printf '%s' "$status" | jq -r '.tasks[0].trace // .connector.trace // "No error returned"')"
  fail "Debezium connector is not running."
fi

[ -s "$state_file" ] || fail "Source test state is missing; run cdc-insert-test.sh first."
pass
