# Tests manuels et preuves d'execution

Ces tests peuvent etre executes sans infrastructure distante grace au mode
`-n` dry-run et aux benchmarks locaux.

## Aide et syntaxe

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -h
```

Resultat attendu: aide complete avec usage, options, commandes, exemples et
codes de retour.

## Validation d'inventaire

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -i ./inventory.example validate-hosts
```

Resultat attendu: chaque cible valide est affichee avec `OK`.

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -m 'srv-app-01;id' validate-hosts
echo $?
```

Resultat attendu: rejet de la cible et code `4`.

## Gestion des erreurs

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -Z
echo $?
```

Resultat attendu: option invalide, aide complete, code `100`.

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs
echo $?
```

Resultat attendu: parametre obligatoire manquant, aide complete, code `101`.

## Logging

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -m 192.0.2.10 validate-hosts
tail /tmp/sysremote-logs/history.log
```

Resultat attendu: les sorties terminal sont aussi journalisees au format:

```text
yyyy-mm-dd-hh-mm-ss : username : INFOS : message
yyyy-mm-dd-hh-mm-ss : username : ERROR : message
```

## Modes d'execution

Normal:

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -n -m 192.0.2.10,192.0.2.11 sessions who
```

Fork avec processus enfants, `&` et `wait`:

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -f -n -m 192.0.2.10,192.0.2.11 sessions who
```

Thread/worker pool avec `xargs -P`:

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -t -j 2 -n -m 192.0.2.10,192.0.2.11 sessions who
```

Subshell avec `( ... )`:

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -s -m 192.0.2.10 validate-hosts
```

## Charges de travail

Legere:

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs benchmark light
```

Moyenne:

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs benchmark medium
```

Lourde:

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs benchmark heavy
```

Les lignes `elapsed_ms` montrent la comparaison. Sur une machine standard,
`fork` et `thread` doivent etre plus rapides que `normal` pour ces charges
composees de taches independantes.

## Archivage et manipulation de fichiers

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs archive-logs ./archives
tar -tzf ./archives/sysremote-logs-*.tar.gz
```

Resultat attendu: creation, copie, modification de manifeste, deplacement,
suppression temporaire et compression `.tar.gz`.

## Controle root

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -m 192.0.2.10 create-user alice
echo $?
```

Resultat attendu sans `sudo`: refus avec code `10`.

```bash
sudo ./bin/sysremote.sh -r
```

Resultat attendu avec `sudo`: restauration de `/etc/sysremote/sysremote.conf`
et du log par defaut.
