#!/usr/bin/env bash
# benchmark.sh — Lot 3: Comparaison des modes d'exécution sysremote
# Usage: ./benchmark.sh -H hosts.txt [-c "commande"] [--max-procs N] [-i N]

set -euo pipefail

HOSTS_FILE=""
COMMAND="uptime"
MAX_PROCS=0
ITERATIONS=3
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<EOF
Usage: $0 -H HOSTS_FILE [-c COMMAND] [--max-procs N] [-i ITERATIONS]
  -H HOSTS_FILE     Fichier d'inventaire SSH
  -c COMMAND        Commande à exécuter (défaut: uptime)
  --max-procs N     Limite de concurrence (0 = illimité)
  -i ITERATIONS     Nombre de répétitions pour moyenner (défaut: 3)
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -H) HOSTS_FILE="$2"; shift 2 ;;
        -c) COMMAND="$2";    shift 2 ;;
        --max-procs) MAX_PROCS="$2"; shift 2 ;;
        -i) ITERATIONS="$2"; shift 2 ;;
        -h) usage ;;
        *)  echo "Option inconnue: $1" >&2; usage ;;
    esac
done

[[ -z "$HOSTS_FILE" ]]   && { echo "ERREUR: -H requis" >&2; exit 1; }
[[ ! -f "$HOSTS_FILE" ]] && { echo "ERREUR: '$HOSTS_FILE' introuvable" >&2; exit 1; }

NB_HOSTS=$(grep -cv '^\s*#\|^\s*$' "$HOSTS_FILE" || true)

run_mode() {
    local mode_flag="$1"
    local total=0
    for ((i=1; i<=ITERATIONS; i++)); do
        local t_start; t_start=$(date +%s%N)
        local mp_arg=""
        [[ "$MAX_PROCS" -gt 0 ]] && mp_arg="--max-procs $MAX_PROCS"
        case "$mode_flag" in
            "-f")
                local bin="$ROOT_DIR/build/native/sysremote_fork"
                [[ ! -x "$bin" ]] && { echo "N/A"; return; }
                "$bin" -H "$HOSTS_FILE" $mp_arg -- "$COMMAND" >/dev/null 2>&1 || true ;;
            "-t")
                local bin="$ROOT_DIR/build/native/sysremote_thread"
                [[ ! -x "$bin" ]] && { echo "N/A"; return; }
                "$bin" -H "$HOSTS_FILE" $mp_arg -- "$COMMAND" >/dev/null 2>&1 || true ;;
            *)
                "$SCRIPT_DIR/native_parallel.sh" \
                    "$mode_flag" -H "$HOSTS_FILE" $mp_arg \
                    -- "$COMMAND" >/dev/null 2>&1 || true ;;
        esac
        local t_end; t_end=$(date +%s%N)
        local elapsed=$(( (t_end - t_start) / 1000000 ))
        total=$((total + elapsed))
        echo "  run $i/${ITERATIONS}: ${elapsed}ms" >&2
    done
    echo $(( total / ITERATIONS ))
}

speedup() {
    local base="$1" val="$2"
    [[ "$val" == "N/A" || "$base" -eq 0 ]] && { echo "N/A"; return; }
    local sp=$(( base * 10 / val ))
    echo "${sp::-1}.${sp: -1}x"
}

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          BENCHMARK sysremote — Lot 3                    ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  Hôtes: %-3d  Commande: %-28s ║\n" "$NB_HOSTS" "$COMMAND"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

declare -A RESULTS
echo "▶ Mode séquentiel...";  RESULTS[sequential]=$(run_mode "-q")
echo "▶ Mode subshell...";    RESULTS[subshell]=$(run_mode "-s")
echo "▶ Mode fork C...";      RESULTS[fork]=$(run_mode "-f")
echo "▶ Mode thread C...";    RESULTS[thread]=$(run_mode "-t")

BASE="${RESULTS[sequential]}"
echo ""
printf "  %-15s %10s %12s\n" "Mode" "Durée moy." "Speedup"
printf "  %-15s %10s %12s\n" "---------------" "----------" "-------"
printf "  %-15s %8sms %12s\n" "Séquentiel"  "${RESULTS[sequential]}"  "1.0x (ref)"
printf "  %-15s %8sms %12s\n" "Subshell"    "${RESULTS[subshell]}"    "$(speedup "$BASE" "${RESULTS[subshell]}")"
printf "  %-15s %8sms %12s\n" "Fork C"      "${RESULTS[fork]}"        "$(speedup "$BASE" "${RESULTS[fork]}")"
printf "  %-15s %8sms %12s\n" "Thread C"    "${RESULTS[thread]}"      "$(speedup "$BASE" "${RESULTS[thread]}")"
