#!/usr/bin/env bash
set -euo pipefail

KAFKA_HOST="${CDC_KAFKA_HOST:-192.168.29.212}"
CONNECT_URL="${CDC_CONNECT_URL:-http://192.168.29.213:8083}"
TIMEOUT="${CDC_TIMEOUT:-120}"
TOPIC="inventory.public.cdc_test"
STATE_DIR="${CDC_STATE_DIR:-.cdc-test-state}"
state_file="$STATE_DIR/latest"

fail() { printf 'Processing: FAIL\n%s\n' "$*" >&2; exit 1; }
read_state() { awk -F= -v key="$1" '$1 == key {print substr($0, index($0,$2))}' "$state_file"; }

[ -s "$state_file" ] || fail "Source test state is missing; run cdc-insert-test.sh first."
test_id="$(read_state test_id)"
service="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ansible@"$KAFKA_HOST" "systemctl is-active kafka-kraft.service")" || fail "Kafka host is unreachable."
[ "$service" = active ] || fail "Kafka service is $service."
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ansible@"$KAFKA_HOST" "ss -lnt | grep -q ':9092 '" || fail "Kafka port 9092 is not listening."

ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ansible@"$KAFKA_HOST" \
  "/opt/kafka/bin/kafka-topics.sh --bootstrap-server cdc-kafka:9092 --describe --topic '$TOPIC'" >/dev/null \
  || fail "CDC topic does not exist: $TOPIC"

deadline=$(( $(date +%s) + TIMEOUT ))
found=false
while [ "$(date +%s)" -lt "$deadline" ]; do
  if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ansible@"$KAFKA_HOST" \
      "/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server cdc-kafka:9092 --topic '$TOPIC' --from-beginning --timeout-ms 5000" 2>/dev/null |
      grep -Fq "$test_id"; then found=true; break; fi
  sleep 3
done

printf 'KAFKA CDC CHECK\n---------------\nKafka service : RUNNING\nKafka port    : LISTENING\nBroker        : OK\nCDC topic     : %s\nTopic         : EXISTS\n' "$TOPIC"
if [ "$found" = true ]; then
  printf 'Test event   : FOUND\nProcessing    : PASS\n'
else
  printf 'Test event   : NOT FOUND\nProcessing    : WAITING\n'
  exit 2
fi
