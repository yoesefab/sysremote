# Local security audit module.

audit_permissions() {
  local issues=0
  local file actual owner expected ww

  printf '%s\n' '--- Sensitive file permissions ---'
  for file in "${SENSITIVE_FILES[@]}"; do
    case "$file" in
      /etc/passwd) expected="644" ;;
      /etc/shadow) expected="640" ;;
      /etc/sudoers) expected="440" ;;
      /etc/ssh/sshd_config) expected="600" ;;
      *) expected="" ;;
    esac

    if [ ! -e "$file" ]; then
      log_warn "$file absent, ignored"
      continue
    fi

    actual="$(stat -c '%a' "$file" 2>/dev/null || printf 'unknown')"
    owner="$(stat -c '%U:%G' "$file" 2>/dev/null || printf 'unknown')"
    if [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
      printf '%-30s perms=%-5s owner=%-12s WARN expected=%s\n' "$file" "$actual" "$owner" "$expected"
      issues=$((issues + 1))
    else
      printf '%-30s perms=%-5s owner=%-12s OK\n' "$file" "$actual" "$owner"
    fi
  done

  ww="$(find /etc -maxdepth 2 -perm -o+w -type f -print 2>/dev/null || true)"
  if [ -n "$ww" ]; then
    printf 'world-writable files under /etc:\n%s\n' "$ww"
    issues=$((issues + 1))
  fi
  printf 'permission issues: %s\n' "$issues"
}

audit_logins() {
  local auth_log="" file failed root_failed

  printf '%s\n' '--- Failed login analysis ---'
  for file in /var/log/auth.log /var/log/secure /var/log/messages; do
    if [ -r "$file" ]; then
      auth_log="$file"
      break
    fi
  done

  if [ -z "$auth_log" ]; then
    log_warn "no readable authentication log found"
  else
    failed="$(grep -c 'Failed password' "$auth_log" 2>/dev/null || printf '0')"
    root_failed="$(grep -c 'Failed password for root' "$auth_log" 2>/dev/null || printf '0')"
    printf 'auth_log=%s failed_password=%s root_failed=%s\n' "$auth_log" "$failed" "$root_failed"
    grep 'Failed password' "$auth_log" 2>/dev/null \
      | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' \
      | sort | uniq -c | sort -rn | head -10 || true
  fi

  last -n 10 2>/dev/null || log_warn "last command unavailable"
}

audit_ports() {
  local open_ports="" port known kp anomalies=0

  printf '%s\n' '--- Open ports ---'
  if command -v ss >/dev/null 2>&1; then
    open_ports="$(ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | grep -oE '[0-9]+$' | sort -n | uniq || true)"
  elif command -v netstat >/dev/null 2>&1; then
    open_ports="$(netstat -tlnp 2>/dev/null | awk 'NR>2 {print $4}' | grep -oE '[0-9]+$' | sort -n | uniq || true)"
  else
    log_warn "neither ss nor netstat is available"
    return 0
  fi

  while IFS= read -r port; do
    [ -n "$port" ] || continue
    known=0
    for kp in "${KNOWN_PORTS[@]}"; do
      [ "$port" -eq "$kp" ] && known=1 && break
    done
    if [ "$known" -eq 1 ]; then
      printf 'port=%s status=known\n' "$port"
    else
      printf 'port=%s status=unusual\n' "$port"
      anomalies=$((anomalies + 1))
    fi
  done <<< "$open_ports"
  printf 'unusual_ports=%s\n' "$anomalies"
}

cmd_audit() {
  local do_perms=0 do_logins=0 do_ports=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --perms) do_perms=1; shift ;;
      --logins) do_logins=1; shift ;;
      --ports) do_ports=1; shift ;;
      --all) do_perms=1; do_logins=1; do_ports=1; shift ;;
      *) die "$EX_INVALID_OPTION" "unknown audit option: $1" ;;
    esac
  done

  if [ "$do_perms" -eq 0 ] && [ "$do_logins" -eq 0 ] && [ "$do_ports" -eq 0 ]; then
    die "$EX_MISSING_PARAM" "audit requires --perms, --logins, --ports or --all"
  fi

  printf '===== SYSREMOTE AUDIT REPORT =====\n'
  printf 'date=%s host=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(hostname)"
  [ "$do_perms" -eq 1 ] && audit_permissions
  [ "$do_logins" -eq 1 ] && audit_logins
  [ "$do_ports" -eq 1 ] && audit_ports
  printf '===== END AUDIT REPORT =====\n'
}
