# Description : Collecte métriques, alertes, rapports CSV/HTML, notifications


# VARIABLES GLOBALES

MODE_INTERACTIF=false
DRY_RUN=false
MACHINE_CIBLE="localhost"
PREMIERE_MACHINE_CSV=true
PREMIERE_MACHINE_HTML=true

# Charger la configuration externe
if [ -f "$HOME/sysremote/sysremote.conf" ]; then
    source "$HOME/sysremote/sysremote.conf"
elif [ -f "./sysremote.conf" ]; then
    source "./sysremote.conf"
elif [ -f "./sysremote.conf.example" ]; then
    source "./sysremote.conf.example"
fi

# Valeurs par défaut si non définies
LOG_DIR="${LOG_DIR:-./logs}"
REPORT_DIR="${REPORT_DIR:-./reports}"
SSH_USER="${SSH_USER:-$USER}"
SSH_TIMEOUT="${SSH_TIMEOUT:-5}"
SEUIL_ALERTE="${SEUIL_ALERTE:-80}"
GENERER_HTML="${GENERER_HTML:-true}"
NOTIF_DISCORD="${NOTIF_DISCORD:-false}"
NOTIF_EMAIL="${NOTIF_EMAIL:-false}"

trap 'fermer_html' EXIT

mkdir -p "$LOG_DIR"
mkdir -p "$REPORT_DIR"

# COULEURS POUR L'AFFICHAGE CONSOLE

ROUGE='\033[0;31m'
VERT='\033[0;32m'
JAUNE='\033[1;33m'
BLEU='\033[0;34m'
RESET='\033[0m'

# FONCTIONS UTILITAIRES

log_info() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d-%H-%M-%S')
    local utilisateur
    utilisateur=$(whoami)
    local entree="${timestamp} : ${utilisateur} : INFOS : ${message}"
    echo -e "${VERT}${entree}${RESET}"
    echo "$entree" >> "${LOG_DIR}/history.log"
}

log_erreur() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d-%H-%M-%S')
    local utilisateur
    utilisateur=$(whoami)
    local entree="${timestamp} : ${utilisateur} : ERROR : ${message}"
    echo -e "${ROUGE}${entree}${RESET}" >&2
    echo "$entree" >> "${LOG_DIR}/history.log"
}

# FONCTIONS PRINCIPALES

collecter_metriques() {
    local hote="$1"

    log_info "Connexion à $hote pour collecte des métriques..."

    # --- Mode dry-run : simuler sans exécuter ---
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Exécuterait SSH vers $hote"
        log_info "[DRY-RUN] Commandes : uptime, free -m, df -h, top -bn1"
        return 0
    fi

    # --- Si localhost, exécuter localement ---
    if [ "$hote" = "localhost" ] || [ "$hote" = "127.0.0.1" ] || [ "$hote" = "$(hostname)" ]; then
        log_info "Exécution locale pour $hote"
        UPTIME_RAW=$(uptime 2>/dev/null)
        RAM_RAW=$(free -m 2>/dev/null)
        DISK_RAW=$(df -h / 2>/dev/null)
        CPU_RAW=$(top -bn1 2>/dev/null)
        log_info "Collecte terminee avec succes pour : $hote"
        normaliser_metriques "$hote"
        return 0
    fi

    # --- Vérifier que la machine est joignable ---
    if ! ssh -o ConnectTimeout="$SSH_TIMEOUT" \
             -o BatchMode=yes \
             "${SSH_USER}@${hote}" "exit" 2>/dev/null; then
        log_erreur "Machine $hote inaccessible (timeout ou refus SSH)"
        return 1
    fi

    # --- Collecter uptime ---
    UPTIME_RAW=$(ssh -o ConnectTimeout="$SSH_TIMEOUT" \
                     -o BatchMode=yes \
                     "${SSH_USER}@${hote}" "uptime" 2>/dev/null)

    # --- Collecter RAM ---
    RAM_RAW=$(ssh -o ConnectTimeout="$SSH_TIMEOUT" \
                  -o BatchMode=yes \
                  "${SSH_USER}@${hote}" "free -m" 2>/dev/null)

    # --- Collecter Disque ---
    DISK_RAW=$(ssh -o ConnectTimeout="$SSH_TIMEOUT" \
                   -o BatchMode=yes \
                   "${SSH_USER}@${hote}" "df -h /" 2>/dev/null)

    # --- Collecter CPU via top ---
    CPU_RAW=$(ssh -o ConnectTimeout="$SSH_TIMEOUT" \
                  -o BatchMode=yes \
                  "${SSH_USER}@${hote}" "top -bn1" 2>/dev/null)

    log_info "Collecte terminee avec succes pour : $hote"

    # --- Normaliser et afficher ---
    normaliser_metriques "$hote"
}

normaliser_metriques() {
    local hote="$1"

    # --- Extraire CPU % idle depuis top ---
    local cpu_idle
    cpu_idle=$(echo "$CPU_RAW" | grep "Cpu(s)" | awk '{print $8}' | tr -d '%us,')
 
   # CPU utilisé = 100 - idle
    CPU_PERCENT=$(echo "100 - ${cpu_idle:-100}" | bc 2>/dev/null || echo "0")
    CPU_PERCENT=${CPU_PERCENT%.*}    # garder seulement la partie entière

    # --- Extraire RAM depuis free -m ---
    local ram_total ram_used
    ram_total=$(echo "$RAM_RAW" | awk '/Mem:/{print $2}')
    ram_used=$(echo "$RAM_RAW"  | awk '/Mem:/{print $3}')
    if [ -n "$ram_total" ] && [ "$ram_total" -gt 0 ]; then
        RAM_PERCENT=$(( ram_used * 100 / ram_total ))
    else
        RAM_PERCENT=0
    fi

    # --- Extraire disque depuis df -h ---
    DISK_PERCENT=$(echo "$DISK_RAW" | awk 'NR==2{print $5}' | tr -d '%')

    # --- Extraire uptime lisible ---
    UPTIME_CLEAN=$(echo "$UPTIME_RAW" | awk -F'up ' '{print $2}' | awk -F',' '{print $1}' | xargs)

    # --- Extraire load average ---
    LOAD_AVG=$(echo "$UPTIME_RAW" | awk -F'load average:' '{print $2}' | xargs)

    log_info "[$hote] CPU: ${CPU_PERCENT}% | RAM: ${RAM_PERCENT}% | Disk: ${DISK_PERCENT}% | Up: ${UPTIME_CLEAN} | Load: ${LOAD_AVG}"
}

check_sante() {
    local hote="$1"
    local statut_global="OK"
    local ligne_separation="-----------------------------------------"
    
    # Mode interactif
    if ! confirmer_interactif "$hote" "le bilan de sante"; then
        return 0
    fi    

    # Collecter les métriques d'abord (remplit CPU_PERCENT, RAM_PERCENT, etc.)
    collecter_metriques "$hote"
    if [ $? -ne 0 ]; then
        log_erreur "Impossible de faire le bilan — machine $hote inaccessible"
        return 1
    fi

    # Mode dry-run
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Ferait bilan de sante pour $hote"
        return 0
    fi

    # Vérifier les services critiques via SSH
    local statut_sshd statut_ufw

    if [ "$hote" = "localhost" ] || [ "$hote" = "127.0.0.1" ] || [ "$hote" = "$(hostname)" ]; then
        statut_sshd=$(systemctl is-active ssh 2>/dev/null || echo inactive)
        statut_ufw=$(systemctl is-active ufw 2>/dev/null || echo inactive)
    else
        statut_sshd=$(ssh -o ConnectTimeout="$SSH_TIMEOUT" \
                          -o BatchMode=yes \
                          "${SSH_USER}@${hote}" \
                          "systemctl is-active ssh 2>/dev/null || echo inactive" \
                          2>/dev/null)

        statut_ufw=$(ssh -o ConnectTimeout="$SSH_TIMEOUT" \
                         -o BatchMode=yes \
                         "${SSH_USER}@${hote}" \
                         "systemctl is-active ufw 2>/dev/null || echo inactive" \
                         2>/dev/null)
    fi

    # Évaluer chaque métrique — comparer avec le seuil
    local verdict_cpu verdict_ram verdict_disk verdict_sshd verdict_ufw

    # CPU
    if [ "${CPU_PERCENT:-0}" -gt "$SEUIL_ALERTE" ]; then
        verdict_cpu="CRITIQUE"
        statut_global="CRITIQUE"
    else
        verdict_cpu="OK"
    fi

    # RAM
    if [ "${RAM_PERCENT:-0}" -gt "$SEUIL_ALERTE" ]; then
        verdict_ram="CRITIQUE"
        statut_global="CRITIQUE"
    else
        verdict_ram="OK"
    fi

    # Disque
    if [ "${DISK_PERCENT:-0}" -gt "$SEUIL_ALERTE" ]; then
        verdict_disk="CRITIQUE"
        statut_global="CRITIQUE"
    else
        verdict_disk="OK"
    fi

    # Service sshd
    if [ "$statut_sshd" = "active" ]; then
        verdict_sshd="actif"
    else
        verdict_sshd="INACTIF"
        [ "$statut_global" != "CRITIQUE" ] && statut_global="ATTENTION"
    fi

    # Service ufw
    if [ "$statut_ufw" = "active" ]; then
        verdict_ufw="actif"
    else
        verdict_ufw="INACTIF"
        [ "$statut_global" != "CRITIQUE" ] && statut_global="ATTENTION"
    fi

    # Choisir la couleur du statut global
    local couleur_statut
    case "$statut_global" in
        "OK")       couleur_statut="$VERT"   ;;
        "ATTENTION") couleur_statut="$JAUNE" ;;
        "CRITIQUE") couleur_statut="$ROUGE"  ;;
    esac

    # Afficher le bilan formaté
    echo ""
    echo -e "${BLEU}${ligne_separation}${RESET}"
    echo -e "${BLEU}---- BILAN DE SANTE : ${hote} ----${RESET}"
    echo -e "${BLEU}${ligne_separation}${RESET}"
    echo -e "  CPU    (${CPU_PERCENT}%)   : $(coloriser_verdict "$verdict_cpu")"
    echo -e "  RAM    (${RAM_PERCENT}%)   : $(coloriser_verdict "$verdict_ram")"
    echo -e "  Disque (${DISK_PERCENT}%)  : $(coloriser_verdict "$verdict_disk")"
    echo -e "  Uptime              : ${UPTIME_CLEAN}"
    echo -e "  Service ssh        : $(coloriser_verdict "$verdict_sshd")"
    echo -e "  Service ufw         : $(coloriser_verdict "$verdict_ufw")"
    echo -e "${BLEU}${ligne_separation}${RESET}"
    echo -e "  STATUT GLOBAL : ${couleur_statut}${statut_global}${RESET}"
    echo -e "${BLEU}${ligne_separation}${RESET}"
    echo ""

    # Logger le résultat global
    log_info "Bilan $hote — CPU:${CPU_PERCENT}% RAM:${RAM_PERCENT}% Disk:${DISK_PERCENT}% sshd:${statut_sshd} ufw:${statut_ufw} => ${statut_global}"

    return 0
}

coloriser_verdict() {
    local verdict="$1"
    case "$verdict" in
        "OK"|"actif")
            echo -e "${VERT}${verdict}${RESET}" ;;
        "ATTENTION")
            echo -e "${JAUNE}${verdict}${RESET}" ;;
        "CRITIQUE"|"INACTIF")
            echo -e "${ROUGE}${verdict}${RESET}" ;;
        *)
            echo -e "${verdict}" ;;
    esac
}

verifier_seuils() {
    local hote="$1"
    local seuil="${2:-$SEUIL_ALERTE}"
    local alertes_declenchees=0

    # Collecter les métriques si pas encore fait
    if [ -z "$CPU_PERCENT" ]; then
        collecter_metriques "$hote"
        if [ $? -ne 0 ]; then
            log_erreur "Verification impossible — machine $hote inaccessible"
            return 1
        fi
    fi
    
    # Mode interactif
    if ! confirmer_interactif "$hote" "la verification des seuils"; then
        return 0
    fi

    # Vérifier CPU
    if [ "${CPU_PERCENT:-0}" -gt "$seuil" ]; then
        afficher_alerte_console "CPU" "$CPU_PERCENT" "$seuil" "$hote"
        log_erreur "ALERTE CPU — $hote : ${CPU_PERCENT}% depasse le seuil de ${seuil}%"
        envoyer_notification "CPU ${CPU_PERCENT}% sur $hote depasse le     seuil de ${seuil}%" "ALERTE"
        alertes_declenchees=1
    fi

    # Vérifier RAM
    if [ "${RAM_PERCENT:-0}" -gt "$seuil" ]; then
        afficher_alerte_console "RAM" "$RAM_PERCENT" "$seuil" "$hote"
        log_erreur "ALERTE RAM — $hote : ${RAM_PERCENT}% depasse le seuil de ${seuil}%"
        envoyer_notification "RAM ${RAM_PERCENT}% sur $hote depasse le seuil de ${seuil}%" "ALERTE"
        alertes_declenchees=1
    fi

    # Vérifier Disque
    if [ "${DISK_PERCENT:-0}" -gt "$seuil" ]; then
        afficher_alerte_console "DISQUE" "$DISK_PERCENT" "$seuil" "$hote"
        log_erreur "ALERTE DISQUE — $hote : ${DISK_PERCENT}% depasse le seuil de ${seuil}%"
        envoyer_notification "Disque ${DISK_PERCENT}% sur $hote depasse le seuil de ${seuil}%" "ALERTE"       
        alertes_declenchees=1
    fi

    # Résumé final
    if [ "$alertes_declenchees" -eq 0 ]; then
        log_info "[$hote] Verification seuil ${seuil}% — tout dans les limites normales"
    fi

    return "$alertes_declenchees"
}

afficher_alerte_console() {
    local metrique="$1"
    local valeur="$2"
    local seuil="$3"
    local hote="$4"

    echo ""
    echo -e "${ROUGE}---- ALERTE ${metrique} : ${hote} ----${RESET}"
    echo -e "${ROUGE}  Valeur actuelle : ${valeur}%${RESET}"
    echo -e "${ROUGE}  Seuil configure : ${seuil}%${RESET}"
    echo -e "${ROUGE}  Depassement     : +$(( valeur - seuil ))%${RESET}"
    echo -e "${ROUGE}-------------------------------------${RESET}"
    echo ""
}

generer_csv() {
    local hote="$1"
    local statut="${2:-OK}"
    local fichier_csv="${REPORT_DIR}/rapport_sysremote.csv"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Valider le statut fourni
    case "$statut" in
        "OK"|"ALERTE"|"CRITIQUE") ;;
        *)
            log_erreur "Statut invalide : '$statut'. Valeurs acceptees : OK, ALERTE, CRITIQUE"
            return 1
            ;;
    esac
    
    # Mode interactif
    if ! confirmer_interactif "$hote" "la generation du rapport CSV"; then
        return 0
    fi

    # Mode dry-run
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Genererait CSV pour $hote avec statut $statut"
        return 0
    fi
    # Créer l'en-tête si le fichier n'existe pas encore
    if [ ! -f "$fichier_csv" ]; then
        echo "Horodatage,Machine,CPU%,RAM%,Disque%,Uptime,Load Average,Statut" \
            > "$fichier_csv"
        log_info "Rapport CSV cree : $fichier_csv"
    fi

    # Ajouter un séparateur de session si c'est la première machine  de cette exécution du script
    if [ "${PREMIERE_MACHINE_CSV:-true}" = "true" ]; then
        echo "# ======== SESSION ${timestamp} ========" >> "$fichier_csv"
        PREMIERE_MACHINE_CSV=false
    fi

    # Vérifier que les métriques sont disponibles
    if [ -z "$CPU_PERCENT" ]; then
        collecter_metriques "$hote"
        local code_retour=$?
        if [ $code_retour -ne 0 ]; then
            log_erreur "Impossible de generer le rapport — machine $hote inaccessible"
            return 1
        fi
    fi

    # Ajouter la ligne de données
    echo "${timestamp},${hote},${CPU_PERCENT},${RAM_PERCENT},${DISK_PERCENT},${UPTIME_CLEAN},\"${LOAD_AVG}\",${statut}" \
        >> "$fichier_csv"

    log_info "Rapport CSV mis a jour — machine : $hote | statut : $statut"
    log_info "Fichier : $fichier_csv"

    return 0
}

generer_html() {
    local hote="$1"
    local statut="${2:-OK}"
    local fichier_html="${REPORT_DIR}/rapport_sysremote.html"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Valider le statut
    case "$statut" in
        "OK"|"ALERTE"|"CRITIQUE") ;;
        *)
            log_erreur "Statut invalide : '$statut'. Valeurs acceptees : OK, ALERTE, CRITIQUE"
            return 1
            ;;
    esac
    
    # Mode interactif
    if ! confirmer_interactif "$hote" "la generation du rapport HTML"; then
        return 0
    fi 
    
    # Mode dry-run
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Genererait HTML pour $hote avec statut $statut"
        return 0
    fi   

    # Créer le fichier HTML avec en-tête si nouveau
    if [ "${PREMIERE_MACHINE_HTML:-true}" = "true" ]; then
        PREMIERE_MACHINE_HTML=false
        cat > "$fichier_html" << 'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Rapport Sysremote</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }

        body {
            font-family: 'Courier New', Courier, monospace;
            background-color: #0a0a0a;
            color: #cccccc;
            padding: 24px;
            font-size: 13px;
            transition: background-color 0.3s, color 0.3s;
        }
        h1 {
            color: #ffffff;
            font-size: 16px;
            font-weight: bold;
            text-transform: uppercase;
            letter-spacing: 2px;
            padding-bottom: 8px;
            border-bottom: 1px solid #333333;
            margin-bottom: 8px;
        }
        .meta {
            color: #555555;
            font-size: 11px;
            margin-bottom: 20px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            border: 1px solid #2a2a2a;
        }
        thead tr {
            background-color: #1a1a1a;
            border-bottom: 2px solid #333333;
        }
        th {
            color: #aaaaaa;
            font-weight: bold;
            text-transform: uppercase;
            font-size: 11px;
            letter-spacing: 1px;
            padding: 10px 12px;
            text-align: left;
            border-right: 1px solid #2a2a2a;
        }
        td {
            padding: 8px 12px;
            border-right: 1px solid #1e1e1e;
            border-bottom: 1px solid #1e1e1e;
        }
        tr.session td {
            background-color: #111111;
            color: #444444;
            font-size: 11px;
            padding: 4px 12px;
            font-style: italic;
            border-bottom: 1px solid #1a1a1a;
        }
        tr.ok      td { background-color: #0a0f0a; }
        tr.alerte  td { background-color: #0f0f00; }
        tr.critique td { background-color: #0f0500; }
        tr:hover td { filter: brightness(1.4); }
        .badge-ok       { color: #00cc44; font-weight: bold; }
        .badge-alerte   { color: #ffcc00; font-weight: bold; }
        .badge-critique { color: #ff3333; font-weight: bold; }

        /* ---- THEME CLAIR ---- */
        body.light { background-color: #f0f0f0; color: #1a1a1a; }
        body.light h1 { color: #111111; border-bottom-color: #cccccc; }
        body.light .meta { color: #888888; }
        body.light table { border-color: #cccccc; }
        body.light thead tr { background-color: #e0e0e0; border-bottom-color: #bbbbbb; }
        body.light th { color: #333333; border-right-color: #cccccc; }
        body.light td { border-right-color: #dddddd; border-bottom-color: #dddddd; }
        body.light tr.session td { background-color: #e8e8e8; color: #999999; }
        body.light tr.ok      td { background-color: #ffffff; }
        body.light tr.alerte  td { background-color: #fffce8; }
        body.light tr.critique td { background-color: #fff8f5; }        
        body.light .badge-ok { color: #00aa33; font-weight: bold; }
        bodyi.light .badge-alerte   { color: #886600; font-weight: bold; }
        body.light .badge-critique { color: #cc2200; font-weight: bold; }

        /* ---- BOUTON THEME ---- */
        .toggle-btn {
            position: fixed;
            top: 20px;
            right: 20px;
            background: transparent;
            color: #555555;
            border: 1px solid #444444;
            padding: 4px 10px;
            font-family: 'Courier New', monospace;
            font-size: 11px;
            cursor: pointer;
            letter-spacing: 1px;
            transition: color 0.2s, border-color 0.2s;
        }
        .toggle-btn:hover {
            color: #aaaaaa;
            border-color: #777777;
        }
        body.light .toggle-btn {
            color: #666666;
            border-color: #aaaaaa;
        }
        body.light .toggle-btn:hover {
            color: #222222;
            border-color: #444444;
        }
    </style>
</head>
<body>
    <button class="toggle-btn" onclick="this.textContent=document.body.classList.toggle('light')?'[ LIGHT ]':'[ DARK ]'">
        [ DARK ]
    </button>
    <h1>Rapport Sysremote</h1>
    PLACEHOLDER_META
    <table>    
        <thead>
            <tr>
                <th>Horodatage</th>
                <th>Machine</th>
                <th>CPU%</th>
                <th>RAM%</th>
                <th>Disque%</th>
                <th>Uptime</th>
                <th>Load Average</th>
                <th>Statut</th>
            </tr>
        </thead>
        <tbody>
EOF

        sed -i "s|PLACEHOLDER_META|<p class=\"meta\">Genere le : ${timestamp} - Hote : $(hostname)</p>|" "$fichier_html"
        echo "            <tr class=\"session\"><td colspan=\"8\">Session : ${timestamp}</td></tr>" \
            >> "$fichier_html"
        log_info "Rapport HTML cree : $fichier_html"        
    fi

    # Vérifier que les métriques sont disponibles
    if [ -z "$CPU_PERCENT" ]; then
        collecter_metriques "$hote"
        local code_retour=$?
        if [ $code_retour -ne 0 ]; then
            log_erreur "Impossible de generer le rapport HTML — machine $hote inaccessible"
            return 1
        fi
    fi

    # Déterminer la classe CSS selon le statut
    local classe_css badge_css
    case "$statut" in
        "OK")       classe_css="ok";       badge_css="badge-ok"      ;;
        "ALERTE")   classe_css="alerte";   badge_css="badge-alerte"  ;;
        "CRITIQUE") classe_css="critique"; badge_css="badge-critique" ;;
    esac

    # Ajouter la ligne de données
    cat >> "$fichier_html" << EOF
            <tr class="${classe_css}">
                <td>${timestamp}</td>
                <td>${hote}</td>
                <td>${CPU_PERCENT}%</td>
                <td>${RAM_PERCENT}%</td>
                <td>${DISK_PERCENT}%</td>
                <td>${UPTIME_CLEAN}</td>
                <td>${LOAD_AVG}</td>
                <td class="${badge_css}">${statut}</td>
            </tr>
EOF

    log_info "Rapport HTML mis a jour — machine : $hote | statut : $statut"
    log_info "Fichier : $fichier_html"

    return 0
}

fermer_html() {
    local fichier_html="${REPORT_DIR}/rapport_sysremote.html"

    if [ -f "$fichier_html" ]; then
        cat >> "$fichier_html" << 'EOF'
        </tbody>
    </table>
</body>
</html>
EOF
    fi
}

envoyer_notification() {
    local message="$1"
    local niveau="${2:-INFO}"
    local envoye=false

    # Vérifier qu'il y a quelque chose à envoyer
    if [ -z "$message" ]; then
        log_erreur "envoyer_notification : message vide"
        return 1
    fi

    # Mode dry-run : simuler sans envoyer
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Enverrait notification : $message"
        return 0
    fi

    # Notification Discord via webhook
    if [ "$NOTIF_DISCORD" = true ]; then
        if [ -z "$DISCORD_WEBHOOK" ]; then
            log_erreur "DISCORD_WEBHOOK non configure"
        else
            notifier_discord "$message" "$niveau"
            envoye=true
        fi
    fi

    # Notification Email
    if [ "$NOTIF_EMAIL" = true ]; then
        if [ -z "$EMAIL_DESTINATAIRE" ]; then
            log_erreur "EMAIL_DESTINATAIRE non configure"
        else
            notifier_email "$message" "$niveau"
            envoye=true
        fi
    fi

    # Aucun canal configuré
    if [ "$envoye" = false ]; then
        log_info "Notification non envoyee — aucun canal configure (Discord/Email)"
    fi

    return 0
}

notifier_discord() {
    local message="$1"
    local niveau="${2:-INFO}"
    local couleur_discord

    # Discord utilise des couleurs numériques (décimal)
    case "$niveau" in
        "OK")       couleur_discord=65280   ;;
        "ALERTE")   couleur_discord=16776960 ;;
        "CRITIQUE") couleur_discord=16711680 ;;
        *)          couleur_discord=8421504  ;;
    esac

    # Construire le payload JSON
    local payload
    payload=$(cat << EOF
{
    "embeds": [{
        "title": "Sysremote — ${niveau}",
        "description": "${message}",
        "color": ${couleur_discord},
        "footer": {"text": "Hote : $(hostname) | $(date '+%Y-%m-%d %H:%M:%S')"}
    }]
}
EOF
)

    # Envoyer via curl
    local code_http
    code_http=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$payload" \
        "$DISCORD_WEBHOOK" 2>/dev/null)

    if [ "$code_http" = "204" ]; then
        log_info "Notification Discord envoyee — niveau : $niveau"
    else
        log_erreur "Echec notification Discord — code HTTP : $code_http"
    fi
}

notifier_email() {
    local message="$1"
    local niveau="${2:-INFO}"
    local sujet="[Sysremote] ${niveau} — $(hostname) — $(date '+%Y-%m-%d %H:%M')"

    # Vérifier que la commande mail est disponible
    if ! command -v mail &>/dev/null; then
        log_erreur "Commande 'mail' non disponible — installer mailutils"
        return 1
    fi

    # Envoyer l'email
    echo "$message" | mail -s "$sujet" "$EMAIL_DESTINATAIRE"
    local code_retour=$?

    if [ $code_retour -eq 0 ]; then
        log_info "Email envoye a $EMAIL_DESTINATAIRE — sujet : $sujet"
    else
        log_erreur "Echec envoi email — code : $code_retour"
    fi
}

confirmer_interactif() {
    local hote="$1"
    local action="${2:-action}"

    if [ "$MODE_INTERACTIF" != true ]; then
        return 0
    fi

    echo -ne "${JAUNE}  Executer ${action} sur ${hote} ? (o/n) : ${RESET}"
    read -r reponse

    if [ "$reponse" = "o" ] || [ "$reponse" = "O" ]; then
        return 0
    else
        log_info "Machine $hote ignoree par l'utilisateur"
        return 1
    fi
}

# FONCTION DE DÉMONSTRATION

demo() {
    log_info "=== DEBUT DEMONSTRATION SYSREMOTE - MONITORING ==="

    # 1. Collecte et vérification seuil normal
    log_info "--- Collecte metriques et seuil 80% ---"
    collecter_metriques "localhost"
    verifier_seuils "localhost" 80

    if [ $? -eq 0 ]; then
        STATUT_MACHINE="OK"
    else
        STATUT_MACHINE="ALERTE"
    fi

    # 2. Génération des rapports
    log_info "---  Generation rapports CSV/HTML ---"
    generer_csv "localhost" "$STATUT_MACHINE"
    if [ "$GENERER_HTML" = "true" ]; then
        generer_html "localhost" "$STATUT_MACHINE"
    fi

    # 3. Bilan de santé
    log_info "--- Bilan de sante ---"
    check_sante "localhost"

    # 4. Mode interactif
    log_info "--- Mode interactif ---"
    MODE_INTERACTIF=true
    check_sante "localhost"
    MODE_INTERACTIF=false

    # 5. Alertes et notifications (seuil 5%)
    log_info "---  Alertes et notifications ---"
    CPU_PERCENT=""
    verifier_seuils "localhost" 5

    # 6. Affichage final
    echo ""
    echo -e "  CSV  → ${REPORT_DIR}/rapport_sysremote.csv"
    echo -e "  HTML → ${BLEU}\033[4mfile://${REPORT_DIR}/rapport_sysremote.html${RESET}"
    echo ""
    xdg-open "${REPORT_DIR}/rapport_sysremote.html" 2>/dev/null || true

    log_info "=== FIN DEMONSTRATION ==="
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    demo
fi
