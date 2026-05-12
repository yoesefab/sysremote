# * Commandes utilisateur de sysremote.

cmd_validate_hosts() {
  local host

  for host in "${TARGET_HOSTS[@]}"; do
    printf '%s OK\n' "$host"
  done
}

cmd_sessions() {
  if [ "$#" -gt 1 ]; then
    die "$EX_USAGE" "sessions accepte au plus un argument: who ou w"
  fi

  local session_command="${1:-$DEFAULT_SESSION_COMMAND}"

  case "$session_command" in
    who) run_on_targets "who" ;;
    w) run_on_targets "w" ;;
    *) die "$EX_USAGE" "sessions accepte uniquement: who ou w" ;;
  esac
}

cmd_create_user() {
  require_arg_count 1 "create-user" "$@"
  local user="$1"
  validate_account_name "$user" || die "$EX_USAGE" "nom utilisateur invalide: $user"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)useradd --create-home -- $(remote_quote "$user")"
}

cmd_delete_user() {
  require_arg_count 1 "delete-user" "$@"
  local user="$1"
  validate_account_name "$user" || die "$EX_USAGE" "nom utilisateur invalide: $user"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)userdel -r -- $(remote_quote "$user")"
}

cmd_add_user_group() {
  require_arg_count 2 "add-user-group" "$@"
  local user="$1"
  local group="$2"
  validate_account_name "$user" || die "$EX_USAGE" "nom utilisateur invalide: $user"
  validate_account_name "$group" || die "$EX_USAGE" "nom groupe invalide: $group"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)usermod -a -G $(remote_quote "$group") $(remote_quote "$user")"
}

cmd_remove_user_group() {
  require_arg_count 2 "remove-user-group" "$@"
  local user="$1"
  local group="$2"
  validate_account_name "$user" || die "$EX_USAGE" "nom utilisateur invalide: $user"
  validate_account_name "$group" || die "$EX_USAGE" "nom groupe invalide: $group"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)gpasswd -d $(remote_quote "$user") $(remote_quote "$group")"
}

cmd_lock_user() {
  require_arg_count 1 "lock-user" "$@"
  local user="$1"
  validate_account_name "$user" || die "$EX_USAGE" "nom utilisateur invalide: $user"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)passwd -l $(remote_quote "$user")"
}

cmd_unlock_user() {
  require_arg_count 1 "unlock-user" "$@"
  local user="$1"
  validate_account_name "$user" || die "$EX_USAGE" "nom utilisateur invalide: $user"
  require_root_for_sensitive_action
  run_on_targets "$(sudo_prefix)passwd -u $(remote_quote "$user")"
}

cmd_archive_logs() {
  local dest="${1:-./archives}"
  local timestamp archive staging file base

  if [ "$#" -gt 1 ]; then
    die "$EX_USAGE" "archive-logs accepte au plus un dossier de destination"
  fi

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$dest" || die "$EX_CONFIG" "creation dossier archive impossible: $dest"
  staging="$(mktemp -d "${TMPDIR:-/tmp}/sysremote-archive.XXXXXX")" || die "$EX_CONFIG" "creation repertoire temporaire impossible"
  archive="$dest/sysremote-logs-$timestamp.tar.gz"

  touch "$staging/manifest.tmp" "$staging/log-files.txt"
  find "$LOG_DIR" -type f -name '*.log' -print 2>/dev/null \
    | grep -E '/[^/]+[.]log$' \
    | sed 's#//*#/#g' \
    | sort \
    | uniq > "$staging/log-files.txt" || true

  while IFS= read -r file; do
    [ -f "$file" ] || continue
    base="$(basename "$file")"
    cp "$file" "$staging/$base"
  done < "$staging/log-files.txt"

  awk -F/ '{print $NF}' "$staging/log-files.txt" \
    | cut -d. -f1 \
    | sort \
    | uniq > "$staging/manifest.tmp"
  printf 'archive=%s\ncreated=%s\nsource=%s\n' "$archive" "$timestamp" "$LOG_DIR" >> "$staging/manifest.tmp"
  mv "$staging/manifest.tmp" "$staging/manifest.txt"
  rm -f "$staging/log-files.txt"

  tar -czf "$archive" -C "$staging" . || {
    rm -rf "$staging"
    die "$EX_CONFIG" "compression tar.gz impossible: $archive"
  }
  rm -rf "$staging"
  printf 'archive creee: %s\n' "$archive"
}

benchmark_task() {
  local mode="$1"
  local task_id="$2"
  local delay="$3"

  printf 'mode=%s task=%s pid=%s start\n' "$mode" "$task_id" "$BASHPID"
  sleep "$delay"
  printf 'mode=%s task=%s pid=%s end\n' "$mode" "$task_id" "$BASHPID"
}

run_benchmark_mode() {
  local mode="$1"
  local tasks="$2"
  local delay="$3"
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
      die "$EX_CONFIG" "mode benchmark invalide: $mode"
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
    die "$EX_USAGE" "benchmark accepte: light, medium ou heavy"
  fi

  case "$workload" in
    light)
      tasks=2
      delay="0.10"
      ;;
    medium)
      tasks=4
      delay="0.20"
      ;;
    heavy)
      tasks=6
      delay="0.30"
      ;;
    *)
      die "$EX_USAGE" "charge inconnue: $workload"
      ;;
  esac

  printf 'benchmark workload=%s workers=%s\n' "$workload" "$THREAD_JOBS"
  run_benchmark_mode normal "$tasks" "$delay"
  run_benchmark_mode fork "$tasks" "$delay"
  run_benchmark_mode thread "$tasks" "$delay"
  run_benchmark_mode subshell "$tasks" "$delay"
}

cmd_restore_defaults() {
  if [ "$EUID" -ne 0 ]; then
    die "$EX_PRIVILEGE" "restauration reservee aux administrateurs; utiliser sudo"
  fi

  mkdir -p /etc/sysremote "$LOG_DIR" || die "$EX_CONFIG" "creation dossiers par defaut impossible"
  if [ -f "./sysremote.conf.example" ]; then
    cp "./sysremote.conf.example" "/etc/sysremote/sysremote.conf"
  fi
  touch "$LOG_FILE"
  chmod 755 /etc/sysremote "$LOG_DIR" 2>/dev/null || true
  chmod 640 /etc/sysremote/sysremote.conf "$LOG_FILE" 2>/dev/null || true
  printf 'reglages par defaut restaures: /etc/sysremote/sysremote.conf et %s\n' "$LOG_FILE"
}
