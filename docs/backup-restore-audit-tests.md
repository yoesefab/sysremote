#  Guide de Test — sysremote
## Module Backup / Restore / Security Audit


---

## Prérequis

Avant de commencer, assure-toi d'avoir :
- Une VM Linux 
- Un accès terminal
- Les droits sudo

---

## Étape 1 — Récupérer les scripts

Crée la structure de dossiers sur ta VM :

```bash
mkdir -p ~/sysremote/lib
cd ~/sysremote
```

Tu dois avoir ces fichiers :

```
sysremote/
├── sysremote.sh          ← script principal
└── lib/
    ├── common.sh
    ├── backup.sh
    ├── restore.sh
    ├── audit.sh
    ├── maintain.sh
    └── schedule.sh
```

---

## Étape 2 — Installation

```bash
# Rendre le script exécutable
chmod +x ~/sysremote/sysremote.sh

# Installer les dépendances
sudo apt-get update
sudo apt-get install -y rsync tar openssl

# Créer les dossiers système
sudo mkdir -p /var/log/sysremote
sudo mkdir -p /var/backups/sysremote
sudo chmod 755 /var/log/sysremote
sudo chmod 755 /var/backups/sysremote
```

---

## Étape 3 — Préparer les données de test

```bash
# Créer la source de test
mkdir -p ~/test_source/config ~/test_source/data

echo "port=8080"   > ~/test_source/config/app.conf
echo "user=admin"  > ~/test_source/config/db.conf
echo "hello world" > ~/test_source/data/fichier.txt

# Créer 20 fichiers pour tester l'incrémental
for i in $(seq 1 20); do
  echo "fichier numero $i" > ~/test_source/data/file_$i.txt
done
```

---

## TEST 1 — Aide et version 

```bash
cd ~/sysremote
./sysremote.sh -h
./sysremote.sh --version
```

**Résultat attendu :** affichage coloré de la documentation et `sysremote v1.0.0`

---

## TEST 2 — Sauvegarde simple 

```bash
./sysremote.sh backup -S ~/test_source -D ~/test_backup --tag snap1
```

**Vérifier :**
```bash
ls ~/test_backup/snap1/
```
**Résultat attendu :** les fichiers de `test_source` sont copiés dans `snap1`

---

## TEST 3 — Sauvegarde incrémentale 

```bash
# Modifier seulement 2 fichiers
echo "ligne modifiee" >> ~/test_source/config/app.conf
echo "nouveau contenu" > ~/test_source/data/file_1.txt

# Deuxième sauvegarde
./sysremote.sh backup -S ~/test_source -D ~/test_backup --tag snap2

# Comparer les tailles
du -sh ~/test_backup/snap1
du -sh ~/test_backup/snap2
```

**Résultat attendu :** `snap2` est plus petit que `snap1` grâce aux liens durs (hard links)

---

## TEST 4 — Sauvegarde compressée 

```bash
./sysremote.sh backup -S ~/test_source -D ~/test_backup --tag snap3 --compress
```

**Vérifier :**
```bash
ls -lh ~/test_backup/*.tar.gz
```
**Résultat attendu :** fichier `snap3.tar.gz` créé

---

## TEST 5 — Sauvegarde chiffrée 

```bash
./sysremote.sh backup -S ~/test_source -D ~/test_backup --tag snap4 --compress --encrypt
```
> Quand il demande le mot de passe, tape : **test1234**

**Vérifier :**
```bash
ls -lh ~/test_backup/*.enc
```
**Résultat attendu :** fichier `snap4.tar.gz.enc` créé

---

## TEST 6 — Mode subshell (-s) 

```bash
./sysremote.sh -s backup -S ~/test_source -D ~/test_backup --tag snap-subshell --compress
```

**Résultat attendu :** message `Mode subshell : environnement isole...` puis sauvegarde OK

---

## TEST 7 — Mode fork (-f) 

```bash
./sysremote.sh -f backup -S ~/test_source -D ~/test_backup --tag snap-fork --compress
```

**Résultat attendu :** message `PID=XXXX cree.` puis `PID=XXXX termine (code=0).`

---

## TEST 8 — Mode thread (-t) 

```bash
./sysremote.sh -t backup -S ~/test_source -D ~/test_backup --tag snap-thread --compress
```

**Résultat attendu :** message `Job XXXX demarre.` puis sauvegarde OK

---

## TEST 9 — Restauration 

```bash
mkdir ~/test_restore

sudo ./sysremote.sh restore -A ~/test_backup/snap3.tar.gz -T ~/test_restore
```

**Vérifier :**
```bash
ls ~/test_restore/snap3/
```
**Résultat attendu :** les fichiers originaux sont restaurés

---

## TEST 10 — Restauration archive chiffrée 

```bash
mkdir ~/test_restore2

sudo ./sysremote.sh restore -A ~/test_backup/snap4.tar.gz.enc -T ~/test_restore2
```
> Quand il demande le mot de passe, tape : **test1234**

**Résultat attendu :** fichiers restaurés dans `test_restore2`

---

## TEST 11 — Audit permissions 

```bash
./sysremote.sh audit --perms
```

**Résultat attendu :**
- `/etc/passwd` → `OK` (644)
- `/etc/shadow` → `OK` (640)
- Rapport lisible avec couleurs

---

## TEST 12 — Audit connexions 

```bash
sudo ./sysremote.sh audit --logins
```

**Résultat attendu :** liste des dernières connexions et tentatives échouées SSH

---

## TEST 13 — Audit ports 

```bash
./sysremote.sh audit --ports
```

**Résultat attendu :** liste des ports ouverts, signalement des ports inhabituels

---

## TEST 14 — Audit complet 

```bash
sudo ./sysremote.sh audit --all
```

**Résultat attendu :** rapport complet avec les 3 audits

---

## TEST 15 — Planification cron 

```bash
# Ajouter une tâche
sudo ./sysremote.sh schedule --add "0 2 * * *" "./sysremote.sh backup -S /etc --compress"

# Voir la tâche
./sysremote.sh schedule --list

# Voir le fichier créé
cat /etc/cron.d/sysremote

# Supprimer
sudo ./sysremote.sh schedule --remove
```

**Résultat attendu :** tâche ajoutée dans `/etc/cron.d/sysremote`

---

## TEST 16 — Journaux 

```bash
./sysremote.sh logs
cat /var/log/sysremote/history.log
```

**Résultat attendu :** toutes les opérations précédentes enregistrées au format :
```
2026-05-03-10-00-00 : soukaina : INFOS : === Debut sauvegarde ===
```

---

## TEST 17 — Gestion des erreurs 

```bash
# Code 100 : option inconnue
./sysremote.sh --foobar

# Code 101 : paramètre manquant
./sysremote.sh backup

# Code 102 : root requis
./sysremote.sh restore -A ~/test_backup/snap3.tar.gz

# Code 103 : source inexistante
./sysremote.sh backup -S /dossier_qui_nexiste_pas -D ~/test_backup

# Code 107 : archive inexistante
sudo ./sysremote.sh restore -A /fichier_inexistant.tar.gz
```

**Résultat attendu :** message `[ERROR]` en rouge avec le bon code + affichage de l'aide

---

## Résumé des tests

| # | Test | Commande clé | Root ? |
|---|------|-------------|--------|
| 1 | Aide | `./sysremote.sh -h` | Non |
| 2 | Backup simple | `backup -S ... --tag snap1` | Non |
| 3 | Backup incrémental | `backup -S ... --tag snap2` | Non |
| 4 | Backup compressé | `backup ... --compress` | Non |
| 5 | Backup chiffré | `backup ... --encrypt` | Non |
| 6 | Mode subshell | `-s backup ...` | Non |
| 7 | Mode fork | `-f backup ...` | Non |
| 8 | Mode thread | `-t backup ...` | Non |
| 9 | Restauration | `restore -A snap3.tar.gz` | **Oui** |
| 10 | Restore chiffré | `restore -A snap4.tar.gz.enc` | **Oui** |
| 11 | Audit permissions | `audit --perms` | Non |
| 12 | Audit connexions | `audit --logins` | **Oui** |
| 13 | Audit ports | `audit --ports` | Non |
| 14 | Audit complet | `audit --all` | **Oui** |
| 15 | Cron | `schedule --add ...` | **Oui** |
| 16 | Journaux | `logs` | Non |
| 17 | Erreurs | options invalides | Mix |

---

## En cas de problème

| Erreur | Solution |
|--------|----------|
| `Permission denied` sur `/var/log` | Utiliser `-l ./logs` pour les tests non-root ou corriger le proprietaire du dossier |
| `rsync: command not found` | `sudo apt install rsync` |
| `cannot create directory` | Vérifier que le chemin n'est pas un fichier : `rm ~/test_source` puis `mkdir` |
| Pas de couleurs | Utiliser `./` et non `bash script.sh` |
| `dos2unix` sur fichier Windows | `sudo apt install dos2unix && dos2unix sysremote.sh` |

---
