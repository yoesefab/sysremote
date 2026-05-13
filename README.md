# sysremote

Unified Bash/Linux administration project integrating remote user management,
SSH sessions, backup/restore, audit, maintenance, scheduling, monitoring,
logging, archiving, and benchmarking.

## Quick Start

```bash
chmod +x bin/sysremote.sh
./bin/sysremote.sh --help
./bin/sysremote.sh -l ./logs -m localhost validate-hosts
./bin/sysremote.sh -l ./logs benchmark light
./bin/sysremote.sh -l ./logs archive-logs ./archives
```

Use `-n` for dry-run remote workflows:

```bash
./bin/sysremote.sh -l ./logs -n -m srv1,srv2 sessions who
./bin/sysremote.sh -l ./logs -n backup -S ./docs -D ./backups --compress
```

## Layout

```text
bin/       entry point
lib/       shared CLI, config, logging, validation, target and SSH logic
modules/   integrated feature modules
modules/native/ optional C fork/pthread helpers from the concurrency lot
logs/      history.log runtime output
docs/      project reports and manual tests
tests/     smoke tests
assets/    optional static assets
build/     generated deliverables
backups/   local backup snapshots
archives/  compressed log archives
reports/   monitoring CSV/HTML reports
tools/     optional native benchmark and deliverable helpers
examples/  sample inventories and small source examples
```

## Logging

All stdout and stderr emitted through the main CLI is duplicated to:

```text
LOG_DIR/history.log
```

Format:

```text
YYYY-MM-DD-HH-MM-SS : user : INFOS|ERROR : message
```

## Main Commands

Run `./bin/sysremote.sh --help` for the complete option and command list.

## Optional Native Concurrency

Wafae's C fork/pthread helpers are integrated as optional sources:

```bash
make native
tools/native_benchmark.sh -H examples/hosts.txt -c uptime
```

The main CLI remains the supported runtime path.
