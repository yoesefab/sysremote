# Makefile — Lot 3: sysremote modules C

CC      = gcc
CFLAGS  = -Wall -Werror -O2
LDFLAGS_THREAD = -lpthread

.PHONY: all clean check

all: sysremote_fork sysremote_thread
	@echo "Compilation reussie"

sysremote_fork: sysremote_fork.c
	$(CC) $(CFLAGS) -o sysremote_fork sysremote_fork.c

sysremote_thread: sysremote_thread.c
	$(CC) $(CFLAGS) -o sysremote_thread sysremote_thread.c $(LDFLAGS_THREAD)

check:
	bash -n sysremote_parallel.sh && echo "sysremote_parallel.sh OK"
	bash -n benchmark.sh && echo "benchmark.sh OK"

clean:
	rm -f sysremote_fork sysremote_thread
