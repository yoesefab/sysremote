# * Validation des noms, arguments et droits.

validate_ipv4() {
  local host="$1"
  local IFS='.'
  local -a parts
  local part

  [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  read -r -a parts <<< "$host"
  [ "${#parts[@]}" -eq 4 ] || return 1

  for part in "${parts[@]}"; do
    [[ "$part" =~ ^[0-9]+$ ]] || return 1
    [ "$part" -le 255 ] || return 1
  done
}

validate_hostname() {
  local host="$1"
  local IFS='.'
  local -a labels
  local label

  [ "${#host}" -le 253 ] || return 1
  [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  [[ "$host" != .* && "$host" != *. ]] || return 1

  read -r -a labels <<< "$host"
  for label in "${labels[@]}"; do
    [ -n "$label" ] || return 1
    [ "${#label}" -le 63 ] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

validate_host() {
  local host="$1"

  [ -n "$host" ] || return 1
  [[ "$host" != -* ]] || return 1
  [[ "$host" != *[[:space:]]* ]] || return 1
  [[ "$host" != *@* ]] || return 1
  [[ "$host" != *:* ]] || return 1

  if [[ "$host" =~ ^[0-9.]+$ ]]; then
    validate_ipv4 "$host"
    return
  fi

  validate_ipv4 "$host" || validate_hostname "$host"
}

validate_account_name() {
  local name="$1"
  [ "${#name}" -le 32 ] || return 1
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_.-]*[$]?$ ]] || return 1
  [[ "$name" != -* ]] || return 1
}

validate_command_name() {
  if [ "$RESTORE_DEFAULTS" = "true" ]; then
    return 0
  fi

  case "$COMMAND" in
    validate-hosts|sessions|create-user|user-create|delete-user|user-delete|add-user-group|group-add|remove-user-group|group-remove|lock-user|unlock-user|archive-logs|benchmark)
      return 0
      ;;
    ""|help)
      die "$EX_MISSING_PARAM" "commande obligatoire manquante"
      ;;
    *)
      die "$EX_USAGE" "commande inconnue: $COMMAND"
      ;;
  esac
}

require_arg_count() {
  local expected="$1"
  local command_name="$2"
  shift 2

  if [ "$#" -ne "$expected" ]; then
    die "$EX_MISSING_PARAM" "$command_name requiert $expected argument(s)"
  fi
}

require_root_for_sensitive_action() {
  if [ "$REQUIRE_ROOT" = "true" ] && [ "$EUID" -ne 0 ]; then
    die "$EX_PRIVILEGE" "privileges root locaux requis pour cette action; utiliser sudo ou -N si delegation distante controlee"
  fi
}

is_sensitive_command() {
  case "$1" in
    create-user|user-create|delete-user|user-delete|add-user-group|group-add|remove-user-group|group-remove|lock-user|unlock-user)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

command_requires_targets() {
  case "$1" in
    validate-hosts|sessions|create-user|user-create|delete-user|user-delete|add-user-group|group-add|remove-user-group|group-remove|lock-user|unlock-user)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
