# * Lecture et preparation des cibles.

add_target_host() {
  local host
  host="$(trim "$1")"

  [ -z "$host" ] && return
  if ! validate_host "$host"; then
    die "$EX_HOST_VALIDATION" "cible refusee par validation: $host"
  fi

  TARGET_HOSTS+=("$host")
}

read_inventory() {
  local file="$1"
  local line

  [ -z "$file" ] && return
  [ -f "$file" ] || die "$EX_CONFIG" "inventaire introuvable: $file"
  [ -r "$file" ] || die "$EX_CONFIG" "inventaire illisible: $file"

  log_info "lecture inventaire: $file"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(trim "$line")"
    [ -z "$line" ] && continue
    add_target_host "$line"
  done < "$file"
}

read_inline_hosts() {
  local hosts="$1"
  local IFS=','
  local -a items
  local item

  [ -z "$hosts" ] && return
  read -r -a items <<< "$hosts"
  for item in "${items[@]}"; do
    add_target_host "$item"
  done
}

dedupe_targets() {
  local -A seen=()
  local -a unique=()
  local host

  for host in "${TARGET_HOSTS[@]}"; do
    if [ -z "${seen[$host]+x}" ]; then
      seen["$host"]=1
      unique+=("$host")
    fi
  done

  TARGET_HOSTS=("${unique[@]}")
}

load_targets() {
  TARGET_HOSTS=()
  read_inventory "$INVENTORY_FILE"
  read_inline_hosts "$CLI_MULTI_HOSTS"
  dedupe_targets

  if [ "${#TARGET_HOSTS[@]}" -eq 0 ]; then
    die "$EX_MISSING_PARAM" "aucune cible; utiliser -m ou -i/INVENTORY_FILE"
  fi
}
