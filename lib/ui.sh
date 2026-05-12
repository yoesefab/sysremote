# * Aide, messages et journalisation.

usage() {
  cat <<'USAGE'
sysremote - administration distante multi-hotes

Synopsis:
  sysremote [options] commande [arguments]

Description:
  sysremote fournit une CLI Bash commune pour charger une configuration,
  valider un inventaire de machines, executer des commandes SSH avec timeout
  et gerer les utilisateurs/groupes sur des hotes distants.

Options:
  -h              Affiche cette aide.
  -c FICHIER      Charge un fichier de configuration precis.
  -i FICHIER      Charge un inventaire de cibles, une cible par ligne.
  -m HOTES        Cibles separees par des virgules (ex: srv1,10.0.0.5).
  -l DOSSIER      Dossier de logs (defaut: /var/log/sysremote).
  -U LOGIN        Login SSH distant.
  -p PORT         Port SSH distant.
  -T SECONDES     Timeout de connexion SSH (defaut: 5).
  -f              Mode fork: execute les hotes en processus enfants concurrents.
  -t              Mode thread: execute les hotes via un pool xargs -P.
  -s              Mode subshell: execute le traitement dans un sous-shell.
  -j N            Nombre de workers pour le mode thread (defaut: 4).
  -r              Restaure les reglages par defaut (root uniquement).
  -N              Desactive le controle EUID/root local pour actions sensibles.
  -n              Dry-run: affiche les commandes sans se connecter.
  -v              Mode verbeux.

Commandes:
  validate-hosts
      Valide les cibles configurees sans ouvrir de connexion SSH.

  sessions [who|w]
      Affiche les sessions actives via who ou w.

  create-user UTILISATEUR
      Cree un compte distant avec repertoire home.

  delete-user UTILISATEUR
      Supprime un compte distant et son repertoire home.

  add-user-group UTILISATEUR GROUPE
      Ajoute un utilisateur a un groupe.

  remove-user-group UTILISATEUR GROUPE
      Retire un utilisateur d'un groupe.

  lock-user UTILISATEUR
      Verrouille un compte distant.

  unlock-user UTILISATEUR
      Deverrouille un compte distant.

  archive-logs [DOSSIER]
      Archive et compresse les logs sysremote dans DOSSIER ou ./archives.

  benchmark [light|medium|heavy]
      Compare les modes normal, fork, thread et subshell sur une charge locale.

Codes de retour:
  0   Succes.
  2   Usage invalide ou option inconnue.
  3   Configuration invalide.
  4   Nom d'hote/IP refuse par validation.
  10  Privileges locaux insuffisants pour une action sensible.
  20  Erreur SSH ou hote injoignable.
  21  Commande distante en echec.
  30  Aucune cible exploitable.
  100 Option invalide.
  101 Parametre obligatoire manquant.

Exemples:
  sysremote -m srv-app-01 validate-hosts
  sysremote -l /tmp/sysremote-logs -m srv-app-01 validate-hosts
  sysremote -f -n -m srv-app-01,srv-db-01 sessions who
  sysremote -t -j 2 -n -m srv-app-01,srv-db-01 sessions who
  sysremote -s -m srv-app-01 validate-hosts
  sudo sysremote -r
  sudo sysremote -c ./sysremote.conf -i ./inventory.example create-user alice
  sudo sysremote -m srv-app-01,srv-db-01 add-user-group alice wheel
  sysremote -i ./inventory.example sessions w
  sysremote -l /tmp/sysremote-logs archive-logs ./archives
  sysremote -l /tmp/sysremote-logs benchmark light

Notes:
  Les cibles sont des noms DNS ou IPv4 uniquement. Le login SSH se configure
  avec -U ou SSH_USER dans sysremote.conf, jamais dans le nom d'hote.
USAGE
}

log_info() {
  if [ "$VERBOSE" = "true" ]; then
    printf 'sysremote: %s\n' "$*" >&2
  fi
}

log_error() {
  printf 'sysremote: %s\n' "$*" >&2
}

log_line_direct() {
  local level="$1"
  local message="$2"

  [ "$LOGGING_READY" = "true" ] || return 0
  printf '%s : %s : %s : %s\n' "$(date '+%Y-%m-%d-%H-%M-%S')" "${USER:-unknown}" "$level" "$message" >> "$LOG_FILE"
}

emit_help() {
  local line

  if [ "$LOGGING_READY" = "true" ]; then
    usage >&3
    while IFS= read -r line; do
      log_line_direct "INFOS" "$line"
    done <<< "$(usage)"
  else
    usage
  fi
}

die() {
  local code="$1"
  local message
  shift
  message="$*"

  if [ "$LOGGING_READY" = "true" ]; then
    printf 'sysremote: %s\n' "$message" >&4
    log_line_direct "ERROR" "sysremote: $message"
    usage >&4
    while IFS= read -r line; do
      log_line_direct "ERROR" "$line"
    done <<< "$(usage)"
  else
    printf 'sysremote: %s\n' "$message" >&2
    usage >&2
  fi
  exit "$code"
}

preparse_log_dir() {
  local arg next

  while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
      -l)
        next="${2:-}"
        if [ -n "$next" ]; then
          CLI_LOG_DIR="$next"
          LOG_DIR="$next"
          shift 2
        else
          shift
        fi
        ;;
      -l?*)
        CLI_LOG_DIR="${arg#-l}"
        LOG_DIR="$CLI_LOG_DIR"
        shift
        ;;
      --log-dir=*)
        CLI_LOG_DIR="${arg#--log-dir=}"
        LOG_DIR="$CLI_LOG_DIR"
        shift
        ;;
      --log-dir)
        next="${2:-}"
        if [ -n "$next" ]; then
          CLI_LOG_DIR="$next"
          LOG_DIR="$next"
          shift 2
        else
          shift
        fi
        ;;
      --)
        break
        ;;
      *)
        shift
        ;;
    esac
  done
}

finish_logging() {
  if [ "$LOGGING_READY" = "true" ]; then
    sleep 0.1
    exec 1>&3 2>&4
    exec 3>&- 4>&-
  fi
}

setup_logging() {
  local attempt=1

  LOG_FILE="${LOG_DIR%/}/history.log"
  until mkdir -p "$LOG_DIR" 2>/dev/null; do
    if [ "$attempt" -ge 3 ]; then
      printf 'sysremote: impossible de creer le dossier de logs: %s\n' "$LOG_DIR" >&2
      printf 'sysremote: continuer sans journal fichier; utiliser -l DOSSIER ou sudo pour /var/log/sysremote.\n' >&2
      LOGGING_READY="false"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  if ! touch "$LOG_FILE" 2>/dev/null; then
    printf "sysremote: impossible d'ecrire le log: %s\n" "$LOG_FILE" >&2
    LOGGING_READY="false"
    return 0
  fi

  chmod 640 "$LOG_FILE" 2>/dev/null || true
  LOGGING_READY="true"

  exec 3>&1
  exec 4>&2
  exec > >(while IFS= read -r line; do
    printf '%s\n' "$line" >&3
    printf '%s : %s : INFOS : %s\n' "$(date '+%Y-%m-%d-%H-%M-%S')" "${USER:-unknown}" "$line" >> "$LOG_FILE"
  done)
  exec 2> >(while IFS= read -r line; do
    printf '%s\n' "$line" >&4
    printf '%s : %s : ERROR : %s\n' "$(date '+%Y-%m-%d-%H-%M-%S')" "${USER:-unknown}" "$line" >> "$LOG_FILE"
  done)
  trap finish_logging EXIT
}
