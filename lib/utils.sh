# Utility functions without business-specific dependencies.

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

check_dep() {
  local dep
  for dep in "$@"; do
    command -v "$dep" >/dev/null 2>&1 || die "$EX_DEPENDENCY" "missing dependency: $dep"
  done
}

timestamp_tag() {
  date '+%Y%m%d-%H%M%S'
}

safe_status_name() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9_.-]/_/g'
}

html_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  printf '%s' "$value"
}

csv_escape() {
  local value="$1"
  value="${value//\"/\"\"}"
  printf '"%s"' "$value"
}
