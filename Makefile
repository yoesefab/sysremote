.PHONY: test audit-tree native native-clean native-check deliverables

test:
	bash tests/smoke.sh

audit-tree:
	find bin lib modules docs tests assets build backups logs archives reports tools examples -maxdepth 3 -type f | sort

native: build/native/sysremote_fork build/native/sysremote_thread

build/native/sysremote_fork: modules/native/sysremote_fork.c
	mkdir -p build/native
	gcc -Wall -Werror -O2 -o build/native/sysremote_fork modules/native/sysremote_fork.c

build/native/sysremote_thread: modules/native/sysremote_thread.c
	mkdir -p build/native
	gcc -Wall -Werror -O2 -o build/native/sysremote_thread modules/native/sysremote_thread.c -lpthread

native-check:
	bash -n tools/native_parallel.sh
	bash -n tools/native_benchmark.sh

native-clean:
	rm -f build/native/sysremote_fork build/native/sysremote_thread

deliverables:
	python3 tools/make_deliverables.py
