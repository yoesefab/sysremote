# CLI parsing and application lifecycle.

parse_cli() {
  COMMAND=""
  COMMAND_ARGS=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        emit_help
        exit "$EX_OK"
        ;;
      --version)
        printf 'sysremote v%s\n' "$SYSREMOTE_VERSION"
        exit "$EX_OK"
        ;;
      -c|--config)
        CLI_CONFIG_FILE="${2:-}"
        [ -n "$CLI_CONFIG_FILE" ] || die "$EX_MISSING_PARAM" "$1 requires a value"
        CLI_CONFIG_EXPLICIT="true"
        shift 2
        ;;
      --config=*)
        CLI_CONFIG_FILE="${1#--config=}"
        CLI_CONFIG_EXPLICIT="true"
        shift
        ;;
      -i|--inventory)
        CLI_INVENTORY_FILE="${2:-}"
        [ -n "$CLI_INVENTORY_FILE" ] || die "$EX_MISSING_PARAM" "$1 requires a value"
        shift 2
        ;;
      --inventory=*)
        CLI_INVENTORY_FILE="${1#--inventory=}"
        shift
        ;;
      -m|--hosts)
        CLI_MULTI_HOSTS="${2:-}"
        [ -n "$CLI_MULTI_HOSTS" ] || die "$EX_MISSING_PARAM" "$1 requires a value"
        shift 2
        ;;
      --hosts=*)
        CLI_MULTI_HOSTS="${1#--hosts=}"
        shift
        ;;
      -l|--log-dir)
        CLI_LOG_DIR="${2:-}"
        [ -n "$CLI_LOG_DIR" ] || die "$EX_MISSING_PARAM" "$1 requires a value"
        LOG_DIR="$CLI_LOG_DIR"
        shift 2
        ;;
      --log-dir=*)
        CLI_LOG_DIR="${1#--log-dir=}"
        LOG_DIR="$CLI_LOG_DIR"
        shift
        ;;
      -U|--user)
        CLI_SSH_USER="${2:-}"
        [ -n "$CLI_SSH_USER" ] || die "$EX_MISSING_PARAM" "$1 requires a value"
        shift 2
        ;;
      --user=*)
        CLI_SSH_USER="${1#--user=}"
        shift
        ;;
      -p|--port)
        CLI_SSH_PORT="${2:-}"
        [ -n "$CLI_SSH_PORT" ] || die "$EX_MISSING_PARAM" "$1 requires a value"
        shift 2
        ;;
      --port=*)
        CLI_SSH_PORT="${1#--port=}"
        shift
        ;;
      -T|--timeout)
        CLI_SSH_TIMEOUT="${2:-}"
        [ -n "$CLI_SSH_TIMEOUT" ] || die "$EX_MISSING_PARAM" "$1 requires a value"
        shift 2
        ;;
      --timeout=*)
        CLI_SSH_TIMEOUT="${1#--timeout=}"
        shift
        ;;
      -f|--fork) EXEC_MODE="fork"; shift ;;
      -t|--thread) EXEC_MODE="thread"; shift ;;
      -s|--subshell) EXEC_MODE="subshell"; shift ;;
      -j|--jobs)
        THREAD_JOBS="${2:-}"
        [ -n "$THREAD_JOBS" ] || die "$EX_MISSING_PARAM" "$1 requires a value"
        shift 2
        ;;
      --jobs=*)
        THREAD_JOBS="${1#--jobs=}"
        shift
        ;;
      -r|--restore-defaults) RESTORE_DEFAULTS="true"; shift ;;
      -N|--no-root-check) CLI_NO_ROOT_CHECK="true"; shift ;;
      -n|--dry-run) DRY_RUN="true"; shift ;;
      -v|--verbose) VERBOSE="true"; shift ;;
      --)
        shift
        break
        ;;
      -*)
        die "$EX_INVALID_OPTION" "invalid global option: $1"
        ;;
      *)
        COMMAND="$1"
        shift
        COMMAND_ARGS=("$@")
        return 0
        ;;
    esac
  done

  if [ -z "$COMMAND" ] && [ "$#" -gt 0 ]; then
    COMMAND="$1"
    shift
    COMMAND_ARGS=("$@")
  fi
}

main() {
  local status

  parse_cli "$@"
  resolve_default_config
  load_config "$CONFIG_FILE" "$CLI_CONFIG_EXPLICIT"
  apply_cli_overrides
  setup_logging
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
