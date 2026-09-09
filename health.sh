#!/usr/bin/env bash

set -u

SSH_USER="${1:-ansible}"
SSH_OPTS="-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no"

declare -A NODES=(
  [cdc-db-source]="192.168.29.211"
  [cdc-kafka]="192.168.29.212"
  [cdc-connect]="192.168.29.213"
  [cdc-db-target]="192.168.29.214"
)

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }

run_remote() {
  local ip="$1"
  local cmd="$2"
  ssh $SSH_OPTS "${SSH_USER}@${ip}" "$cmd" 2>/dev/null
}

echo "============================================================"
echo " CDC LAB - SSH HEALTH CHECK"
echo " SSH user : ${SSH_USER}"
echo " Date     : $(date)"
echo "============================================================"

for name in "${!NODES[@]}"; do
  ip="${NODES[$name]}"

  echo
  echo "------------------------------------------------------------"
  echo "$name ($ip)"
  echo "------------------------------------------------------------"

  if run_remote "$ip" "true"; then
    green "SSH             : OK"
  else
    red "SSH             : FAILED"
    continue
  fi

  printf "Hostname        : "
  run_remote "$ip" "hostname"

  printf "OS              : "
  run_remote "$ip" "grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2-"

  printf "IP              : "
  run_remote "$ip" "ip -4 addr show | awk '/inet 192\\.168\\.29\\./ {print \$2}'"

  printf "Disk /          : "
  run_remote "$ip" "df -h / | awk 'NR==2 {print \$5, \"used\", \$4, \"free\"}'"

  if [[ "$name" == "cdc-db-source" || "$name" == "cdc-db-target" ]]; then

    if run_remote "$ip" "systemctl is-active --quiet postgresql-16"; then
      green "PostgreSQL      : RUNNING"
    else
      red "PostgreSQL      : NOT RUNNING"
    fi

    printf "Port 5432       : "
    if run_remote "$ip" "ss -lnt | grep -q ':5432 '"; then
      green "LISTENING"
    else
      red "NOT LISTENING"
    fi

    printf "Version         : "
    run_remote "$ip" 'sudo -n -u postgres psql -d postgres -tAc "SELECT version();" 2>/dev/null | cut -d"," -f1'

    if [[ "$name" == "cdc-db-source" ]]; then

      printf "wal_level       : "
      run_remote "$ip" 'sudo -n -u postgres psql -d postgres -tAc "SHOW wal_level;"'

      printf "dbzuser         : "
      run_remote "$ip" 'sudo -n -u postgres psql -d postgres -tAc "SELECT rolname || '\'' | replication='\'' || rolreplication FROM pg_roles WHERE rolname='\''dbzuser'\'';"'

    else

      printf "Target DB       : "
      run_remote "$ip" 'sudo -n -u postgres psql -d targetdb -tAc "SELECT current_database();" 2>/dev/null'

    fi
  fi

  if [[ "$name" == "cdc-kafka" ]]; then

    if run_remote "$ip" "systemctl is-active --quiet kafka-kraft"; then
      green "Kafka           : RUNNING"
    else
      red "Kafka           : NOT RUNNING"
    fi

    printf "Port 9092       : "
    if run_remote "$ip" "ss -lnt | grep -q ':9092 '"; then
      green "LISTENING"
    else
      red "NOT LISTENING"
    fi

    printf "Java            : "
    run_remote "$ip" "java -version 2>&1 | head -1"

    printf "Kafka process   : "
    run_remote "$ip" "pgrep -af 'kafka.Kafka|kafka-server' | head -1 || true"

  fi

  if [[ "$name" == "cdc-connect" ]]; then

    if run_remote "$ip" "systemctl is-active --quiet kafka-connect"; then
      green "Kafka Connect   : RUNNING"
    else
      red "Kafka Connect   : NOT RUNNING"
    fi

    printf "Port 8083       : "
    if run_remote "$ip" "ss -lnt | grep -q ':8083 '"; then
      green "LISTENING"
    else
      red "NOT LISTENING"
    fi

    printf "Java            : "
    run_remote "$ip" "java -version 2>&1 | head -1"

    printf "Connect REST    : "
    if run_remote "$ip" "curl -fsS --max-time 5 http://localhost:8083/ >/dev/null"; then
      green "OK"
    else
      red "FAILED"
    fi

    printf "Connectors      : "
    run_remote "$ip" "curl -fsS --max-time 5 http://localhost:8083/connectors 2>/dev/null || true"

  fi

done

echo
echo "============================================================"
echo " Health check complete"
echo "============================================================"
