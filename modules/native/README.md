# Native Concurrency Helpers

This directory integrates Wafae's Lot 3 C sources into the final project as
optional native helpers.

- `sysremote_fork.c`: fork-based multi-host SSH/SCP executor.
- `sysremote_thread.c`: pthread scheduler that uses fork/exec for SSH/SCP work.

The unified runtime does not depend on these binaries. The main CLI implements
assignment-required concurrency in Bash through `normal`, `fork`, `thread`, and
`subshell` modes in `lib/remote.sh`.

Build the native helpers with:

```bash
make native
```

The binaries are written to `build/native/`.
