# Storytelling Demo Test Plan

## Summary

This document is a presentation-ready demo script for sysremote in the Docker
demo lab.

Storyline: we have one Linux demo machine, sysremote reaches it through SSH,
controls it safely from one CLI, and leaves proof through logs, reports,
archives, backups, restores, audits, monitoring, and concurrency tests.

Expected duration: 10 to 15 minutes.

Demo lab node:

- `sysremote-node1` on `localhost:2222`

SSH uses `demo-lab/ssh/sysremote_demo`. This demo intentionally uses only one
machine so the presentation stays simple and easy to follow.

## Presenter Checklist

Before starting:

- Docker is installed and the demo lab is running.
- SSH connectivity to `sysremote-node1` was verified with the demo key.
- The terminal is opened at the repository root.
- Keep this file open beside the terminal.
- Use `/tmp` paths so the demo does not depend on old local files.
- Do not run real notification delivery unless Discord or email secrets are
  configured.

## Setup

What to say:

> I am preparing a clean workspace for the demo. All temporary logs, backups,
> reports, and restore tests go under `/tmp`, so the demo is repeatable and does
> not depend on previous runs.

```bash
cd /home/youssef/Documents/Github/sysremote

export LOG_DIR=/tmp/sysremote-test-logs
export TEST_ROOT=/tmp/sysremote-manual-test
export DEMO_PORT=2222
rm -rf "$TEST_ROOT"
mkdir -p "$LOG_DIR" "$TEST_ROOT"
chmod 600 demo-lab/ssh/sysremote_demo
```

If SSH shows `Bad owner or permissions on
/etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf`, use a temporary SSH wrapper
for tests:

```bash
export SYSREMOTE_ROOT="$PWD"
mkdir -p /tmp/sysremote-ssh-wrap

cat >/tmp/sysremote-ssh-wrap/ssh <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/ssh -F /dev/null -i "$SYSREMOTE_ROOT/demo-lab/ssh/sysremote_demo" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"
EOF

cat >/tmp/sysremote-ssh-wrap/scp <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/scp -F /dev/null -i "$SYSREMOTE_ROOT/demo-lab/ssh/sysremote_demo" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"
EOF

chmod +x /tmp/sysremote-ssh-wrap/ssh /tmp/sysremote-ssh-wrap/scp
export PATH="/tmp/sysremote-ssh-wrap:$PATH"
```

Expected output to point at:

- The setup commands produce no error.
- `demo-lab/ssh/sysremote_demo` has secure permissions.
- `$LOG_DIR` and `$TEST_ROOT` exist under `/tmp`.

## Act 1: The Lab Is Alive

Goal: prove that the demo machine exists and that direct SSH works before using
sysremote.

What to say:

> First I show the infrastructure. This container plays the role of a remote
> Linux machine. Then I connect to it with SSH and ask it for its hostname and
> current user.

```bash
docker compose -f demo-lab/compose.yml ps node1

ssh -F /dev/null -i demo-lab/ssh/sysremote_demo -p "$DEMO_PORT" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  demo@localhost 'hostname && whoami'
```

Expected output to point at:

- Docker shows `sysremote-node1` as `Up`.
- SSH returns `node1`.
- The connected user is `demo`.

## Act 2: Sysremote Understands Targets

Goal: show that sysremote has a real CLI surface, validates targets, and passes
basic project checks.

What to say:

> Now I move from raw SSH to the sysremote tool. I show the command interface,
> confirm the version, validate a target, and run the smoke tests that prove the
> integrated scripts still work together.

```bash
find bin lib modules tools tests demo-lab -type f -name '*.sh' -exec bash -n {} \;
make test
make native-check
```

```bash
./bin/sysremote.sh --help
./bin/sysremote.sh --version
./bin/sysremote.sh -l "$LOG_DIR" -m localhost validate-hosts
```

Expected output to point at:

- `make test` prints `smoke tests passed`.
- `make native-check` completes without syntax errors.
- `--help` lists the supported commands.
- `--version` prints `sysremote v1.0.0`.
- `validate-hosts` prints `localhost OK`.

## Act 3: Remote Admin From One CLI

Goal: show sysremote running remote commands and safely managing a user account
on the demo machine.

What to say:

> This is the remote administration part. The same CLI checks active sessions
> and runs a complete user lifecycle: create, lock, unlock, add to group,
> remove from group, and delete.

```bash
./bin/sysremote.sh -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -T 5 -m localhost sessions who
./bin/sysremote.sh -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -T 5 -m localhost sessions w
```

```bash
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost create-user srtest
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost lock-user srtest
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost unlock-user srtest
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost add-user-group srtest sudo
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost remove-user-group srtest sudo
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost delete-user srtest
```

Expected output to point at:

- Each remote command starts with the target host marker.
- Session commands return normal Linux session output.
- User lifecycle commands finish without SSH or remote command errors.
- `-N` is used because elevation happens on the remote side with the demo user.

## Act 4: Safety Net

Goal: demonstrate backup, compressed backup, encrypted backup, and restore.

What to say:

> Administration is not only changing systems. It also needs a safety net. Here
> I create test data, back it up, compress it, encrypt it, and restore it to a
> separate location.

```bash
mkdir -p "$TEST_ROOT/source/config" "$TEST_ROOT/source/data"
echo "port=8080" > "$TEST_ROOT/source/config/app.conf"
echo "hello" > "$TEST_ROOT/source/data/file.txt"

./bin/sysremote.sh -l "$LOG_DIR" backup -S "$TEST_ROOT/source" -D "$TEST_ROOT/backups" --tag snap1
./bin/sysremote.sh -l "$LOG_DIR" backup -S "$TEST_ROOT/source" -D "$TEST_ROOT/backups" --tag snap2 --compress
printf 'test1234\ntest1234\n' | ./bin/sysremote.sh -l "$LOG_DIR" backup -S "$TEST_ROOT/source" -D "$TEST_ROOT/backups" --tag snap3 --compress --encrypt

./bin/sysremote.sh -N -l "$LOG_DIR" restore -A "$TEST_ROOT/backups/snap2.tar.gz" -T "$TEST_ROOT/restore"
printf 'test1234\n' | ./bin/sysremote.sh -N -l "$LOG_DIR" restore -A "$TEST_ROOT/backups/snap3.tar.gz.enc" -T "$TEST_ROOT/restore-enc"
```

Optional proof checks:

```bash
find "$TEST_ROOT/backups" -maxdepth 1 -type f -o -type d
find "$TEST_ROOT/restore" "$TEST_ROOT/restore-enc" -type f
```

Expected output to point at:

- `backup complete` appears for each backup.
- `snap1` exists as a directory.
- `snap2.tar.gz` exists as a compressed archive.
- `snap3.tar.gz.enc` exists as an encrypted archive.
- `restore complete` appears for both restore commands.

## Act 5: Security and Health

Goal: show local security audit, safe maintenance planning, schedule planning,
and remote monitoring with CSV/HTML reports.

What to say:

> Now I switch to visibility and hygiene. Sysremote can audit permissions,
> login traces, and open ports. For risky operations like maintenance and cron,
> I use dry-run mode during the presentation. Then I collect health metrics and
> generate reports.

```bash
./bin/sysremote.sh -l "$LOG_DIR" audit --perms
./bin/sysremote.sh -l "$LOG_DIR" audit --ports
./bin/sysremote.sh -l "$LOG_DIR" audit --logins
./bin/sysremote.sh -l "$LOG_DIR" audit --all
```

```bash
./bin/sysremote.sh -N -n -l "$LOG_DIR" maintain --update --clean
./bin/sysremote.sh -N -n -l "$LOG_DIR" schedule --add "*/5 * * * *" "./bin/sysremote.sh monitor --check"
./bin/sysremote.sh -l "$LOG_DIR" schedule --list
./bin/sysremote.sh -N -n -l "$LOG_DIR" schedule --remove
```

```bash
./bin/sysremote.sh -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost monitor --check --alert 80 --csv --html
./bin/sysremote.sh -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost metrics --check
```

Expected output to point at:

- Audit prints a `SYSREMOTE AUDIT REPORT`.
- Dry-run maintenance prints the intended update and cleanup action.
- Dry-run schedule prints the cron line it would install or remove.
- Monitoring prints `status=OK` or an alert status for the demo machine.
- CSV and HTML report paths are printed.

## Act 6: Proof and Performance

Goal: prove that sysremote records what happened, can archive logs, and can show
execution performance with benchmark and native concurrency helpers.

What to say:

> A demo is stronger when it leaves evidence. I finish by showing the log
> history, archiving it with a manifest, and comparing execution modes.

```bash
./bin/sysremote.sh -l "$LOG_DIR" logs -n 30
./bin/sysremote.sh -l "$LOG_DIR" archive-logs "$TEST_ROOT/archives"
tar -tzf "$TEST_ROOT"/archives/sysremote-logs-*.tar.gz
```

```bash
./bin/sysremote.sh -l "$LOG_DIR" benchmark light
./bin/sysremote.sh -l "$LOG_DIR" benchmark medium
./bin/sysremote.sh -l "$LOG_DIR" benchmark heavy
```

```bash
make native

printf 'localhost\n' > "$TEST_ROOT/hosts-node1.txt"

tools/native_parallel.sh -q -H "$TEST_ROOT/hosts-node1.txt" -u demo -p "$DEMO_PORT" -- hostname
tools/native_parallel.sh -s -H "$TEST_ROOT/hosts-node1.txt" -u demo -p "$DEMO_PORT" -- hostname
tools/native_parallel.sh -f -H "$TEST_ROOT/hosts-node1.txt" -u demo -p "$DEMO_PORT" -- hostname
tools/native_parallel.sh -t -H "$TEST_ROOT/hosts-node1.txt" -u demo -p "$DEMO_PORT" -- hostname
```

Expected output to point at:

- `logs -n 30` shows recent sysremote actions.
- `archive-logs` creates a `.tar.gz` file.
- `tar -tzf` shows archived logs and `manifest.txt`.
- Benchmarks print `elapsed_ms` for normal, fork, thread, and subshell modes.
- Native parallel modes print successful host execution.

## Closing Line

What to say:

> In this demo, sysremote started from one SSH-accessible Linux machine and gave
> us one consistent administration workflow: validate, operate, protect, audit,
> monitor, log, archive, and compare execution modes.

## Demo Day Fallbacks

### Container Is Not Running

```bash
docker compose -f demo-lab/compose.yml up -d node1
docker compose -f demo-lab/compose.yml ps node1
```

### SSH Config Permission Error

Use the temporary SSH wrapper from the setup section. It runs SSH with
`-F /dev/null` and the demo key.

### User Already Exists

Clean the demo user on the node, then rerun Act 3.

```bash
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost delete-user srtest
```

If the lab state is too messy, restart the container.

```bash
docker compose -f demo-lab/compose.yml stop node1
docker compose -f demo-lab/compose.yml up -d node1
```

### Restore Requires Privilege

Keep `-N` and restore into a local `/tmp` path:

```bash
./bin/sysremote.sh -N -l "$LOG_DIR" restore -A "$TEST_ROOT/backups/snap2.tar.gz" -T "$TEST_ROOT/restore"
```

### Notification Secrets Are Missing

Skip `--notify`. The demo still proves monitoring through console output, CSV,
HTML, and logs.

## Expected Results

- Docker shows `sysremote-node1` as `Up`.
- SSH checks return `node1`.
- `make test` prints `smoke tests passed`.
- CLI commands exit `0` for valid cases.
- Backup creates `snap1`, `snap2.tar.gz`, and `snap3.tar.gz.enc`.
- Restore recreates files under `$TEST_ROOT/restore` and `$TEST_ROOT/restore-enc`.
- Monitoring updates CSV and HTML reports.
- Logs are visible through `logs -n`.
- Archive command creates a `.tar.gz` file with a manifest.
- Benchmarks and native parallel modes print successful execution.

## Assumptions

- This presentation intentionally uses only `sysremote-node1` on
  `localhost:2222`.
- Do not test real `maintain --update --clean` without `-n`; dry-run is enough
  for demo safety.
- Do not test real notification delivery unless Discord or email secrets are
  configured.
- `tools/native_benchmark.sh` is not a good fit for this port-mapped demo lab
  because it has no user or port options; use `benchmark` and
  `tools/native_parallel.sh` for lab validation.
