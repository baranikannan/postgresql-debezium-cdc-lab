#!/usr/bin/env bash
set -euo pipefail

SOURCE_HOST="${CDC_SOURCE_HOST:-192.168.29.211}"
TARGET_HOST="${CDC_TARGET_HOST:-192.168.29.214}"
CONNECT_HOST="${CDC_CONNECT_HOST:-192.168.29.213}"
SOURCE_DB="${CDC_SOURCE_DB:-inventory}"
TARGET_DB="${CDC_TARGET_DB:-targetdb}"
SOURCE_USER="${CDC_SOURCE_USER:-dbzuser}"
TARGET_USER="${CDC_TARGET_USER:-jdbcuser}"
TIMEOUT="${CDC_TIMEOUT:-60}"
TABLE="cdc_test"
state_file="${CDC_STATE_DIR:-.cdc-test-state}/latest"

fail() { printf 'CDC: FAIL\n%s\n' "$*" >&2; exit 1; }
read_state() { awk -F= -v key="$1" '$1 == key {print substr($0, index($0,$2))}' "$state_file"; }
: "${CDC_SOURCE_PASSWORD:?Set CDC_SOURCE_PASSWORD in the environment}"
: "${CDC_TARGET_PASSWORD:?Set CDC_TARGET_PASSWORD in the environment}"
[ -s "$state_file" ] || fail "Source test state is missing."

test_id="$(read_state test_id)"
table="$TABLE"
timestamp_column="$(read_state timestamp_column)"
source_sql="SELECT test_id, test_value, extract(epoch FROM \"$timestamp_column\"::timestamptz) FROM public.\"$table\" WHERE test_id='$test_id';"
target_sql="SELECT test_id, test_value, extract(epoch FROM \"$timestamp_column\"::timestamptz) FROM public.\"$table\" WHERE test_id='$test_id';"

source_record="$({ printf '%s\n' "$CDC_SOURCE_PASSWORD"; printf '%s\n' "$source_sql"; } | ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ansible@"$CONNECT_HOST" \
  "read -r PGPASSWORD; export PGPASSWORD; psql \"host=$SOURCE_HOST dbname=$SOURCE_DB user=$SOURCE_USER sslmode=prefer\" -v ON_ERROR_STOP=1 -Atq")"
[ -n "$source_record" ] || fail "Source record was not found."
IFS='|' read -r source_id source_value source_epoch <<< "$source_record"

deadline=$(( $(date +%s) + TIMEOUT ))
target_record=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  target_record="$({ printf '%s\n' "$CDC_TARGET_PASSWORD"; printf '%s\n' "$target_sql"; } | ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ansible@"$CONNECT_HOST" \
    "read -r PGPASSWORD; export PGPASSWORD; psql \"host=$TARGET_HOST dbname=$TARGET_DB user=$TARGET_USER sslmode=prefer\" -v ON_ERROR_STOP=1 -Atq" 2>/dev/null || true)"
  [ -n "$target_record" ] && break
  sleep 3
done
[ -n "$target_record" ] || fail "Target record was not found within ${TIMEOUT}s."
IFS='|' read -r target_id target_value target_epoch <<< "$target_record"
[ "$source_id" = "$target_id" ] || fail "Source and target IDs differ."
[ "$source_value" = "$target_value" ] || fail "Source and target test values differ."

timestamp_status="MATCH"
if [ "$source_epoch" != "$target_epoch" ]; then
  timestamp_status="DIFFERENT REPRESENTATION"
fi
printf 'TARGET CDC VERIFICATION\n-----------------------\nTest ID: %s\n\nSOURCE\n------\nRecord found: YES\nID: %s\nValue: %s\nTimestamp epoch: %s\n\nTARGET\n------\nRecord found: YES\nID: %s\nValue: %s\nTimestamp epoch: %s\n\nComparison\n----------\nRecord: MATCH\nValues: MATCH\nTimestamp: %s\nCDC: PASS\n' \
  "$test_id" "$source_id" "$source_value" "$source_epoch" "$target_id" "$target_value" "$target_epoch" "$timestamp_status"
