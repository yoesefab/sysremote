# * Chargement et validation de la configuration.

resolve_default_config() {
  if [ -n "$CLI_CONFIG_FILE" ]; then
    CONFIG_FILE="$CLI_CONFIG_FILE"
    return
  fi

  if [ -f "./sysremote.conf" ]; then
    CONFIG_FILE="./sysremote.conf"
  elif [ -f "/etc/sysremote/sysremote.conf" ]; then
    CONFIG_FILE="/etc/sysremote/sysremote.conf"
  else
    CONFIG_FILE=""
  fi
}

load_config() {
  local file="$1"
  local explicit="$2"
  local line key value bool_value

  if [ -z "$file" ]; then
    return
  fi

  if [ ! -f "$file" ]; then
    if [ "$explicit" = "true" ]; then
      die "$EX_CONFIG" "configuration introuvable: $file"
    fi
    return
  fi

  if [ ! -r "$file" ]; then
    die "$EX_CONFIG" "configuration illisible: $file"
  fi

  log_info "chargement configuration: $file"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(trim "$line")"
    [ -z "$line" ] && continue

    if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      die "$EX_CONFIG" "ligne de configuration invalide: $line"
    fi

    key="${line%%=*}"
    value="${line#*=}"
    value="$(trim "$value")"
    value="$(strip_quotes "$value")"

    case "$key" in
      SSH_USER) SSH_USER="$value" ;;
      SSH_PORT) SSH_PORT="$value" ;;
      SSH_TIMEOUT) SSH_TIMEOUT="$value" ;;
      INVENTORY_FILE) INVENTORY_FILE="$value" ;;
      REQUIRE_ROOT)
        bool_value="$(normalize_bool "$value")" || die "$EX_CONFIG" "REQUIRE_ROOT doit etre booleen"
        REQUIRE_ROOT="$bool_value"
        ;;
      REMOTE_SUDO) REMOTE_SUDO="$value" ;;
      DEFAULT_SESSION_COMMAND) DEFAULT_SESSION_COMMAND="$value" ;;
      *)
        die "$EX_CONFIG" "cle de configuration inconnue: $key"
        ;;
    esac
  done < "$file"
}

apply_cli_overrides() {
  [ -n "$CLI_INVENTORY_FILE" ] && INVENTORY_FILE="$CLI_INVENTORY_FILE"
  [ -n "$CLI_SSH_USER" ] && SSH_USER="$CLI_SSH_USER"
  [ -n "$CLI_SSH_PORT" ] && SSH_PORT="$CLI_SSH_PORT"
  [ -n "$CLI_SSH_TIMEOUT" ] && SSH_TIMEOUT="$CLI_SSH_TIMEOUT"
  [ -n "$CLI_LOG_DIR" ] && LOG_DIR="$CLI_LOG_DIR"
  [ "$CLI_NO_ROOT_CHECK" = "true" ] && REQUIRE_ROOT="false"
}

validate_ssh_user() {
  local user="$1"
  [[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ "$user" != -* ]] || return 1
}

validate_runtime_config() {
  validate_ssh_user "$SSH_USER" || die "$EX_CONFIG" "SSH_USER invalide: $SSH_USER"
  is_positive_int "$SSH_PORT" || die "$EX_CONFIG" "SSH_PORT doit etre un entier positif"
  [ "$SSH_PORT" -le 65535 ] || die "$EX_CONFIG" "SSH_PORT doit etre inferieur ou egal a 65535"
  is_positive_int "$SSH_TIMEOUT" || die "$EX_CONFIG" "SSH_TIMEOUT doit etre un entier positif"
  is_positive_int "$THREAD_JOBS" || die "$EX_CONFIG" "THREAD_JOBS doit etre un entier positif"
  case "$REMOTE_SUDO" in
    ""|"sudo"|"sudo -n"|"doas"|"doas -n") ;;
    *) die "$EX_CONFIG" "REMOTE_SUDO accepte: vide, sudo, sudo -n, doas, doas -n" ;;
  esac
  case "$DEFAULT_SESSION_COMMAND" in
    who|w) ;;
    *) die "$EX_CONFIG" "DEFAULT_SESSION_COMMAND accepte: who ou w" ;;
  esac
}
