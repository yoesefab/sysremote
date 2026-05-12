# sysremote

`sysremote` est un mini-projet Linux/Bash pour automatiser l'administration
distante multi-hotes. Il centralise la configuration SSH, l'inventaire, la
validation des cibles, les logs, les modes d'execution concurrents et les
operations de base sur les utilisateurs/groupes.

## Besoin reel

Les administrateurs systeme, developpeurs DevOps et utilisateurs Linux doivent
souvent executer la meme verification ou la meme action sur plusieurs machines.
Le faire a la main prend du temps, augmente l'effort repetitif et rend les
erreurs plus probables. `sysremote` automatise ces actions avec:

- une syntaxe CLI standard `programme [options] commande [arguments]`;
- un inventaire valide avant execution;
- des timeouts SSH controles;
- des logs terminal + fichier;
- des modes normal, fork, thread et subshell;
- des codes d'erreur documentes.

## Installation locale

```bash
chmod +x ./bin/sysremote.sh
cp ./sysremote.conf.example ./sysremote.conf
./bin/sysremote.sh -h
```

## Architecture

```text
bin/sysremote.sh          Point d'entree CLI Bash
lib/defaults.sh           Valeurs par defaut et codes de retour
lib/ui.sh                 Aide, erreurs et logging
lib/utils.sh              Petits utilitaires de texte/validation simple
lib/config.sh             Chargement et validation de configuration
lib/validation.sh         Validation hotes, comptes, commandes et droits
lib/targets.sh            Lecture inventaire et cibles inline
lib/remote.sh             SSH et modes normal/fork/thread/subshell
lib/commands.sh           Commandes metier
lib/cli.sh                Parsing CLI, dispatch et main
sysremote.conf.example    Configuration exemple
inventory.example         Inventaire exemple
docs/usage-rapide.md      Guide d'utilisation
docs/tests-manuels.md     Tests et preuves d'execution
docs/rapport-shell.md     Rapport source pour PDF
```

Le point d'entree reste volontairement court: il verifie Bash, localise le
projet, charge les modules `lib/`, puis lance `main`. Les fonctions sont
regroupees par responsabilite pour garder le projet lisible.

## Options principales

```text
-h              aide complete
-c FICHIER      configuration
-i FICHIER      inventaire
-m HOTES        hotes separes par des virgules
-l DOSSIER      dossier de logs, defaut /var/log/sysremote
-U LOGIN        login SSH
-p PORT         port SSH
-T SECONDES     timeout SSH
-f              mode fork avec & et wait
-t              mode thread avec pool xargs -P
-s              mode subshell avec (...)
-j N            nombre de workers thread
-r              restauration par defaut, root uniquement
-N              desactive le controle root local pour actions sensibles
-n              dry-run
-v              verbeux
```

## Exemples d'execution

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -m 192.0.2.10 validate-hosts
./bin/sysremote.sh -l /tmp/sysremote-logs -f -n -m 192.0.2.10,192.0.2.11 sessions who
./bin/sysremote.sh -l /tmp/sysremote-logs -t -j 2 -n -m 192.0.2.10,192.0.2.11 sessions who
./bin/sysremote.sh -l /tmp/sysremote-logs -s -m 192.0.2.10 validate-hosts
./bin/sysremote.sh -l /tmp/sysremote-logs benchmark medium
./bin/sysremote.sh -l /tmp/sysremote-logs archive-logs ./archives
sudo ./bin/sysremote.sh -r
```

## Logging

Par defaut, les logs sont ecrits dans:

```text
/var/log/sysremote/history.log
```

Pour un lancement sans privileges root, utiliser un dossier personnalisable:

```bash
./bin/sysremote.sh -l /tmp/sysremote-logs -m 192.0.2.10 validate-hosts
```

Chaque ligne du journal respecte le format:

```text
yyyy-mm-dd-hh-mm-ss : username : INFOS : message
yyyy-mm-dd-hh-mm-ss : username : ERROR : message
```

## Captures d'ecran

Captures attendues pour le rapport:

1. `./bin/sysremote.sh -h`
2. log genere dans `history.log`
3. `benchmark light`
4. archive `.tar.gz` creee par `archive-logs`

## Documentation

- [Utilisation rapide](docs/usage-rapide.md)
- [Tests manuels](docs/tests-manuels.md)
- [Rapport source](docs/rapport-shell.md)
