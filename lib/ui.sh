# Help, stdout/stderr logging, and shared error handling.

usage() {
  cat <<'USAGE'
sysremote - unified Linux/Bash remote administration toolkit

Synopsis:
  sysremote [global options] command [arguments]

Global options:
  -h, --help              Show this help.
  --version               Show version.
  -c, --config FILE       Load a config file.
  -i, --inventory FILE    Load target inventory, one host per line.
  -m, --hosts HOSTS       Comma-separated targets.
  -l, --log-dir DIR       Log directory. history.log is created inside it.
  -U, --user LOGIN        SSH login.
  -p, --port PORT         SSH port.
  -T, --timeout SECONDS   SSH connection timeout.
  -f, --fork              Fork mode for multi-target execution.
  -t, --thread            Thread-pool mode via xargs -P.
  -s, --subshell          Subshell mode.
  -j, --jobs N            Worker count for thread mode.
  -r, --restore-defaults  Install default config/log paths (root only).
  -N, --no-root-check     Skip local EUID check for sensitive remote actions.
  -n, --dry-run           Print intended actions without remote changes.
  -v, --verbose           Print extra diagnostic messages.

Remote administration:
  validate-hosts
  sessions [who|w]
  create-user USER
  delete-user USER
  add-user-group USER GROUP
  remove-user-group USER GROUP
  lock-user USER
  unlock-user USER

Backup, restore, audit, maintenance:
  backup -S DIR [-D DIR] [--compress] [--encrypt] [--remote TARGET] [--tag NAME]
  restore -A ARCHIVE [-T DIR]
  audit [--perms] [--logins] [--ports] [--all]
  maintain [--update] [--clean]
  schedule --add "M H DOM MON DOW" "COMMAND"
  schedule --list
  schedule --remove
  logs [-n LINES]

Monitoring and reports:
  monitor [--check] [--alert N] [--csv] [--html] [--notify] [--interactive]
  metrics

Other:
  archive-logs [DIR]
  benchmark [light|medium|heavy]

Exit codes:
  0 success; 2 usage; 3 config; 4 host validation; 10 privileges;
  20 SSH; 21 remote command; 30 no targets; 100 invalid option;
  101 missing parameter; 109 dependency; 110 invalid parameter; 111 cron.
USAGE
}

log_info() {
  if [ "$VERBOSE" = "true" ]; then
    printf 'sysremote: %s\n' "$*" >&2
  fi
}

log_warn() {
  printf 'sysremote: warning: %s\n' "$*" >&2
}

log_error() {
  printf 'sysremote: %s\n' "$*" >&2
}

log_line_direct() {
  local level="$1"
  local message="$2"

  [ "$LOGGING_READY" = "true" ] || return 0
  printf '%s : %s : %s : %s\n' "$(date '+%Y-%m-%d-%H-%M-%S')" "${USER:-unknown}" "$level" "$message" >> "$LOG_FILE"
}

emit_help() {
  usage
  if [ "$LOGGING_READY" = "true" ]; then
    while IFS= read -r line; do
      log_line_direct "INFOS" "$line"
    done <<< "$(usage)"
  fi
}

die() {
  local code="$1"
  local message
  shift
  message="$*"

  printf 'sysremote: %s\n\n' "$message" >&2
  log_line_direct "ERROR" "sysremote: $message"
  usage >&2
  if [ "$LOGGING_READY" = "true" ]; then
    while IFS= read -r line; do
      log_line_direct "ERROR" "$line"
    done <<< "$(usage)"
  fi
  exit "$code"
}

preparse_log_dir() {
  local arg next

  while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
      -l|--log-dir)
        next="${2:-}"
        if [ -n "$next" ]; then
          CLI_LOG_DIR="$next"
          LOG_DIR="$next"
          shift 2
        else
          shift
        fi
        ;;
      --log-dir=*)
        CLI_LOG_DIR="${arg#--log-dir=}"
        LOG_DIR="$CLI_LOG_DIR"
        shift
        ;;
      --)
        break
        ;;
      *)
        shift
        ;;
    esac
  done
}

finish_logging() {
  if [ "$LOGGING_READY" = "true" ]; then
    sleep 0.05
    exec 1>&3 2>&4
    exec 3>&- 4>&-
  fi
}

setup_logging() {
  local attempt=1

  LOG_FILE="${LOG_DIR%/}/history.log"
  until mkdir -p "$LOG_DIR" 2>/dev/null; do
    if [ "$attempt" -ge 3 ]; then
      printf 'sysremote: cannot create log directory: %s\n' "$LOG_DIR" >&2
      LOGGING_READY="false"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  if ! touch "$LOG_FILE" 2>/dev/null; then
    printf 'sysremote: cannot write log file: %s\n' "$LOG_FILE" >&2
    LOGGING_READY="false"
    return 0
  fi

  chmod 640 "$LOG_FILE" 2>/dev/null || true
  LOGGING_READY="true"

  exec 3>&1
  exec 4>&2
  exec > >(while IFS= read -r line; do
    printf '%s\n' "$line" >&3
    printf '%s : %s : INFOS : %s\n' "$(date '+%Y-%m-%d-%H-%M-%S')" "${USER:-unknown}" "$line" >> "$LOG_FILE"
  done)
  exec 2> >(while IFS= read -r line; do
    printf '%s\n' "$line" >&4
    printf '%s : %s : ERROR : %s\n' "$(date '+%Y-%m-%d-%H-%M-%S')" "${USER:-unknown}" "$line" >> "$LOG_FILE"
  done)
  trap finish_logging EXIT
}
