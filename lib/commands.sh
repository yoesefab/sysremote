# Command implementations and dispatch helpers.

cmd_validate_hosts() {
  local host
  for host in "${TARGET_HOSTS[@]}"; do
    printf '%s OK\n' "$host"
  done
}

cmd_sessions() {
  if [ "$#" -gt 1 ]; then
    die "$EX_USAGE" "sessions accepts at most one argument: who or w"
  fi

  local session_command="${1:-$DEFAULT_SESSION_COMMAND}"
  case "$session_command" in
    who) run_on_targets "who" ;;
    w) run_on_targets "w" ;;
    *) die "$EX_USAGE" "sessions accepts only: who or w" ;;
  esac
}

cmd_create_user() {
  require_arg_count 1 "create-user" "$@"
  local user="$1"
  validate_account_name "$user" || die "$EX_USAGE" "invalid username: $user"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)useradd --create-home -- $(remote_quote "$user")"
}

cmd_delete_user() {
  require_arg_count 1 "delete-user" "$@"
  local user="$1"
  validate_account_name "$user" || die "$EX_USAGE" "invalid username: $user"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)userdel -r -- $(remote_quote "$user")"
}

cmd_add_user_group() {
  require_arg_count 2 "add-user-group" "$@"
  local user="$1" group="$2"
  validate_account_name "$user" || die "$EX_USAGE" "invalid username: $user"
  validate_account_name "$group" || die "$EX_USAGE" "invalid group: $group"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)usermod -a -G $(remote_quote "$group") $(remote_quote "$user")"
}

cmd_remove_user_group() {
  require_arg_count 2 "remove-user-group" "$@"
  local user="$1" group="$2"
  validate_account_name "$user" || die "$EX_USAGE" "invalid username: $user"
  validate_account_name "$group" || die "$EX_USAGE" "invalid group: $group"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)gpasswd -d $(remote_quote "$user") $(remote_quote "$group")"
}

cmd_lock_user() {
  require_arg_count 1 "lock-user" "$@"
  local user="$1"
  validate_account_name "$user" || die "$EX_USAGE" "invalid username: $user"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)passwd -l $(remote_quote "$user")"
}

cmd_unlock_user() {
  require_arg_count 1 "unlock-user" "$@"
  local user="$1"
  validate_account_name "$user" || die "$EX_USAGE" "invalid username: $user"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)passwd -u $(remote_quote "$user")"
}

cmd_archive_logs() {
  local dest="${1:-$ARCHIVE_DIR}"
  local timestamp archive staging file base

  if [ "$#" -gt 1 ]; then
    die "$EX_USAGE" "archive-logs accepts at most one destination directory"
  fi

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$dest" || die "$EX_CONFIG" "cannot create archive directory: $dest"
  staging="$(mktemp -d "${TMPDIR:-/tmp}/sysremote-archive.XXXXXX")" || die "$EX_CONFIG" "cannot create temporary archive directory"
  archive="${dest%/}/sysremote-logs-$timestamp.tar.gz"

  find "$LOG_DIR" -type f -name '*.log' -print 2>/dev/null | sort > "$staging/log-files.txt" || true
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    base="$(basename "$file")"
    cp "$file" "$staging/$base"
  done < "$staging/log-files.txt"

  {
    printf 'archive=%s\n' "$archive"
    printf 'created=%s\n' "$timestamp"
    printf 'source=%s\n' "$LOG_DIR"
    printf 'files=\n'
    sed 's/^/  /' "$staging/log-files.txt"
  } > "$staging/manifest.txt"
  rm -f "$staging/log-files.txt"

  tar -czf "$archive" -C "$staging" . || {
    rm -rf "$staging"
    die "$EX_CONFIG" "tar.gz compression failed: $archive"
  }
  rm -rf "$staging"
  printf 'archive created: %s\n' "$archive"
}

cmd_logs() {
  local lines=50
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -n) lines="${2:-}"; [ -n "$lines" ] || die "$EX_MISSING_PARAM" "logs -n requires a line count"; shift 2 ;;
      *) die "$EX_INVALID_OPTION" "unknown logs option: $1" ;;
    esac
  done
  is_positive_int "$lines" || die "$EX_INVALID_PARAM" "line count must be a positive integer"
  if [ -f "$LOG_FILE" ]; then
    tail -n "$lines" "$LOG_FILE"
  else
    printf 'no log file found: %s\n' "$LOG_FILE"
  fi
}

benchmark_task() {
  local mode="$1" task_id="$2" delay="$3"
  printf 'mode=%s task=%s pid=%s start\n' "$mode" "$task_id" "$BASHPID"
  sleep "$delay"
  printf 'mode=%s task=%s pid=%s end\n' "$mode" "$task_id" "$BASHPID"
}

run_benchmark_mode() {
  local mode="$1" tasks="$2" delay="$3"
  local start end elapsed task

  start="$(date '+%s%3N')"
  case "$mode" in
    normal)
      for ((task = 1; task <= tasks; task++)); do
        benchmark_task "$mode" "$task" "$delay"
      done
      ;;
    fork)
      for ((task = 1; task <= tasks; task++)); do
        benchmark_task "$mode" "$task" "$delay" &
      done
      wait
      ;;
    thread)
      export delay mode
      seq 1 "$tasks" | xargs -n 1 -P "$THREAD_JOBS" bash -c '
        task="$1"
        printf "mode=%s task=%s pid=%s start\n" "$mode" "$task" "$BASHPID"
        sleep "$delay"
        printf "mode=%s task=%s pid=%s end\n" "$mode" "$task" "$BASHPID"
      ' _
      ;;
    subshell)
      (
        for ((task = 1; task <= tasks; task++)); do
          benchmark_task "$mode" "$task" "$delay"
        done
      )
      ;;
    *)
      die "$EX_CONFIG" "invalid benchmark mode: $mode"
      ;;
  esac
  end="$(date '+%s%3N')"
  elapsed=$((end - start))
  printf 'benchmark mode=%s tasks=%s delay=%ss elapsed_ms=%s\n' "$mode" "$tasks" "$delay" "$elapsed"
}

cmd_benchmark() {
  local workload="${1:-light}"
  local tasks delay

  if [ "$#" -gt 1 ]; then
    die "$EX_USAGE" "benchmark accepts: light, medium or heavy"
  fi

  case "$workload" in
    light) tasks=2; delay="0.10" ;;
    medium) tasks=4; delay="0.20" ;;
    heavy) tasks=6; delay="0.30" ;;
    *) die "$EX_USAGE" "unknown workload: $workload" ;;
  esac

  printf 'benchmark workload=%s workers=%s\n' "$workload" "$THREAD_JOBS"
  run_benchmark_mode normal "$tasks" "$delay"
  run_benchmark_mode fork "$tasks" "$delay"
  run_benchmark_mode thread "$tasks" "$delay"
  run_benchmark_mode subshell "$tasks" "$delay"
}

cmd_restore_defaults() {
  [ "$EUID" -eq 0 ] || die "$EX_PRIVILEGE" "default restoration requires root"

  mkdir -p /etc/sysremote "$LOG_DIR" "$DEFAULT_BACKUP_DIR" "$ARCHIVE_DIR" "$REPORT_DIR" \
    || die "$EX_CONFIG" "cannot create default directories"
  write_default_config "/etc/sysremote/sysremote.conf"
  touch "$LOG_FILE" || die "$EX_CONFIG" "cannot create log file: $LOG_FILE"
  chmod 755 /etc/sysremote "$LOG_DIR" "$DEFAULT_BACKUP_DIR" "$ARCHIVE_DIR" "$REPORT_DIR" 2>/dev/null || true
  chmod 640 /etc/sysremote/sysremote.conf "$LOG_FILE" 2>/dev/null || true
  printf 'defaults restored: /etc/sysremote/sysremote.conf and %s\n' "$LOG_FILE"
}

dispatch() {
  case "$COMMAND" in
    validate-hosts) cmd_validate_hosts ;;
    sessions) cmd_sessions "${COMMAND_ARGS[@]}" ;;
    create-user|user-create) cmd_create_user "${COMMAND_ARGS[@]}" ;;
    delete-user|user-delete) cmd_delete_user "${COMMAND_ARGS[@]}" ;;
    add-user-group|group-add) cmd_add_user_group "${COMMAND_ARGS[@]}" ;;
    remove-user-group|group-remove) cmd_remove_user_group "${COMMAND_ARGS[@]}" ;;
    lock-user) cmd_lock_user "${COMMAND_ARGS[@]}" ;;
    unlock-user) cmd_unlock_user "${COMMAND_ARGS[@]}" ;;
    archive-logs) cmd_archive_logs "${COMMAND_ARGS[@]}" ;;
    benchmark) cmd_benchmark "${COMMAND_ARGS[@]}" ;;
    backup) cmd_backup "${COMMAND_ARGS[@]}" ;;
    restore) cmd_restore "${COMMAND_ARGS[@]}" ;;
    audit) cmd_audit "${COMMAND_ARGS[@]}" ;;
    maintain|maintenance) cmd_maintain "${COMMAND_ARGS[@]}" ;;
    schedule) cmd_schedule "${COMMAND_ARGS[@]}" ;;
    logs) cmd_logs "${COMMAND_ARGS[@]}" ;;
    monitor) cmd_monitor "${COMMAND_ARGS[@]}" ;;
    metrics) cmd_metrics "${COMMAND_ARGS[@]}" ;;
    ""|help) die "$EX_MISSING_PARAM" "missing required command" ;;
    *) die "$EX_USAGE" "unknown command: $COMMAND" ;;
  esac
}
