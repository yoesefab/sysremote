# sysremote
# Lot 3 — Parallélisation et exécution multi-cibles

## Description
Ce lot implémente les modes de parallélisation de sysremote
pour exécuter des commandes SSH sur plusieurs machines simultanément.

## Fichiers

| Fichier | Rôle |
|---|---|
| `sysremote_parallel.sh` | Script principal (séquentiel, subshell, SCP, --max-procs) |
| `sysremote_fork.c` | Parallélisation par fork() |
| `sysremote_thread.c` | Parallélisation par pthread |
| `Makefile` | Compilation des modules C |
| `benchmark.sh` | Benchmark comparatif des 4 modes |

## Installation

```bash
make
```

## Utilisation

```bash
# Mode séquentiel
./sysremote_parallel.sh -q -H hosts.txt -- "uptime"

# Mode subshell
./sysremote_parallel.sh -s -H hosts.txt -- "uptime"

# Mode fork
./sysremote_parallel.sh -f -H hosts.txt -- "uptime"

# Mode thread
./sysremote_parallel.sh -t -H hosts.txt -- "uptime"

# Benchmark
./benchmark.sh -H hosts.txt -c "uptime" -i 3
```

## Auteur
Wafae — Lot 3
