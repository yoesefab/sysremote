#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSREMOTE="$ROOT_DIR/bin/sysremote.sh"
LOG_DIR="$ROOT_DIR/logs/test"
TMP_DIR="${TMPDIR:-/tmp}/sysremote-smoke.$$"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  rm -rf "$TMP_DIR"
  exit 1
}

mkdir -p "$TMP_DIR/source" "$LOG_DIR"
printf 'hello\n' > "$TMP_DIR/source/file.txt"

bash -n "$SYSREMOTE" || fail "entry point syntax"
"$SYSREMOTE" -l "$LOG_DIR" --help >/dev/null || fail "help"
"$SYSREMOTE" -l "$LOG_DIR" -m localhost validate-hosts >/dev/null || fail "validate-hosts"
"$SYSREMOTE" -l "$LOG_DIR" benchmark light >/dev/null || fail "benchmark"
"$SYSREMOTE" -l "$LOG_DIR" archive-logs "$TMP_DIR/archives" >/dev/null || fail "archive-logs"
"$SYSREMOTE" -l "$LOG_DIR" -n backup -S "$TMP_DIR/source" -D "$TMP_DIR/backups" --compress >/dev/null || fail "backup dry-run"
"$SYSREMOTE" -l "$LOG_DIR" -n -m localhost monitor --check --csv --no-html >/dev/null || fail "monitor dry-run"
test -f "$LOG_DIR/history.log" || fail "history.log missing"

rm -rf "$TMP_DIR"
printf 'smoke tests passed\n'
