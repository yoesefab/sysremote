# Backup module: incremental rsync snapshots, compression, optional encryption.

cmd_backup() {
  local src="" dst="$DEFAULT_BACKUP_DIR"
  local remote="" compress="false" encrypt="false" tag=""
  local snap_tag snap_dir latest_link="" prev archive src_path

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -S|--source) src="${2:-}"; [ -n "$src" ] || die "$EX_MISSING_PARAM" "backup source missing"; shift 2 ;;
      -D|--dest) dst="${2:-}"; [ -n "$dst" ] || die "$EX_MISSING_PARAM" "backup destination missing"; shift 2 ;;
      --remote) remote="${2:-}"; [ -n "$remote" ] || die "$EX_MISSING_PARAM" "remote target missing"; shift 2 ;;
      --compress) compress="true"; shift ;;
      --encrypt) encrypt="true"; compress="true"; shift ;;
      --tag) tag="${2:-}"; [ -n "$tag" ] || die "$EX_MISSING_PARAM" "backup tag missing"; shift 2 ;;
      *) die "$EX_INVALID_OPTION" "unknown backup option: $1" ;;
    esac
  done

  check_dep rsync
  [ -n "$src" ] || die "$EX_MISSING_PARAM" "backup source is required (-S)"
  [ -d "$src" ] || die "$EX_FILE_NOT_FOUND" "backup source not found: $src"
  if [ -n "$tag" ]; then
    validate_safe_label "$tag" || die "$EX_INVALID_PARAM" "invalid backup tag: $tag"
  fi

  snap_tag="${tag:-snap-$(timestamp_tag)}"
  snap_dir="${dst%/}/${snap_tag}"

  if [ "$DRY_RUN" = "true" ]; then
    printf '[dry-run] backup source=%s dest=%s compress=%s encrypt=%s remote=%s\n' "$src" "$snap_dir" "$compress" "$encrypt" "${remote:-none}"
    return "$EX_OK"
  fi

  mkdir -p "$snap_dir" || die "$EX_CONFIG" "cannot create backup snapshot: $snap_dir"

  prev="$(find "$dst" -maxdepth 1 -mindepth 1 -type d -name 'snap-*' ! -name "$snap_tag" -print 2>/dev/null | sort | tail -1 || true)"
  [ -n "$prev" ] && latest_link="--link-dest=$prev"

  log_info "backup started: $src -> $snap_dir"
  if [ -n "$latest_link" ]; then
    rsync -a --delete "$latest_link" "$src"/ "$snap_dir"/ || die "$EX_REMOTE" "rsync failed"
  else
    rsync -a --delete "$src"/ "$snap_dir"/ || die "$EX_REMOTE" "rsync failed"
  fi

  archive=""
  if [ "$compress" = "true" ]; then
    check_dep tar
    archive="${dst%/}/${snap_tag}.tar.gz"
    tar -czf "$archive" -C "$dst" "$snap_tag" || die "$EX_CONFIG" "tar compression failed: $archive"
    rm -rf "$snap_dir"
    log_info "archive created: $archive"
  fi

  if [ "$encrypt" = "true" ]; then
    check_dep openssl
    [ -n "$archive" ] || die "$EX_CONFIG" "internal backup error: archive missing before encryption"
    local pass1 pass2 enc_file
    read -r -s -p "Encryption passphrase: " pass1; printf '\n'
    read -r -s -p "Confirm passphrase: " pass2; printf '\n'
    [ "$pass1" = "$pass2" ] || die "$EX_CONFIG" "encryption passphrases differ"
    [ "${#pass1}" -ge 8 ] || die "$EX_CONFIG" "encryption passphrase must contain at least 8 characters"
    enc_file="${archive}.enc"
    printf '%s' "$pass1" | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -pass stdin -in "$archive" -out "$enc_file" \
      || die "$EX_CONFIG" "OpenSSL encryption failed"
    rm -f "$archive"
    archive="$enc_file"
    unset pass1 pass2
    log_info "encrypted archive created: $archive"
  fi

  if [ -n "$remote" ]; then
    check_dep rsync ssh
    src_path="${archive:-$snap_dir}"
    rsync -az -e ssh "$src_path" "$remote" || die "$EX_REMOTE" "remote backup transfer failed"
    log_info "remote transfer complete: $remote"
  fi

  printf 'backup complete: %s\n' "${archive:-$snap_dir}"
}
