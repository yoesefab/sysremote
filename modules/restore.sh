# Restore module.

cmd_restore() {
  local archive="" target="$DEFAULT_RESTORE_DIR"
  local working_archive dec_archive

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -A|--archive) archive="${2:-}"; [ -n "$archive" ] || die "$EX_MISSING_PARAM" "restore archive missing"; shift 2 ;;
      -T|--target) target="${2:-}"; [ -n "$target" ] || die "$EX_MISSING_PARAM" "restore target missing"; shift 2 ;;
      *) die "$EX_INVALID_OPTION" "unknown restore option: $1" ;;
    esac
  done

  require_root_for_sensitive_action
  check_dep tar
  [ -n "$archive" ] || die "$EX_MISSING_PARAM" "restore archive is required (-A)"
  [ -f "$archive" ] || die "$EX_CONFIG" "archive not found: $archive"

  if [ "$DRY_RUN" = "true" ]; then
    printf '[dry-run] restore archive=%s target=%s\n' "$archive" "$target"
    return "$EX_OK"
  fi

  mkdir -p "$target" || die "$EX_CONFIG" "cannot create restore target: $target"
  working_archive="$archive"

  if [[ "$archive" == *.enc ]]; then
    check_dep openssl
    local decrypt_pass
    read -r -s -p "Decryption passphrase: " decrypt_pass; printf '\n'
    dec_archive="$(mktemp "${TMPDIR:-/tmp}/sysremote-restore.XXXXXX.tar.gz")" || die "$EX_CONFIG" "cannot create temporary archive"
    printf '%s' "$decrypt_pass" | openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass stdin -in "$archive" -out "$dec_archive" \
      || die "$EX_CONFIG" "OpenSSL decryption failed"
    working_archive="$dec_archive"
    unset decrypt_pass
  fi

  tar -xzf "$working_archive" -C "$target" || die "$EX_CONFIG" "tar extraction failed"
  [ "$working_archive" != "$archive" ] && rm -f "$working_archive"
  printf 'restore complete: %s\n' "$target"
}
