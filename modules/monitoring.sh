# Monitoring, alerting, CSV, and HTML reports.

monitor_remote_metrics() {
  local host="$1"
  local remote_script
  remote_script='
uptime_line=$(uptime 2>/dev/null || true)
ram_line=$(free -m 2>/dev/null | awk "/Mem:/{print \$2,\$3}" || true)
disk_pct=$(df -P / 2>/dev/null | awk "NR==2{gsub(/%/,\"\",\$5); print \$5}" || true)
cpu_idle=$(top -bn1 2>/dev/null | awk -F"[, ]+" "/Cpu\\(s\\)|%Cpu/{for(i=1;i<=NF;i++){if(\$i ~ /^id/){print prev; exit} prev=\$i}}" || true)
load_avg=$(printf "%s" "$uptime_line" | awk -F"load average:" "{print \$2}" | xargs)
up_clean=$(printf "%s" "$uptime_line" | awk -F" up " "{print \$2}" | awk -F"," "{print \$1}" | xargs)
ram_total=$(printf "%s" "$ram_line" | awk "{print \$1}")
ram_used=$(printf "%s" "$ram_line" | awk "{print \$2}")
if [ -n "$ram_total" ] && [ "$ram_total" -gt 0 ] 2>/dev/null; then ram_pct=$((ram_used * 100 / ram_total)); else ram_pct=0; fi
cpu_pct=$(awk -v idle="${cpu_idle:-100}" "BEGIN { v=100-idle; if (v<0) v=0; printf \"%d\", v }" 2>/dev/null || printf "0")
printf "cpu=%s ram=%s disk=%s uptime=%s load=%s\n" "${cpu_pct:-0}" "${ram_pct:-0}" "${disk_pct:-0}" "${up_clean:-unknown}" "${load_avg:-unknown}"
'
  ssh_exec "$host" "$remote_script"
}

parse_metric_field() {
  local line="$1" key="$2"
  printf '%s\n' "$line" | sed -n "s/.*${key}=\\([^ ]*\\).*/\\1/p"
}

monitor_status() {
  local cpu="$1" ram="$2" disk="$3" threshold="$4"
  if [ "${cpu:-0}" -gt "$threshold" ] || [ "${ram:-0}" -gt "$threshold" ] || [ "${disk:-0}" -gt "$threshold" ]; then
    printf 'ALERTE'
  else
    printf 'OK'
  fi
}

write_monitor_csv() {
  local host="$1" line="$2" status="$3"
  local csv_file="${REPORT_DIR%/}/rapport_sysremote.csv"
  local cpu ram disk uptime load ts

  mkdir -p "$REPORT_DIR" || die "$EX_CONFIG" "cannot create report directory: $REPORT_DIR"
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  cpu="$(parse_metric_field "$line" cpu)"
  ram="$(parse_metric_field "$line" ram)"
  disk="$(parse_metric_field "$line" disk)"
  uptime="$(parse_metric_field "$line" uptime)"
  load="${line#* load=}"

  if [ ! -f "$csv_file" ]; then
    printf 'Horodatage,Machine,CPU%%,RAM%%,Disque%%,Uptime,Load Average,Statut\n' > "$csv_file"
  fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(csv_escape "$ts")" "$(csv_escape "$host")" "$cpu" "$ram" "$disk" "$(csv_escape "$uptime")" "$(csv_escape "$load")" "$status" >> "$csv_file"
  printf 'csv report updated: %s\n' "$csv_file"
}

write_monitor_html_header() {
  local html_file="$1"
  mkdir -p "$REPORT_DIR" || die "$EX_CONFIG" "cannot create report directory: $REPORT_DIR"
  {
    printf '<!doctype html><html lang="fr"><head><meta charset="utf-8">\n'
    printf '<title>Rapport Sysremote</title><style>body{font-family:monospace;background:#111;color:#ddd;padding:24px}table{border-collapse:collapse;width:100%%}th,td{border:1px solid #333;padding:8px}.OK{background:#102014}.ALERTE{background:#302810}.CRITIQUE{background:#351515}</style></head><body>\n'
    printf '<h1>Rapport Sysremote</h1><p>Genere le %s sur %s</p><table><thead><tr><th>Horodatage</th><th>Machine</th><th>CPU%%</th><th>RAM%%</th><th>Disque%%</th><th>Uptime</th><th>Load</th><th>Statut</th></tr></thead><tbody>\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(hostname)"
  } > "$html_file"
}

write_monitor_html() {
  local host="$1" line="$2" status="$3"
  local html_file="${REPORT_DIR%/}/rapport_sysremote.html"
  local cpu ram disk uptime load ts

  [ -f "$html_file" ] || write_monitor_html_header "$html_file"
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  cpu="$(parse_metric_field "$line" cpu)"
  ram="$(parse_metric_field "$line" ram)"
  disk="$(parse_metric_field "$line" disk)"
  uptime="$(parse_metric_field "$line" uptime)"
  load="${line#* load=}"
  printf '<tr class="%s"><td>%s</td><td>%s</td><td>%s%%</td><td>%s%%</td><td>%s%%</td><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
    "$status" "$(html_escape "$ts")" "$(html_escape "$host")" "$cpu" "$ram" "$disk" "$(html_escape "$uptime")" "$(html_escape "$load")" "$status" >> "$html_file"
  printf 'html report updated: %s\n' "$html_file"
}

close_monitor_html() {
  local html_file="${REPORT_DIR%/}/rapport_sysremote.html"
  [ -f "$html_file" ] || return 0
  if ! tail -n 1 "$html_file" | grep -q '</html>'; then
    printf '</tbody></table></body></html>\n' >> "$html_file"
  fi
}

send_monitor_notification() {
  local host="$1" status="$2" line="$3"
  local payload code subject

  [ "$status" != "OK" ] || return 0
  if [ "$NOTIF_DISCORD" = "true" ]; then
    [ -n "$DISCORD_WEBHOOK" ] || die "$EX_CONFIG" "DISCORD_WEBHOOK is required when NOTIF_DISCORD=true"
    check_dep curl
    payload="$(printf '{"content":"Sysremote %s on %s: %s"}' "$status" "$host" "$(printf '%s' "$line" | sed 's/"/\\"/g')")"
    code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -X POST -d "$payload" "$DISCORD_WEBHOOK" 2>/dev/null || true)"
    [ "$code" = "204" ] || log_warn "Discord notification returned HTTP $code"
  fi
  if [ "$NOTIF_EMAIL" = "true" ]; then
    [ -n "$EMAIL_DESTINATAIRE" ] || die "$EX_CONFIG" "EMAIL_DESTINATAIRE is required when NOTIF_EMAIL=true"
    check_dep mail
    subject="[Sysremote] ${status} ${host}"
    printf '%s\n' "$line" | mail -s "$subject" "$EMAIL_DESTINATAIRE" || log_warn "email notification failed"
  fi
}

cmd_monitor() {
  local do_check="false" do_csv="false" do_html="$GENERER_HTML" do_notify="false"
  local threshold="$SEUIL_ALERTE" host line cpu ram disk status answer

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check) do_check="true"; shift ;;
      --alert) threshold="${2:-}"; [ -n "$threshold" ] || die "$EX_MISSING_PARAM" "alert threshold missing"; shift 2 ;;
      --csv) do_csv="true"; shift ;;
      --html) do_html="true"; shift ;;
      --no-html) do_html="false"; shift ;;
      --notify) do_notify="true"; shift ;;
      --interactive) MONITOR_INTERACTIVE="true"; shift ;;
      *) die "$EX_INVALID_OPTION" "unknown monitor option: $1" ;;
    esac
  done

  is_positive_int "$threshold" && [ "$threshold" -le 100 ] || die "$EX_INVALID_PARAM" "threshold must be 1..100"

  for host in "${TARGET_HOSTS[@]}"; do
    if [ "$MONITOR_INTERACTIVE" = "true" ]; then
      printf 'Run monitoring on %s? [y/N] ' "$host" >&2
      read -r answer
      case "$answer" in y|Y|yes|YES) ;; *) log_info "monitoring skipped for $host"; continue ;; esac
    fi

    if [ "$DRY_RUN" = "true" ]; then
      line="cpu=0 ram=0 disk=0 uptime=dry-run load=dry-run"
      printf '[dry-run] monitor %s\n' "$host"
    else
      line="$(monitor_remote_metrics "$host")" || return "$?"
    fi

    cpu="$(parse_metric_field "$line" cpu)"
    ram="$(parse_metric_field "$line" ram)"
    disk="$(parse_metric_field "$line" disk)"
    status="$(monitor_status "$cpu" "$ram" "$disk" "$threshold")"
    printf '%s status=%s threshold=%s %s\n' "$host" "$status" "$threshold" "$line"
    [ "$do_check" = "true" ] && printf '%s health=%s\n' "$host" "$status"
    [ "$do_csv" = "true" ] && write_monitor_csv "$host" "$line" "$status"
    [ "$do_html" = "true" ] && write_monitor_html "$host" "$line" "$status"
    [ "$do_notify" = "true" ] && send_monitor_notification "$host" "$status" "$line"
  done
  if [ "$do_html" = "true" ]; then
    close_monitor_html
  fi
  return "$EX_OK"
}

cmd_metrics() {
  cmd_monitor --no-html "$@"
}
