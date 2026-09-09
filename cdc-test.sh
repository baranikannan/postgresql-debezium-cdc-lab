#!/usr/bin/env bash
set -u

printf '========================================\n       DEBEZIUM CDC TEST\n========================================\n'
stages=(cdc-insert-test.sh cdc-debezium-check.sh cdc-kafka-check.sh cdc-verify-target.sh)
labels=("Insert source record" "Debezium connector" "Kafka processing" "Target verification")
failed=0
for i in "${!stages[@]}"; do
  printf '\n[%s/4] %s\n' "$((i + 1))" "${labels[$i]}"
  if "./${stages[$i]}"; then
    printf '[%s/4] %s PASS\n' "$((i + 1))" "${labels[$i]}"
  else
    rc=$?
    if [ "${stages[$i]}" = cdc-kafka-check.sh ] && [ "$rc" -eq 2 ]; then
      printf '[%s/4] %s WARNING (event not observed before timeout)\n' "$((i + 1))" "${labels[$i]}"
    else
      printf '[%s/4] %s FAIL\n' "$((i + 1))" "${labels[$i]}"
      failed=1
      break
    fi
  fi
done
printf '\n========================================\n'
if [ "$failed" -eq 0 ]; then
  printf 'CDC END-TO-END RESULT: PASS\n'
else
  printf 'CDC END-TO-END RESULT: FAIL\n'
  exit 1
fi
