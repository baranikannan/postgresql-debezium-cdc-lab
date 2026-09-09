#!/usr/bin/env bash
set -euo pipefail

SOURCE_HOST="${CDC_SOURCE_HOST:-192.168.29.211}"
CONNECT_HOST="${CDC_CONNECT_HOST:-192.168.29.213}"
SOURCE_DB="${CDC_SOURCE_DB:-inventory}"
SOURCE_USER="${CDC_SOURCE_USER:-dbzuser}"
TABLE="cdc_test"
STATE_DIR="${CDC_STATE_DIR:-.cdc-test-state}"
STATE_FILE="$STATE_DIR/latest"

pass() { printf 'Status: PASS\n'; }
fail() { printf 'Status: FAIL\n%s\n' "$*" >&2; exit 1; }

: "${CDC_SOURCE_PASSWORD:?Set CDC_SOURCE_PASSWORD in the environment}"
mkdir -p "$STATE_DIR"

remote_psql() {
  local sql="$1"
  { printf '%s\n' "$CDC_SOURCE_PASSWORD"; printf '%s\n' "$sql"; } | ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    "ansible@$CONNECT_HOST" \
    "read -r PGPASSWORD; export PGPASSWORD; psql \"host=$SOURCE_HOST dbname=$SOURCE_DB user=$SOURCE_USER sslmode=prefer\" -v ON_ERROR_STOP=1 -Atq"
}

export CDC_SOURCE_PASSWORD
table_info="$(remote_psql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='$TABLE';")"
[ "$table_info" = "1" ] || fail "Required table public.$TABLE does not exist."
table="$TABLE"
timestamp_column="test_timestamp"
timestamp_info="$(remote_psql "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='$table' AND column_name='$timestamp_column';")"
[ "$timestamp_info" = "1" ] || fail "Required column public.$table.$timestamp_column does not exist."

test_id="CDC_TEST_$(date -u +%Y%m%dT%H%M%S%NZ)"
test_value="CDC validation $test_id"
inserted_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

remote_psql "INSERT INTO public.\"$table\" (test_id, test_value, \"$timestamp_column\") VALUES ('$test_id', '$test_value', '$inserted_at');"
umask 077
printf '%s\n' "test_id=$test_id" "test_value=$test_value" "timestamp=$inserted_at" "timestamp_column=$timestamp_column" "table=$table" > "$STATE_FILE"

printf 'SOURCE TEST\n-----------\nTest ID: %s\nTable: %s\nInserted ID: %s\nInserted timestamp: %s\n' \
  "$test_id" "$table" "$test_id" "$inserted_at"
pass
