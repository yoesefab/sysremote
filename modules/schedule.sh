# Cron scheduling module.

cmd_schedule() {
  local action="" cron_expr="" cron_cmd="" cron_file="/etc/cron.d/${PROGRAM_NAME}"
  local fields tmp

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --add)
        action="add"
        cron_expr="${2:-}"
        cron_cmd="${3:-}"
        [ -n "$cron_expr" ] && [ -n "$cron_cmd" ] || die "$EX_MISSING_PARAM" "schedule --add requires cron expression and command"
        shift 3
        ;;
      --list) action="list"; shift ;;
      --remove) action="remove"; shift ;;
      *) die "$EX_INVALID_OPTION" "unknown schedule option: $1" ;;
    esac
  done

  [ -n "$action" ] || die "$EX_MISSING_PARAM" "schedule action required: --add, --list or --remove"

  case "$action" in
    add)
      require_root_for_sensitive_action
      fields="$(printf '%s\n' "$cron_expr" | awk '{print NF}')"
      [ "$fields" -eq 5 ] || die "$EX_INVALID_PARAM" "invalid cron expression; expected 5 fields"
      if [ "$DRY_RUN" = "true" ]; then
        printf '[dry-run] add cron: %s root %s # %s\n' "$cron_expr" "$cron_cmd" "$CRON_TAG"
        return "$EX_OK"
      fi
      tmp="$(mktemp "${TMPDIR:-/tmp}/sysremote-cron.XXXXXX")" || die "$EX_CONFIG" "cannot create temporary cron file"
      if [ -f "$cron_file" ]; then
        grep -v "$CRON_TAG" "$cron_file" > "$tmp" || true
      else
        {
          printf '# %s\n' "$CRON_TAG"
          printf 'SHELL=/bin/bash\n'
          printf 'PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\n'
        } > "$tmp"
      fi
      printf '%s root %s # %s\n' "$cron_expr" "$cron_cmd" "$CRON_TAG" >> "$tmp"
      install -m 0644 "$tmp" "$cron_file" || die "$EX_CRON" "cannot install cron file: $cron_file"
      rm -f "$tmp"
      printf 'scheduled: [%s] %s\n' "$cron_expr" "$cron_cmd"
      ;;
    list)
      if [ -f "$cron_file" ]; then
        grep "$CRON_TAG" "$cron_file" || true
      else
        printf 'no scheduled tasks\n'
      fi
      ;;
    remove)
      require_root_for_sensitive_action
      if [ "$DRY_RUN" = "true" ]; then
        printf '[dry-run] remove cron file: %s\n' "$cron_file"
        return "$EX_OK"
      fi
      if [ -f "$cron_file" ]; then
        rm -f "$cron_file" || die "$EX_CRON" "cannot remove cron file: $cron_file"
        printf 'scheduled tasks removed\n'
      else
        printf 'no scheduled tasks\n'
      fi
      ;;
  esac
}
