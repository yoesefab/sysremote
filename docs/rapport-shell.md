# Rapport - devoir shell - sysremote

## Objectif

`sysremote` repond a un besoin reel d'automatisation Linux: executer et
documenter des actions d'administration distante sur plusieurs hotes sans
repeter les commandes manuellement. Les utilisateurs vises sont les
administrateurs systeme, developpeurs DevOps, enseignants et utilisateurs Linux
qui manipulent des inventaires de machines.

## Apports

- gain de temps par execution multi-hotes;
- reduction de l'effort repetitif;
- fiabilite par validation des entrees et codes d'erreur;
- qualite d'automatisation par logs, dry-run et benchmarks.

## Architecture

Le projet contient un point d'entree `bin/sysremote.sh`, des modules Bash dans
`lib/`, une configuration exemple, un inventaire exemple et une documentation.
Le point d'entree charge les modules puis lance `main`. Les responsabilites sont
separees: `ui.sh` pour l'aide et les logs, `config.sh` pour la configuration,
`targets.sh` pour l'inventaire, `remote.sh` pour SSH et la concurrence,
`commands.sh` pour les commandes, et `cli.sh` pour le parsing et le dispatch.

## Options obligatoires

- `-h`: aide complete.
- `-f`: mode fork avec processus enfants, `&` et `wait`.
- `-t`: mode thread/worker pool avec `xargs -P`.
- `-s`: execution dans un sous-shell.
- `-l DOSSIER`: dossier de logs.
- `-r`: restauration des valeurs par defaut, reservee a root.

## Concepts Linux/Bash

Le projet utilise conditions, `case`, tests `[[ ]]`, boucles `for`, `while` et
`until`, fonctions, variables d'environnement, expressions regulieres,
manipulation de fichiers, permissions, pipes, filtres, recherche et compression.

## Logs

Le log par defaut est `/var/log/sysremote/history.log`. Un dossier peut etre
fourni avec `-l`. Les sorties standard et erreur sont envoyees au terminal et au
fichier avec le format:

```text
yyyy-mm-dd-hh-mm-ss : username : INFOS : message
yyyy-mm-dd-hh-mm-ss : username : ERROR : message
```

## Exemples

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -h
./bin/sysremote.sh -l /tmp/sysremote-logs -m 192.0.2.10 validate-hosts
./bin/sysremote.sh -l /tmp/sysremote-logs -f -n -m 192.0.2.10,192.0.2.11 sessions who
./bin/sysremote.sh -l /tmp/sysremote-logs -t -j 2 -n -m 192.0.2.10,192.0.2.11 sessions who
./bin/sysremote.sh -l /tmp/sysremote-logs -s -m 192.0.2.10 validate-hosts
./bin/sysremote.sh -l /tmp/sysremote-logs benchmark light
./bin/sysremote.sh -l /tmp/sysremote-logs archive-logs ./archives
```

## Captures d'ecran a inserer

1. Aide `-h`.
2. Fichier `history.log`.
3. Comparaison `benchmark light`.
4. Archive creee par `archive-logs`.

## Conclusion

Le projet respecte les exigences principales du devoir: script Bash, syntaxe
Linux, options obligatoires, logs, codes d'erreur, execution concurrente,
documentation et livrables.
