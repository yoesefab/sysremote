# Utilisation rapide de sysremote

`sysremote` centralise la configuration, l'inventaire, la validation des cibles,
les logs et les modes d'execution pour l'administration distante.

## Installation locale

```bash
chmod +x ./bin/sysremote.sh
cp ./sysremote.conf.example ./sysremote.conf
```

Adapter ensuite `SSH_USER`, `REMOTE_SUDO` et `INVENTORY_FILE` dans
`sysremote.conf`.

## Inventaire

L'inventaire contient une cible par ligne:

```text
srv-app-01.example.internal
192.0.2.10
```

Les noms `user@host`, les espaces, les options commencant par `-` et les
caracteres shell sont refuses. Les cibles acceptees sont les noms DNS et IPv4.

## Options principales

```bash
./bin/sysremote.sh -h
./bin/sysremote.sh -l /tmp/sysremote-logs -c ./sysremote.conf -i ./inventory.example validate-hosts
./bin/sysremote.sh -l /tmp/sysremote-logs -U root -T 3 -m 192.0.2.10 sessions w
```

Options imposees par le sujet:

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -f -n -m 192.0.2.10,192.0.2.11 sessions who
./bin/sysremote.sh -l /tmp/sysremote-logs -t -j 2 -n -m 192.0.2.10,192.0.2.11 sessions who
./bin/sysremote.sh -l /tmp/sysremote-logs -s -m 192.0.2.10 validate-hosts
sudo ./bin/sysremote.sh -r
```

## Logging

Le chemin par defaut est `/var/log/sysremote/history.log`. Le dossier est cree
automatiquement lorsque l'utilisateur a les droits necessaires. Pour les tests
sans root:

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -m 192.0.2.10 validate-hosts
tail /tmp/sysremote-logs/history.log
```

## Flux documente: creation d'un compte distant

1. Valider l'inventaire:

   ```bash
   ./bin/sysremote.sh -l /tmp/sysremote-logs -c ./sysremote.conf validate-hosts
   ```

2. Verifier les sessions actives avant intervention:

   ```bash
   ./bin/sysremote.sh -l /tmp/sysremote-logs -c ./sysremote.conf sessions w
   ```

3. Creer le compte sur toutes les cibles:

   ```bash
   sudo ./bin/sysremote.sh -c ./sysremote.conf create-user alice
   ```

4. Ajouter le compte a un groupe:

   ```bash
   sudo ./bin/sysremote.sh -c ./sysremote.conf add-user-group alice wheel
   ```

Pour les environnements ou l'elevation est entierement controlee cote distant,
`-N` desactive uniquement le controle EUID/root local:

```bash
./bin/sysremote.sh -N -n -l /tmp/sysremote-logs -m srv-app-01.example.internal lock-user alice
```

## Archives et benchmarks

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs archive-logs ./archives
./bin/sysremote.sh -l /tmp/sysremote-logs benchmark light
./bin/sysremote.sh -l /tmp/sysremote-logs benchmark medium
./bin/sysremote.sh -l /tmp/sysremote-logs benchmark heavy
```

## Codes de retour

| Code | Signification |
| ---: | --- |
| 0 | Succes |
| 2 | Usage invalide ou commande inconnue |
| 3 | Configuration invalide |
| 4 | Cible refusee par validation |
| 10 | Privileges locaux insuffisants |
| 20 | Erreur SSH |
| 21 | Commande distante en echec |
| 30 | Aucune cible exploitable |
| 100 | Option invalide |
| 101 | Parametre obligatoire manquant |
