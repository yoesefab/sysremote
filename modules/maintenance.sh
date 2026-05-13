# Maintenance module: package updates and safe cleanup.

cmd_maintain() {
  local do_update=0 do_clean=0
  local old

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --update) do_update=1; shift ;;
      --clean) do_clean=1; shift ;;
      *) die "$EX_INVALID_OPTION" "unknown maintain option: $1" ;;
    esac
  done

  [ "$do_update" -eq 1 ] || [ "$do_clean" -eq 1 ] || die "$EX_MISSING_PARAM" "maintain requires --update and/or --clean"
  require_root_for_sensitive_action

  if [ "$DRY_RUN" = "true" ]; then
    printf '[dry-run] maintain update=%s clean=%s backup_dir=%s\n' "$do_update" "$do_clean" "$DEFAULT_BACKUP_DIR"
    return "$EX_OK"
  fi

  if [ "$do_update" -eq 1 ]; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -q || die "$EX_REMOTE" "apt-get update failed"
      apt-get upgrade -y --only-upgrade || die "$EX_REMOTE" "apt-get upgrade failed"
    elif command -v dnf >/dev/null 2>&1; then
      dnf upgrade --security -y || die "$EX_REMOTE" "dnf security upgrade failed"
    else
      log_warn "no supported package manager found"
    fi
  fi

  if [ "$do_clean" -eq 1 ]; then
    if [ -d "$DEFAULT_BACKUP_DIR" ]; then
      find "$DEFAULT_BACKUP_DIR" -maxdepth 1 -name 'snap-*' -type d -print \
        | sort | head -n -5 \
        | while IFS= read -r old; do
            case "$old" in
              "$DEFAULT_BACKUP_DIR"/snap-*) rm -rf "$old" ;;
              *) log_warn "refusing to remove unexpected path: $old" ;;
            esac
          done
    fi
    if command -v apt-get >/dev/null 2>&1; then
      apt-get autoremove -y || log_warn "apt autoremove failed"
      apt-get clean || log_warn "apt clean failed"
    fi
  fi

  printf 'maintenance complete\n'
}
