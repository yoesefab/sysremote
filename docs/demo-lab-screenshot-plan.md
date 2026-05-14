# Demo Lab Screenshot Plan

Use this checklist to capture clean screenshots for the final report. Each part
has one purpose, the commands to execute, and the description to put under the
screenshot.

## Setup Before Screenshots

Run this once before taking screenshots:

```bash
cd /home/youssef/Documents/Github/sysremote

export LOG_DIR=/tmp/sysremote-test-logs
export TEST_ROOT=/tmp/sysremote-manual-test
export DEMO_PORT=2222
rm -rf "$TEST_ROOT"
mkdir -p "$LOG_DIR" "$TEST_ROOT"
chmod 600 demo-lab/ssh/sysremote_demo
clear
```

Sysremote uses the system `ssh` command internally and does not have a separate
`-i` option for the demo key. Run this wrapper before any sysremote SSH command:

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

Screenshot description:

> Preparation of a clean demo workspace. Logs, backups, restores, and generated
> reports are stored under `/tmp` to keep the test reproducible.

## Screenshot 1: Demo Lab Container Running

Execute:

```bash
docker compose -f demo-lab/compose.yml ps node1
```

Take the screenshot when:

- The terminal shows `sysremote-node1`.
- The status is `Up`.
- The port mapping shows `localhost:2222` or `0.0.0.0:2222->22/tcp`.

Screenshot description:

> Docker demo lab status. The machine `sysremote-node1` is running and exposes
> SSH on local port `2222`, which will be used as the remote Linux target.

## Screenshot 2: Direct SSH Connectivity

Execute:

```bash
ssh -F /dev/null -i demo-lab/ssh/sysremote_demo -p "$DEMO_PORT" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  demo@localhost 'hostname && whoami'
```

Take the screenshot when:

- The output shows `node1`.
- The output shows `demo`.

Screenshot description:

> Direct SSH verification before using sysremote. The host returns `node1` and
> the connected user is `demo`, proving that the demo machine is reachable.

## Screenshot 3: Sysremote Help and Version

Execute:

```bash
./bin/sysremote.sh --version
./bin/sysremote.sh --help
```

Take the screenshot when:

- The version line is visible.
- The main command list is visible.

Screenshot description:

> Sysremote command-line interface. The help screen shows the available modules:
> remote administration, backup, restore, audit, maintenance, scheduling,
> monitoring, logging, archiving, and benchmarking.

## Screenshot 4: Baseline Smoke Tests

Execute:

```bash
find bin lib modules tools tests demo-lab -type f -name '*.sh' -exec bash -n {} \;
make test
make native-check
```

Take the screenshot when:

- `smoke tests passed` is visible.
- `make native-check` finishes without errors.

Screenshot description:

> Baseline validation before the live demo. Shell syntax checks pass, the smoke
> test succeeds, and the native helper scripts are syntactically valid.

## Screenshot 5: Target Validation

Execute:

```bash
./bin/sysremote.sh -l "$LOG_DIR" -m localhost validate-hosts
```

Take the screenshot when:

- The output shows `localhost OK`.

Screenshot description:

> Target validation with sysremote. The tool accepts `localhost` as a valid
> target before running remote administration commands.

## Screenshot 6: Remote Sessions

Execute:

```bash
./bin/sysremote.sh -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -T 5 -m localhost sessions who
./bin/sysremote.sh -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -T 5 -m localhost sessions w
```

Take the screenshot when:

- The terminal shows the `==> localhost` target marker.
- Session output from `who` or `w` is visible.

Screenshot description:

> Remote session inspection through sysremote. The CLI connects to the demo
> machine over SSH and runs standard Linux session commands.

## Screenshot 7: Remote User Lifecycle

Execute:

```bash
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost create-user srtest
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost lock-user srtest
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost unlock-user srtest
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost add-user-group srtest sudo
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost remove-user-group srtest sudo
./bin/sysremote.sh -N -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost delete-user srtest
```

Take the screenshot when:

- The commands complete without SSH errors.
- Several `==> localhost` markers are visible.

Screenshot description:

> Remote user management lifecycle. Sysremote creates, locks, unlocks, modifies,
> and deletes a user account on the remote demo machine through one CLI.

## Screenshot 8: Backup Creation

Execute:

```bash
mkdir -p "$TEST_ROOT/source/config" "$TEST_ROOT/source/data"
echo "port=8080" > "$TEST_ROOT/source/config/app.conf"
echo "hello" > "$TEST_ROOT/source/data/file.txt"

./bin/sysremote.sh -l "$LOG_DIR" backup -S "$TEST_ROOT/source" -D "$TEST_ROOT/backups" --tag snap1
./bin/sysremote.sh -l "$LOG_DIR" backup -S "$TEST_ROOT/source" -D "$TEST_ROOT/backups" --tag snap2 --compress
printf 'test1234\ntest1234\n' | ./bin/sysremote.sh -l "$LOG_DIR" backup -S "$TEST_ROOT/source" -D "$TEST_ROOT/backups" --tag snap3 --compress --encrypt

find "$TEST_ROOT/backups" -maxdepth 1 -type f -o -type d
```

Take the screenshot when:

- `backup complete` is visible.
- `snap1`, `snap2.tar.gz`, and `snap3.tar.gz.enc` are visible.

Screenshot description:

> Backup module demonstration. Sysremote creates a normal snapshot, a compressed
> archive, and an encrypted archive from the same test source directory.

## Screenshot 9: Restore Verification

Execute:

```bash
./bin/sysremote.sh -N -l "$LOG_DIR" restore -A "$TEST_ROOT/backups/snap2.tar.gz" -T "$TEST_ROOT/restore"
printf 'test1234\n' | ./bin/sysremote.sh -N -l "$LOG_DIR" restore -A "$TEST_ROOT/backups/snap3.tar.gz.enc" -T "$TEST_ROOT/restore-enc"

find "$TEST_ROOT/restore" "$TEST_ROOT/restore-enc" -type f
```

Take the screenshot when:

- `restore complete` is visible.
- Restored files are listed.

Screenshot description:

> Restore module verification. The compressed and encrypted backups are
> extracted into separate restore directories, proving that saved data can be
> recovered.

## Screenshot 10: Security Audit

Execute:

```bash
./bin/sysremote.sh -l "$LOG_DIR" audit --all
```

Take the screenshot when:

- `SYSREMOTE AUDIT REPORT` is visible.
- Permission, login, or port audit output is visible.

Screenshot description:

> Security audit report. Sysremote checks sensitive file permissions, login
> information, and open ports to provide a quick security view of the system.

## Screenshot 11: Safe Maintenance and Scheduling Dry Run

Execute:

```bash
./bin/sysremote.sh -N -n -l "$LOG_DIR" maintain --update --clean
./bin/sysremote.sh -N -n -l "$LOG_DIR" schedule --add "*/5 * * * *" "./bin/sysremote.sh monitor --check"
./bin/sysremote.sh -N -n -l "$LOG_DIR" schedule --remove
```

Take the screenshot when:

- `[dry-run] maintain` is visible.
- `[dry-run] add cron` or `[dry-run] remove cron file` is visible.

Screenshot description:

> Safe execution mode for sensitive operations. Maintenance and scheduling are
> shown in dry-run mode, so the report demonstrates intent without modifying the
> host system.

## Screenshot 12: Monitoring and Reports

Execute:

```bash
./bin/sysremote.sh -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost monitor --check --alert 80 --csv --html
./bin/sysremote.sh -l "$LOG_DIR" -U demo -p "$DEMO_PORT" -m localhost metrics --check
```

Take the screenshot when:

- `status=OK` or another health status is visible.
- `csv report updated` is visible.
- `html report updated` is visible.

Screenshot description:

> Monitoring and report generation. Sysremote collects CPU, RAM, disk, uptime,
> and load metrics from the demo machine, evaluates the alert threshold, and
> writes CSV and HTML reports.

## Screenshot 13: Logs and Archive Evidence

Execute:

```bash
./bin/sysremote.sh -l "$LOG_DIR" logs -n 30
./bin/sysremote.sh -l "$LOG_DIR" archive-logs "$TEST_ROOT/archives"
tar -tzf "$TEST_ROOT"/archives/sysremote-logs-*.tar.gz
```

Take the screenshot when:

- Recent `history.log` entries are visible.
- `archive created` is visible.
- `manifest.txt` is visible in the archive listing.

Screenshot description:

> Execution evidence. Sysremote records actions in `history.log`, then archives
> the logs into a compressed file with a manifest for traceability.

## Screenshot 14: Benchmark Modes

Execute:

```bash
./bin/sysremote.sh -l "$LOG_DIR" benchmark light
./bin/sysremote.sh -l "$LOG_DIR" benchmark medium
./bin/sysremote.sh -l "$LOG_DIR" benchmark heavy
```

Take the screenshot when:

- `benchmark workload=...` is visible.
- `elapsed_ms` lines are visible for normal, fork, thread, and subshell modes.

Screenshot description:

> Execution mode benchmark. Sysremote compares normal, fork, thread, and
> subshell execution modes using light, medium, and heavy workloads.

## Screenshot 15: Native Concurrency Helpers

Execute:

```bash
make native

printf 'localhost\n' > "$TEST_ROOT/hosts-node1.txt"

tools/native_parallel.sh -q -H "$TEST_ROOT/hosts-node1.txt" -u demo -p "$DEMO_PORT" -- hostname
tools/native_parallel.sh -s -H "$TEST_ROOT/hosts-node1.txt" -u demo -p "$DEMO_PORT" -- hostname
tools/native_parallel.sh -f -H "$TEST_ROOT/hosts-node1.txt" -u demo -p "$DEMO_PORT" -- hostname
tools/native_parallel.sh -t -H "$TEST_ROOT/hosts-node1.txt" -u demo -p "$DEMO_PORT" -- hostname
```

Take the screenshot when:

- `make native` finishes successfully.
- Each native mode returns a successful result for `localhost`.

Screenshot description:

> Native concurrency helpers. The optional C fork and pthread helpers are built
> and used through `tools/native_parallel.sh` to execute a command on the demo
> machine.

## Suggested Report Order

1. Demo lab container running.
2. Direct SSH connectivity.
3. Sysremote help and version.
4. Smoke tests.
5. Target validation.
6. Remote sessions.
7. Remote user lifecycle.
8. Backup creation.
9. Restore verification.
10. Security audit.
11. Maintenance and scheduling dry-run.
12. Monitoring and reports.
13. Logs and archive evidence.
14. Benchmark modes.
15. Native concurrency helpers.
