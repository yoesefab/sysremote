# Central configuration loading and validation.

resolve_default_config() {
  if [ -n "$CLI_CONFIG_FILE" ]; then
    CONFIG_FILE="$CLI_CONFIG_FILE"
    return
  fi

  if [ -f "$SYSREMOTE_ROOT_DIR/sysremote.conf" ]; then
    CONFIG_FILE="$SYSREMOTE_ROOT_DIR/sysremote.conf"
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

  [ -n "$file" ] || return 0

  if [ ! -f "$file" ]; then
    [ "$explicit" = "true" ] && die "$EX_FILE_NOT_FOUND" "configuration not found: $file"
    return 0
  fi

  [ -r "$file" ] || die "$EX_PRIVILEGE" "configuration is not readable: $file"

  log_info "loading configuration: $file"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(trim "$line")"
    [ -z "$line" ] && continue

    if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      die "$EX_CONFIG" "invalid configuration line: $line"
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
        bool_value="$(normalize_bool "$value")" || die "$EX_CONFIG" "REQUIRE_ROOT must be boolean"
        REQUIRE_ROOT="$bool_value"
        ;;
      REMOTE_SUDO) REMOTE_SUDO="$value" ;;
      DEFAULT_SESSION_COMMAND) DEFAULT_SESSION_COMMAND="$value" ;;
      THREAD_JOBS) THREAD_JOBS="$value" ;;
      LOG_DIR) LOG_DIR="$value" ;;
      DEFAULT_BACKUP_DIR) DEFAULT_BACKUP_DIR="$value" ;;
      DEFAULT_RESTORE_DIR) DEFAULT_RESTORE_DIR="$value" ;;
      ARCHIVE_DIR) ARCHIVE_DIR="$value" ;;
      REPORT_DIR|RAPPORT_DIR) REPORT_DIR="$value" ;;
      SEUIL_ALERTE) SEUIL_ALERTE="$value" ;;
      GENERER_HTML|GENERATE_HTML)
        bool_value="$(normalize_bool "$value")" || die "$EX_CONFIG" "$key must be boolean"
        GENERER_HTML="$bool_value"
        ;;
      NOTIF_DISCORD)
        bool_value="$(normalize_bool "$value")" || die "$EX_CONFIG" "NOTIF_DISCORD must be boolean"
        NOTIF_DISCORD="$bool_value"
        ;;
      DISCORD_WEBHOOK) DISCORD_WEBHOOK="$value" ;;
      NOTIF_EMAIL)
        bool_value="$(normalize_bool "$value")" || die "$EX_CONFIG" "NOTIF_EMAIL must be boolean"
        NOTIF_EMAIL="$bool_value"
        ;;
      EMAIL_DESTINATAIRE) EMAIL_DESTINATAIRE="$value" ;;
      *)
        die "$EX_CONFIG" "unknown configuration key: $key"
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
  LOG_FILE="${LOG_DIR%/}/history.log"
}

validate_ssh_user() {
  local user="$1"
  [[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ "$user" != -* ]] || return 1
}

validate_runtime_config() {
  validate_ssh_user "$SSH_USER" || die "$EX_CONFIG" "invalid SSH_USER: $SSH_USER"
  is_positive_int "$SSH_PORT" || die "$EX_CONFIG" "SSH_PORT must be a positive integer"
  [ "$SSH_PORT" -le 65535 ] || die "$EX_CONFIG" "SSH_PORT must be <= 65535"
  is_positive_int "$SSH_TIMEOUT" || die "$EX_CONFIG" "SSH_TIMEOUT must be a positive integer"
  is_positive_int "$THREAD_JOBS" || die "$EX_CONFIG" "THREAD_JOBS must be a positive integer"
  is_positive_int "$SEUIL_ALERTE" || die "$EX_CONFIG" "SEUIL_ALERTE must be a positive integer"
  [ "$SEUIL_ALERTE" -le 100 ] || die "$EX_CONFIG" "SEUIL_ALERTE must be <= 100"
  case "$REMOTE_SUDO" in
    ""|"sudo"|"sudo -n"|"doas"|"doas -n") ;;
    *) die "$EX_CONFIG" "REMOTE_SUDO accepts: empty, sudo, sudo -n, doas, doas -n" ;;
  esac
  case "$DEFAULT_SESSION_COMMAND" in
    who|w) ;;
    *) die "$EX_CONFIG" "DEFAULT_SESSION_COMMAND accepts: who or w" ;;
  esac
}

write_default_config() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")" || die "$EX_CONFIG" "cannot create config directory: $(dirname "$dest")"
  cat > "$dest" <<EOF
SSH_USER="${USER:-root}"
SSH_PORT="22"
SSH_TIMEOUT="5"
INVENTORY_FILE=""
REQUIRE_ROOT="true"
REMOTE_SUDO="sudo -n"
DEFAULT_SESSION_COMMAND="who"
THREAD_JOBS="4"
LOG_DIR="${LOG_DIR}"
DEFAULT_BACKUP_DIR="${DEFAULT_BACKUP_DIR}"
DEFAULT_RESTORE_DIR="${DEFAULT_RESTORE_DIR}"
ARCHIVE_DIR="${ARCHIVE_DIR}"
REPORT_DIR="${REPORT_DIR}"
SEUIL_ALERTE="80"
GENERER_HTML="true"
NOTIF_DISCORD="false"
DISCORD_WEBHOOK=""
NOTIF_EMAIL="false"
EMAIL_DESTINATAIRE=""
EOF
}
