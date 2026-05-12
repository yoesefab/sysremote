# * Parsing CLI, dispatch et cycle principal.

parse_cli() {
  local opt

  OPTIND=1
  while getopts ":hc:i:m:l:U:p:T:ftsj:rNnv" opt; do
    case "$opt" in
      h)
        emit_help
        exit "$EX_OK"
        ;;
      c)
        CLI_CONFIG_FILE="$OPTARG"
        CLI_CONFIG_EXPLICIT="true"
        ;;
      i) CLI_INVENTORY_FILE="$OPTARG" ;;
      m) CLI_MULTI_HOSTS="$OPTARG" ;;
      l)
        CLI_LOG_DIR="$OPTARG"
        LOG_DIR="$OPTARG"
        ;;
      U) CLI_SSH_USER="$OPTARG" ;;
      p) CLI_SSH_PORT="$OPTARG" ;;
      T) CLI_SSH_TIMEOUT="$OPTARG" ;;
      f) EXEC_MODE="fork" ;;
      t) EXEC_MODE="thread" ;;
      s) EXEC_MODE="subshell" ;;
      j) THREAD_JOBS="$OPTARG" ;;
      r) RESTORE_DEFAULTS="true" ;;
      N) CLI_NO_ROOT_CHECK="true" ;;
      n) DRY_RUN="true" ;;
      v) VERBOSE="true" ;;
      :)
        die "$EX_MISSING_PARAM" "option -$OPTARG requiert une valeur"
        ;;
      \?)
        die "$EX_INVALID_OPTION" "option invalide: -$OPTARG"
        ;;
    esac
  done

  shift $((OPTIND - 1))
  COMMAND="${1:-}"
  if [ -n "$COMMAND" ]; then
    shift
    COMMAND_ARGS=("$@")
  else
    COMMAND_ARGS=()
  fi
}

dispatch() {
  case "$COMMAND" in
    validate-hosts)
      cmd_validate_hosts
      ;;
    sessions)
      cmd_sessions "${COMMAND_ARGS[@]}"
      ;;
    create-user|user-create)
      cmd_create_user "${COMMAND_ARGS[@]}"
      ;;
    delete-user|user-delete)
      cmd_delete_user "${COMMAND_ARGS[@]}"
      ;;
    add-user-group|group-add)
      cmd_add_user_group "${COMMAND_ARGS[@]}"
      ;;
    remove-user-group|group-remove)
      cmd_remove_user_group "${COMMAND_ARGS[@]}"
      ;;
    lock-user)
      cmd_lock_user "${COMMAND_ARGS[@]}"
      ;;
    unlock-user)
      cmd_unlock_user "${COMMAND_ARGS[@]}"
      ;;
    archive-logs)
      cmd_archive_logs "${COMMAND_ARGS[@]}"
      ;;
    benchmark)
      cmd_benchmark "${COMMAND_ARGS[@]}"
      ;;
    ""|help)
      die "$EX_MISSING_PARAM" "commande obligatoire manquante"
      ;;
    *)
      die "$EX_USAGE" "commande inconnue: $COMMAND"
      ;;
  esac
}

main() {
  local status

  preparse_log_dir "$@"
  setup_logging
  parse_cli "$@"
  resolve_default_config
  load_config "$CONFIG_FILE" "$CLI_CONFIG_EXPLICIT"
  apply_cli_overrides
  validate_runtime_config
  validate_command_name
  status=$?
  [ "$status" -ne 0 ] && return "$status"

  if [ "$RESTORE_DEFAULTS" = "true" ]; then
    cmd_restore_defaults
    return
  fi

  if command_requires_targets "$COMMAND"; then
    load_targets
  fi

  dispatch
}
