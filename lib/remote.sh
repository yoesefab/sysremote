# Remote command execution and concurrency strategies.

remote_quote() {
  printf '%q' "$1"
}

sudo_prefix() {
  if [ -n "$REMOTE_SUDO" ]; then
    printf '%s ' "$REMOTE_SUDO"
  fi
}

ssh_exec() {
  local host="$1"
  local remote_command="$2"
  local target="${SSH_USER}@${host}"
  local -a ssh_args=(
    -o BatchMode=yes
    -o "ConnectTimeout=${SSH_TIMEOUT}"
    -o ConnectionAttempts=1
    -p "$SSH_PORT"
  )
  local status

  if [ "$DRY_RUN" = "true" ]; then
    printf '[dry-run] ssh %s@%s:%s %s\n' "$SSH_USER" "$host" "$SSH_PORT" "$remote_command"
    return "$EX_OK"
  fi

  printf '==> %s\n' "$host"
  ssh "${ssh_args[@]}" -- "$target" "$remote_command"
  status=$?

  if [ "$status" -eq 255 ]; then
    log_error "SSH error to $host"
    return "$EX_SSH"
  fi

  if [ "$status" -ne 0 ]; then
    log_error "remote command failed on $host (code $status)"
    return "$EX_REMOTE"
  fi

  return "$EX_OK"
}

collect_statuses() {
  local status_dir="$1"
  local host status_file status result
  result="$EX_OK"

  for host in "${TARGET_HOSTS[@]}"; do
    status_file="$status_dir/$(safe_status_name "$host").status"
    if [ ! -f "$status_file" ]; then
      result="$EX_REMOTE"
      continue
    fi
    IFS= read -r status < "$status_file"
    if [ "$status" -ne 0 ] && [ "$result" -eq "$EX_OK" ]; then
      result="$status"
    fi
  done

  return "$result"
}

run_on_targets_normal() {
  local remote_command="$1"
  local host status result
  result="$EX_OK"

  for host in "${TARGET_HOSTS[@]}"; do
    ssh_exec "$host" "$remote_command"
    status=$?
    if [ "$status" -ne 0 ] && [ "$result" -eq "$EX_OK" ]; then
      result="$status"
    fi
  done

  return "$result"
}

run_on_targets_fork() {
  local remote_command="$1"
  local host status_dir result
  status_dir="$(mktemp -d "${TMPDIR:-/tmp}/sysremote-fork.XXXXXX")" || die "$EX_CONFIG" "cannot create temporary directory"

  for host in "${TARGET_HOSTS[@]}"; do
    (
      ssh_exec "$host" "$remote_command"
      printf '%s\n' "$?" > "$status_dir/$(safe_status_name "$host").status"
    ) &
  done

  wait
  collect_statuses "$status_dir"
  result=$?
  rm -rf "$status_dir"
  return "$result"
}

run_on_targets_thread() {
  local remote_command="$1"
  local status_dir result
  status_dir="$(mktemp -d "${TMPDIR:-/tmp}/sysremote-thread.XXXXXX")" || die "$EX_CONFIG" "cannot create temporary directory"

  export SSH_USER SSH_PORT SSH_TIMEOUT DRY_RUN EX_OK EX_SSH EX_REMOTE STATUS_DIR="$status_dir" REMOTE_COMMAND="$remote_command"
  export -f log_error ssh_exec safe_status_name

  printf '%s\0' "${TARGET_HOSTS[@]}" | xargs -0 -n 1 -P "$THREAD_JOBS" bash -c '
    host="$1"
    ssh_exec "$host" "$REMOTE_COMMAND"
    status=$?
    printf "%s\n" "$status" > "$STATUS_DIR/$(safe_status_name "$host").status"
    exit "$status"
  ' _ || true

  collect_statuses "$status_dir"
  result=$?
  rm -rf "$status_dir"
  return "$result"
}

run_on_targets() {
  local remote_command="$1"

  case "$EXEC_MODE" in
    normal) run_on_targets_normal "$remote_command" ;;
    fork) run_on_targets_fork "$remote_command" ;;
    thread) run_on_targets_thread "$remote_command" ;;
    subshell) ( EXEC_MODE="normal"; run_on_targets "$remote_command" ) ;;
    *) die "$EX_CONFIG" "invalid execution mode: $EXEC_MODE" ;;
  esac
}
