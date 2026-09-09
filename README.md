# postgresql-debezium-cdc-lab

Hands-on change data capture from PostgreSQL through Debezium, Kafka, Kafka Connect, and a JDBC sink.

```text
PostgreSQL Source → Debezium → Kafka → JDBC Sink → PostgreSQL Target
```

## Architecture

| Host | Component | Address | Key configuration |
|---|---|---:|---|
| `cdc-db-source` | PostgreSQL source | `192.168.29.211` | PostgreSQL 16.15, `inventory`, port `5432`, logical replication enabled |
| `cdc-kafka` | Apache Kafka broker | `192.168.29.212` | Kafka 4.3.1, KRaft, port `9092`, controller port `9093` |
| `cdc-connect` | Kafka Connect | `192.168.29.213` | Kafka Connect 4.3.1, REST API port `8083` |
| `cdc-db-target` | PostgreSQL target | `192.168.29.214` | PostgreSQL 16.15, `targetdb`, port `5432` |

All VMs are managed manually. Vagrant is not required.

## CDC configuration

| Item | Value |
|---|---|
| Source table | `public.cdc_test` |
| Source connector | `inventory-source-connector` |
| Kafka topic | `inventory.public.cdc_test` |
| JDBC sink connector | `inventory-jdbc-sink` |
| Target database | `targetdb` |
| Target table | `public.cdc_test` |

The source connector uses PostgreSQL logical decoding with the `pgoutput` plugin. The JDBC sink consumes the Debezium event and writes the record to the target database.

## Repository structure

```text
ansible/
├── site.yml
├── inventory/
├── group_vars/
├── host_vars/
└── roles/
    ├── common/
    ├── postgresql/
    ├── kafka/
    └── kafka_connect/

cdc-insert-test.sh
cdc-debezium-check.sh
cdc-kafka-check.sh
cdc-verify-target.sh
cdc-test.sh
health.sh
shutdown.sh
```

## Deployment

Run the Ansible deployment from WSL:

```bash
cd /mnt/c/Labs/debezium-cdc/ansible
ansible-playbook -i inventory/hosts.yml site.yml --ask-vault-pass
```

The playbook configures the existing VMs, services, connector plugins, firewall rules, and CDC connectors.

## Validation scripts

Run the complete end-to-end validation:

```bash
cd /mnt/c/Labs/debezium-cdc
./cdc-test.sh
```

Individual checks:

| Script | Purpose |
|---|---|
| `cdc-insert-test.sh` | Inserts one uniquely identified row into the source test table and saves its state in `.cdc-test-state/latest`. |
| `cdc-debezium-check.sh` | Checks Kafka Connect, the source connector, and its task state. |
| `cdc-kafka-check.sh` | Checks Kafka, the CDC topic, and event delivery. |
| `cdc-verify-target.sh` | Waits for and compares the source record and target record. |
| `cdc-test.sh` | Runs the insert, Debezium, Kafka, and target checks in order. |

The validation scripts use the existing SSH access and environment-provided database passwords; passwords are not stored in the scripts or printed in output.

