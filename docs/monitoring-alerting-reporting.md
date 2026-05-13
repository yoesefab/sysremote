# Module de Monitoring, Alertes et Rapports

**Module :** `monitoring.sh`  
**Projet :** sysremote — Gestion, Surveillance et Sécurité des Machines Distantes  
**Branche :** `feature/monitoring-alerting-reporting`

---

## Rôle de ce module

Ce module constitue la couche d'observabilité de sysremote. Il collecte les métriques système des machines distantes via SSH, évalue leur état par rapport à des seuils configurables, génère des rapports lisibles et envoie des alertes automatiques par Discord et email.

Il s'appuie sur le socle CLI du Lot 1 (connexion SSH, inventaire, configuration).

---

## Fonctionnalités implémentées

- Collecte distante des métriques : CPU, RAM, disque, uptime, load average
- Normalisation des données brutes pour exploitation dans les rapports
- Mode `-check` : bilan de santé complet par machine avec verdict par métrique
- Option `--alert <seuil>` : déclenchement d'alertes si un seuil est dépassé
- Rendu console coloré des alertes (rouge / jaune / vert)
- Génération de rapport CSV avec séparateurs de session
- Génération de rapport HTML avec thème sombre/clair
- Notifications Discord via webhook
- Notifications email via Gmail (msmtp)
- Mode interactif `-i` : confirmation avant exécution sur chaque machine
- Mode `--dry-run` : simulation complète sans exécution réelle
- Journalisation horodatée dans `history.log` au format exigé

---

## Fichiers de ce lot

| Fichier | Rôle |
|---|---|
| `monitoring.sh` | Module principal — toutes les fonctions de monitoring |
| `sysremote.conf.example` | Modèle de configuration à copier et remplir |
| `.gitignore` | ---- |
| `README.md` | ---- |

> `sysremote.conf` et `.msmtprc` ne sont **pas** dans le dépôt (fichiers locaux sensibles).

---

## Prérequis

### Dépendances système

Installer les paquets nécessaires :

```bash
sudo apt-get update
sudo apt-get install -y openssh-client openssh-server curl mailutils msmtp msmtp-mta bc
```

| Outil | Rôle |
|---|---|
| `openssh-client` | Connexion SSH vers les machines distantes |
| `openssh-server` | Accepter les connexions SSH entrantes (nécessaire pour les tests locaux) |
| `curl` | Envoi des notifications Discord via webhook HTTP |
| `mailutils` | Commande `mail` pour l'envoi d'emails |
| `msmtp` | Client SMTP léger pour relayer les emails via Gmail |
| `bc` | Calculatrice pour les opérations sur nombres décimaux |

### Authentification SSH sans mot de passe

Le module se connecte aux machines distantes sans saisie de mot de passe. Configurer les clés SSH une seule fois :

```bash
# Générer une paire de clés RSA
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# Copier la clé publique sur chaque machine cible
ssh-copy-id utilisateur@adresse_machine
```

---

## Configuration

### 1. Créer sysremote.conf

```bash
cp sysremote.conf.example sysremote.conf
vim sysremote.conf
```

Remplir les valeurs selon votre environnement.

### 2. Configurer les notifications Discord

1. Créer un serveur Discord dédié aux alertes
2. Dans le canal voulu : Paramètres du canal → Intégrations → Webhooks → Créer un webhook
3. Copier l'URL du webhook
4. La coller dans `sysremote.conf` à la variable `DISCORD_WEBHOOK`

### 3. Configurer les notifications email (Gmail)

Créer un mot de passe d'application Gmail :

```
Compte Google → Sécurité → Mots de passe des applications
→ Nom : Sysremote → Créer → Copier le code de 16 caractères
```

Créer le fichier de configuration msmtp :

```bash
vim ~/.msmtprc
```

```
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           votre.email@gmail.com
user           votre.email@gmail.com
password       MOT_DE_PASSE_APPLICATION_16_CARACTERES

account default : gmail
```

```bash
# Sécuriser le fichier (lecture uniquement par le propriétaire)
chmod 600 ~/.msmtprc
```

---

## Utilisation en mode démonstration

Exécuter le module directement pour tester toutes les fonctionnalités :

```bash
chmod +x monitoring.sh
./monitoring.sh
```

Le script exécute automatiquement :
1. Collecte des métriques sur `localhost`
2. Vérification du seuil à 80% (aucune alerte attendue)
3. Génération du rapport CSV et HTML
4. Bilan de santé complet
5. Test du mode interactif (confirmation avant exécution)
6. Test des alertes avec seuil à 5% → notifications Discord + email

---

## Intégration avec le script principal

Ce module est conçu pour être sourcé par le script principal sysremote :

```bash
source monitoring.sh
```

Lors du chargement, aucune fonction ne s'exécute automatiquement.  
Le script principal appelle les fonctions selon les options passées par l'utilisateur.

### Variables à activer depuis le script principal

Le script principal doit exposer les variables suivantes selon les options reçues :

| Variable | Option | Valeur |
|---|---|---|
| `MODE_INTERACTIF` | `-i` | `true` |
| `DRY_RUN` | `--dry-run` | `true` |
| `GENERER_HTML` | `-o html` | `true` |
| `SEUIL_ALERTE` | `--alert N` | valeur numérique |

Ces variables sont déjà déclarées dans `monitoring.sh` avec leurs valeurs par défaut.  
Le script principal les surcharge selon les arguments reçus.

### Fonctions exposées

| Fonction | Description |
|---|---|
| `collecter_metriques <hote>` | Collecte CPU, RAM, disque, uptime via SSH |
| `check_sante <hote>` | Bilan de santé complet avec verdict par métrique |
| `verifier_seuils <hote> [seuil]` | Vérifie si les métriques dépassent le seuil |
| `generer_csv <hote> <statut>` | Ajoute une ligne au rapport CSV |
| `generer_html <hote> <statut>` | Ajoute une ligne au rapport HTML |
| `envoyer_notification <message> <niveau>` | Envoie via Discord et/ou email |
| `fermer_html` | Ferme proprement le fichier HTML (appelé automatiquement via `trap EXIT`) |

---

## Rapports générés

### CSV

Chemin : `$RAPPORT_DIR/rapport_sysremote.csv`

Format :
```
Horodatage,Machine,CPU%,RAM%,Disque%,Uptime,Load Average,Statut
# ======== SESSION 2026-05-12 00:19:00 ========
2026-05-12 00:19:00,localhost,4,31,61,11:19,"1.21 1.10 1.02",OK
```

- Les sessions sont séparées par une ligne commentée
- Le fichier s'accumule entre les exécutions

### HTML

Chemin : `$RAPPORT_DIR/rapport_sysremote.html`

- Tableau interactif avec thème sombre par défaut
- Bouton `[ DARK ] / [ LIGHT ]` pour basculer les thèmes
- Lignes colorées : vert (OK), jaune (ATTENTION), rouge (CRITIQUE)
- Reconstruit à chaque exécution (snapshot de la session courante)
- Compatible avec tous les navigateurs modernes

---

## Journalisation

Tous les événements sont écrits dans :

```
$LOG_DIR/history.log
```

Format conforme au cahier des charges :

```
yyyy-mm-dd-hh-mm-ss : utilisateur : INFOS : message
yyyy-mm-dd-hh-mm-ss : utilisateur : ERROR : message d'erreur
```

Le fichier s'accumule entre les exécutions et n'est jamais effacé automatiquement.

---

## Mode dry-run

Activer la simulation sans exécution réelle :

```bash
# Dans sysremote.conf ou via le script principal avec --dry-run
DRY_RUN=true
```

Toutes les actions affichent `[DRY-RUN] Ferait...` sans effectuer de connexion SSH, sans écrire de fichier, sans envoyer de notification.

---

## Mode interactif

Activer la confirmation machine par machine :

```bash
# Via le script principal avec -i
MODE_INTERACTIF=true
```

Avant chaque action sur une machine :

```
  Executer le bilan de sante sur 192.168.1.10 ? (o/n) :
```

`o` → exécution  
`n` → machine ignorée pour cette action, passage à la suivante

---

## Notes pour l'intégration

- Les variables `DRY_RUN`, `MODE_INTERACTIF`, `SEUIL_ALERTE`, `GENERER_HTML` doivent être définies **avant** que les fonctions soient appelées
- `fermer_html` est enregistrée via `trap EXIT` — elle s'exécute automatiquement à la fin du script, ne pas l'appeler manuellement
- La variable `PREMIERE_MACHINE_HTML` se réinitialise automatiquement à chaque exécution — aucune intervention nécessaire
- Les fonctions `notifier_discord` et `notifier_email` ne sont jamais appelées directement — passer toujours par `envoyer_notification`
- En mode dry-run, aucune connexion SSH n'est établie — les métriques ne sont pas collectées

---

## Structure des fichiers locaux (non versionnés)

```
~/sysremote/
├── sysremote.conf          # configuration locale (à créer depuis .example)
├── logs/
│   └── history.log         # journal complet des événements
└── rapports/
    ├── rapport_sysremote.csv   # rapport CSV cumulatif
    └── rapport_sysremote.html  # rapport HTML de la dernière session
```

```
~/.msmtprc                  # configuration email (à créer manuellement)
```
