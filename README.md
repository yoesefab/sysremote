# sysremote

`sysremote` is a Bash-based Linux remote administration toolkit for managing
multiple hosts over SSH. It provides one CLI for host validation, session
inspection, user and group administration, backups, restores, local audits,
maintenance tasks, cron scheduling, logs, benchmarks, and monitoring reports.

The project is designed around plain shell scripts, predictable configuration,
and optional concurrency modes for multi-host execution.

## Features

- Validate target hosts from an inventory file or inline host list.
- Run SSH administration commands across one or more Linux machines.
- Manage users and groups with root-aware safety checks.
- Create incremental `rsync` backups with optional compression and encryption.
- Restore compressed or encrypted archives.
- Run local security audits for sensitive permissions, failed logins, and open
  ports.
- Perform package maintenance and cleanup tasks.
- Register, list, and remove managed cron jobs.
- Archive logs and inspect recent history.
- Benchmark normal, forked, thread-pool, and subshell execution modes.
- Generate monitoring data and CSV/HTML reports.
- Optionally build native C helpers for fork and pthread based execution.

## Repository Layout

```text
bin/sysremote.sh          CLI entry point
lib/                     shared CLI, config, target, remote, and utility code
modules/                 command modules
modules/native/          optional C concurrency helpers
tests/smoke.sh           smoke test suite
demo-lab/                Docker-based SSH demo environment
tools/                   helper scripts for native benchmarks
sysremote.conf.example   example configuration
inventory.example        example host inventory
```

## Requirements

- Bash 4 or newer
- Linux or a Linux-compatible shell environment
- `ssh` for remote execution
- `rsync` for backups
- `tar` for compressed backup and restore workflows
- `openssl` for encrypted backup and restore workflows
- `gcc` and `make` only if building the optional native helpers
- Docker Compose only if using the demo lab

Some commands are sensitive by design and require root privileges unless
`--no-root-check` is used. Remote user-management commands use the configured
`REMOTE_SUDO` prefix, which defaults to `sudo -n`.

## Quick Start

Clone the repository and run the CLI directly:

```bash
git clone git@github.com:yoesefab/sysremote.git
cd sysremote
bash bin/sysremote.sh --help
```

Create local configuration files from the examples:

```bash
cp sysremote.conf.example sysremote.conf
cp inventory.example inventory
```

Validate local targets:

```bash
bash bin/sysremote.sh -i inventory validate-hosts
```

Run a command against inline hosts:

```bash
bash bin/sysremote.sh -m localhost,127.0.0.1 sessions who
```

Use dry-run mode before making changes:

```bash
bash bin/sysremote.sh -n -m server1.example.com create-user deploy
```

## Configuration

Use `-c` or `--config` to load a specific config file:

```bash
bash bin/sysremote.sh -c ./sysremote.conf -i ./inventory validate-hosts
```

Important settings from `sysremote.conf.example`:

```bash
SSH_USER="${USER}"
SSH_PORT="22"
SSH_TIMEOUT="5"
INVENTORY_FILE=""
REQUIRE_ROOT="true"
REMOTE_SUDO="sudo -n"
THREAD_JOBS="4"
LOG_DIR="./logs"
DEFAULT_BACKUP_DIR="./backups"
ARCHIVE_DIR="./archives"
REPORT_DIR="./reports"
SEUIL_ALERTE="80"
```

Target inventories are plain text files with one DNS name or IPv4 address per
line. Blank lines and comments are ignored.

## Common Commands

Show help and version:

```bash
bash bin/sysremote.sh --help
bash bin/sysremote.sh --version
```

Validate hosts:

```bash
bash bin/sysremote.sh -i inventory validate-hosts
bash bin/sysremote.sh -m host1,host2 validate-hosts
```

Inspect remote sessions:

```bash
bash bin/sysremote.sh -i inventory sessions who
bash bin/sysremote.sh -i inventory sessions w
```

Manage users and groups:

```bash
bash bin/sysremote.sh -i inventory create-user deploy
bash bin/sysremote.sh -i inventory add-user-group deploy sudo
bash bin/sysremote.sh -i inventory lock-user deploy
bash bin/sysremote.sh -i inventory unlock-user deploy
bash bin/sysremote.sh -i inventory delete-user deploy
```

Create backups:

```bash
bash bin/sysremote.sh backup -S /etc -D ./backups --tag etc
bash bin/sysremote.sh backup -S /var/www -D ./backups --compress
bash bin/sysremote.sh backup -S /var/www -D ./backups --encrypt
```

Restore an archive:

```bash
bash bin/sysremote.sh restore -A ./backups/snap-example.tar.gz -T ./restore
```

Run audits and maintenance:

```bash
bash bin/sysremote.sh audit --all
bash bin/sysremote.sh maintain --update --clean
```

Schedule managed cron jobs:

```bash
bash bin/sysremote.sh schedule --add "0 2 * * *" "/path/to/job.sh"
bash bin/sysremote.sh schedule --list
bash bin/sysremote.sh schedule --remove
```

View and archive logs:

```bash
bash bin/sysremote.sh logs -n 100
bash bin/sysremote.sh archive-logs ./archives
```

Run concurrency benchmarks:

```bash
bash bin/sysremote.sh benchmark light
bash bin/sysremote.sh benchmark medium
bash bin/sysremote.sh benchmark heavy
```

## Concurrency Modes

Remote multi-host execution supports these modes:

- `normal`: run hosts one after another.
- `fork`: start one background process per host.
- `thread`: use `xargs -P` with the configured worker count.
- `subshell`: run the normal mode inside a subshell.

Examples:

```bash
bash bin/sysremote.sh -f -i inventory sessions who
bash bin/sysremote.sh -t -j 8 -i inventory sessions who
bash bin/sysremote.sh -s -i inventory sessions who
```

## Native Helpers

The main CLI does not require native binaries. Optional C helpers are available
under `modules/native/` for fork and pthread based execution experiments.

Build them with:

```bash
make native
```

The compiled binaries are written to `build/native/`.

Clean them with:

```bash
make native-clean
```

## Demo Lab

`demo-lab/` contains a Docker Compose environment with three SSH nodes exposed
on local ports `2222`, `2223`, and `2224`.

```bash
cd demo-lab
docker compose up --build
./test_nodes.sh
```

The demo SSH material is for local testing only. Do not reuse it for real
systems.

## Testing

Run the smoke test suite:

```bash
make test
```

Check native helper scripts and build the C helpers:

```bash
make native-check
make native
```

## Safety Notes

- Prefer `--dry-run` before backup, maintenance, scheduling, restore, or user
  administration changes.
- Keep real host inventories and credentials out of git.
- Review `REMOTE_SUDO`, `SSH_USER`, `SSH_PORT`, and `SSH_TIMEOUT` before running
  remote commands.
- Encrypted backups prompt for a passphrase and require `openssl`.
- Root-sensitive operations are intentionally guarded by default.
