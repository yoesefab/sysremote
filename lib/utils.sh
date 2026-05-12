# * Fonctions utilitaires sans dependance metier.

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_quotes() {
  local value="$1"
  if [[ "$value" == \"*\" && "$value" == *\" ]] && [ "${#value}" -ge 2 ]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]] && [ "${#value}" -ge 2 ]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

normalize_bool() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    true|yes|1|on) printf 'true' ;;
    false|no|0|off) printf 'false' ;;
    *) return 1 ;;
  esac
}

is_positive_int() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}
