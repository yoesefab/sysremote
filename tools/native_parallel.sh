#!/usr/bin/env bash
# =============================================================================
# sysremote_parallel.sh — Lot 3: Parallélisation, multi-cibles et SCP
# Modes : séquentiel (-q), subshell (-s), fork (-f via C), thread (-t via C)
# =============================================================================

set -uo pipefail

# --------------------------------------------------------------------------- #
# Valeurs par défaut
# --------------------------------------------------------------------------- #
MODE="sequential"
MAX_PROCS=0
TIMEOUT=10
SSH_USER="${USER}"
SSH_PORT=22
SCP_SRC=""
SCP_DST="/tmp"
TARGETS_FILE=""
COMMAND=""
BENCHMARK=false
VERBOSE=false
LOG_DIR="/tmp/sysremote_logs_$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cleanup_log_dir() {
    case "$LOG_DIR" in
        /tmp/sysremote_logs_*) rm -rf "$LOG_DIR" ;;
    esac
}

# --------------------------------------------------------------------------- #
# Aide
# --------------------------------------------------------------------------- #
usage() {
    cat <<EOF
Usage: $0 [OPTIONS] -H HOSTS_FILE -- COMMAND
       $0 [OPTIONS] -H HOSTS_FILE --scp SRC DST

Options générales:
  -H, --hosts FILE        Fichier d'inventaire (une IP/hostname par ligne)
  -u, --user USER         Utilisateur SSH (défaut: \$USER)
  -p, --port PORT         Port SSH (défaut: 22)
  -T, --timeout SEC       Timeout par hôte (défaut: 10s)
  -v, --verbose           Affichage verbeux

Mode d'exécution:
  -q, --sequential        Mode séquentiel (défaut)
  -s, --subshell          Mode subshell Bash (background &)
  -f, --fork              Mode fork() C [requiert sysremote_fork]
  -t, --thread            Mode pthread C  [requiert sysremote_thread]

Limitation:
  --max-procs N           Limite le nombre de processus/threads simultanés

Transfert SCP:
  --scp SRC DST           Copier SRC vers DST sur toutes les cibles

Divers:
  --benchmark             Comparer tous les modes et afficher un rapport
  -h, --help              Afficher cette aide
EOF
    exit 0
}

# --------------------------------------------------------------------------- #
# Parsing des arguments
# --------------------------------------------------------------------------- #
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -H|--hosts)      TARGETS_FILE="$2"; shift 2 ;;
            -u|--user)       SSH_USER="$2";      shift 2 ;;
            -p|--port)       SSH_PORT="$2";       shift 2 ;;
            -T|--timeout)    TIMEOUT="$2";        shift 2 ;;
            -v|--verbose)    VERBOSE=true;        shift   ;;
            -q|--sequential) MODE="sequential";  shift   ;;
            -s|--subshell)   MODE="subshell";    shift   ;;
            -f|--fork)       MODE="fork";        shift   ;;
            -t|--thread)     MODE="thread";      shift   ;;
            --max-procs)     MAX_PROCS="$2";     shift 2 ;;
            --scp)           SCP_SRC="$2"; SCP_DST="$3"; shift 3 ;;
            --benchmark)     BENCHMARK=true;     shift   ;;
            -h|--help)       usage ;;
            --)              shift; COMMAND="$*"; break ;;
            *)               echo "Option inconnue: $1" >&2; usage ;;
        esac
    done
}

# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #
validate() {
    [[ -z "$TARGETS_FILE" ]] && { echo "ERREUR: -H requis" >&2; exit 1; }
    [[ ! -f "$TARGETS_FILE" ]] && { echo "ERREUR: fichier '$TARGETS_FILE' introuvable" >&2; exit 1; }
    [[ -z "$COMMAND" && -z "$SCP_SRC" && "$BENCHMARK" == false ]] && {
        echo "ERREUR: spécifiez une commande (--) ou --scp ou --benchmark" >&2; exit 1
    }
}

# --------------------------------------------------------------------------- #
# Interface commune : exécuter une commande SSH sur un hôte
# --------------------------------------------------------------------------- #
run_on_host() {
    local host="$1"
    local cmd="$2"
    local log_file="$LOG_DIR/${host}.log"

    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$TIMEOUT" \
        -o BatchMode=yes \
        -p "$SSH_PORT" \
        "${SSH_USER}@${host}" "$cmd" \
        >"$log_file" 2>&1
    local rc=$?

    if [[ "$VERBOSE" == true ]]; then
        echo "=== [$host] rc=$rc ==="
        cat "$log_file"
    else
        echo "[$host] rc=$rc"
    fi
    return $rc
}

# --------------------------------------------------------------------------- #
# Transfert SCP sur un hôte
# --------------------------------------------------------------------------- #
scp_to_host() {
    local host="$1"
    local src="$2"
    local dst="$3"
    local log_file="$LOG_DIR/${host}_scp.log"

    scp -o StrictHostKeyChecking=no \
        -o ConnectTimeout="$TIMEOUT" \
        -P "$SSH_PORT" \
        "$src" \
        "${SSH_USER}@${host}:${dst}" \
        >"$log_file" 2>&1
    local rc=$?
    echo "[SCP $host] rc=$rc"
    return $rc
}

# --------------------------------------------------------------------------- #
# MODE 1 : Séquentiel — référence pour comparaison
# --------------------------------------------------------------------------- #
mode_sequential() {
    local action="${1:-cmd}"
    local -a hosts
    mapfile -t hosts < <(grep -v '^\s*#' "$TARGETS_FILE" | grep -v '^\s*$')
    local total=${#hosts[@]}
    local ok=0 fail=0

    echo "[séquentiel] ${total} hôtes"
    local t_start; t_start=$(date +%s%N)

    for host in "${hosts[@]}"; do
        if [[ "$action" == "scp" ]]; then
            scp_to_host "$host" "$SCP_SRC" "$SCP_DST" && ((ok++)) || ((fail++))
        else
            run_on_host "$host" "$COMMAND" && ((ok++)) || ((fail++))
        fi
    done

    local t_end; t_end=$(date +%s%N)
    local elapsed=$(( (t_end - t_start) / 1000000 ))
    echo "[séquentiel] OK=$ok FAIL=$fail durée=${elapsed}ms"
    echo "$elapsed"
}

# --------------------------------------------------------------------------- #
# MODE 2 : Subshell Bash — background & avec wait et collecte des statuts
# --------------------------------------------------------------------------- #
mode_subshell() {
    local action="${1:-cmd}"
    local -a hosts
    mapfile -t hosts < <(grep -v '^\s*#' "$TARGETS_FILE" | grep -v '^\s*$')
    local total=${#hosts[@]}
    local ok=0 fail=0
    local -a pids=()
    local running=0

    echo "[subshell] ${total} hôtes, max-procs=${MAX_PROCS}"
    local t_start; t_start=$(date +%s%N)

    for host in "${hosts[@]}"; do
        # Limitation du nombre de subshells simultanés
        if [[ "$MAX_PROCS" -gt 0 ]]; then
            while [[ $running -ge $MAX_PROCS ]]; do
                for i in "${!pids[@]}"; do
                    if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                        wait "${pids[$i]}" && ((ok++)) || ((fail++))
                        unset 'pids[$i]'
                        ((running--))
                        break
                    fi
                done
                sleep 0.1
            done
        fi

        if [[ "$action" == "scp" ]]; then
            ( scp_to_host "$host" "$SCP_SRC" "$SCP_DST" ) &
        else
            ( run_on_host "$host" "$COMMAND" ) &
        fi
        pids+=($!)
        ((running++))
    done

    # Attendre tous les processus restants et récupérer leurs statuts
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            wait "$pid" && ((ok++)) || ((fail++))
        fi
    done

    local t_end; t_end=$(date +%s%N)
    local elapsed=$(( (t_end - t_start) / 1000000 ))
    echo "[subshell] OK=$ok FAIL=$fail durée=${elapsed}ms"
    echo "$elapsed"
}

# --------------------------------------------------------------------------- #
# MODE 3 : fork() — délégation au binaire C
# --------------------------------------------------------------------------- #
mode_fork() {
    local action="${1:-cmd}"
    local bin
    bin="$ROOT_DIR/build/native/sysremote_fork"
    [[ ! -x "$bin" ]] && { echo "ERREUR: '$bin' introuvable. Lancez: make native" >&2; exit 1; }

    local t_start; t_start=$(date +%s%N)
    local args=(-H "$TARGETS_FILE" -u "$SSH_USER" -p "$SSH_PORT" -T "$TIMEOUT" -L "$LOG_DIR")
    [[ "$MAX_PROCS" -gt 0 ]] && args+=(--max-procs "$MAX_PROCS")
    if [[ "$action" == "scp" ]]; then
        args+=(--scp "$SCP_SRC" "$SCP_DST")
    else
        args+=(-- "$COMMAND")
    fi

    "$bin" "${args[@]}"
    local t_end; t_end=$(date +%s%N)
    local elapsed=$(( (t_end - t_start) / 1000000 ))
    echo "[fork] durée=${elapsed}ms"
    echo "$elapsed"
}

# --------------------------------------------------------------------------- #
# MODE 4 : pthread — délégation au binaire C
# --------------------------------------------------------------------------- #
mode_thread() {
    local action="${1:-cmd}"
    local bin
    bin="$ROOT_DIR/build/native/sysremote_thread"
    [[ ! -x "$bin" ]] && { echo "ERREUR: '$bin' introuvable. Lancez: make native" >&2; exit 1; }

    local t_start; t_start=$(date +%s%N)
    local args=(-H "$TARGETS_FILE" -u "$SSH_USER" -p "$SSH_PORT" -T "$TIMEOUT" -L "$LOG_DIR")
    [[ "$MAX_PROCS" -gt 0 ]] && args+=(--max-procs "$MAX_PROCS")
    if [[ "$action" == "scp" ]]; then
        args+=(--scp "$SCP_SRC" "$SCP_DST")
    else
        args+=(-- "$COMMAND")
    fi

    "$bin" "${args[@]}"
    local t_end; t_end=$(date +%s%N)
    local elapsed=$(( (t_end - t_start) / 1000000 ))
    echo "[thread] durée=${elapsed}ms"
    echo "$elapsed"
}

# --------------------------------------------------------------------------- #
# BENCHMARK — compare les 4 modes
# --------------------------------------------------------------------------- #
run_benchmark() {
    echo "======================================================"
    echo "  BENCHMARK sysremote — comparaison des modes"
    echo "======================================================"
    COMMAND="${COMMAND:-uptime}"

    local -A results

    echo "--- Mode séquentiel ---"
    results[sequential]=$(mode_sequential cmd | tail -1)

    echo "--- Mode subshell ---"
    results[subshell]=$(mode_subshell cmd | tail -1)

    if [[ -x "$ROOT_DIR/build/native/sysremote_fork" ]]; then
        echo "--- Mode fork ---"
        results[fork]=$(mode_fork cmd | tail -1)
    else
        results[fork]="N/A (non compilé)"
    fi

    if [[ -x "$ROOT_DIR/build/native/sysremote_thread" ]]; then
        echo "--- Mode thread ---"
        results[thread]=$(mode_thread cmd | tail -1)
    else
        results[thread]="N/A (non compilé)"
    fi

    echo ""
    echo "======================================================"
    echo "  RAPPORT BENCHMARK"
    echo "======================================================"
    printf "%-15s %s\n" "Mode" "Durée (ms)"
    printf "%-15s %s\n" "---------------" "----------"
    for mode in sequential subshell fork thread; do
        printf "%-15s %s\n" "$mode" "${results[$mode]}"
    done
    echo ""
    echo "Logs disponibles dans : $LOG_DIR"
}

# --------------------------------------------------------------------------- #
# Point d'entrée
# --------------------------------------------------------------------------- #
main() {
    parse_args "$@"
    [[ "$BENCHMARK" == false ]] && validate

    mkdir -p "$LOG_DIR"
    trap cleanup_log_dir EXIT

    local action="cmd"
    [[ -n "$SCP_SRC" ]] && action="scp"

    if [[ "$BENCHMARK" == true ]]; then
        run_benchmark
        return
    fi

    case "$MODE" in
        sequential) mode_sequential "$action" ;;
        subshell)   mode_subshell   "$action" ;;
        fork)       mode_fork       "$action" ;;
        thread)     mode_thread     "$action" ;;
        *)          echo "Mode inconnu: $MODE" >&2; exit 1 ;;
    esac
}

main "$@"
