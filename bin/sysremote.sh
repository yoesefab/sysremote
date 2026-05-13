#!/usr/bin/env bash

# sysremote - unified Bash/Linux administration project.

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'sysremote: Bash 4 or newer is required.\n' >&2
  exit 2
fi

SYSREMOTE_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSREMOTE_ROOT_DIR="$(cd "$SYSREMOTE_BIN_DIR/.." && pwd)"
readonly SYSREMOTE_ROOT_DIR

# shellcheck source=../lib/defaults.sh
. "$SYSREMOTE_ROOT_DIR/lib/defaults.sh"
# shellcheck source=../lib/utils.sh
. "$SYSREMOTE_ROOT_DIR/lib/utils.sh"
# shellcheck source=../lib/ui.sh
. "$SYSREMOTE_ROOT_DIR/lib/ui.sh"
# shellcheck source=../lib/config.sh
. "$SYSREMOTE_ROOT_DIR/lib/config.sh"
# shellcheck source=../lib/validation.sh
. "$SYSREMOTE_ROOT_DIR/lib/validation.sh"
# shellcheck source=../lib/targets.sh
. "$SYSREMOTE_ROOT_DIR/lib/targets.sh"
# shellcheck source=../lib/remote.sh
. "$SYSREMOTE_ROOT_DIR/lib/remote.sh"
# shellcheck source=../modules/backup.sh
. "$SYSREMOTE_ROOT_DIR/modules/backup.sh"
# shellcheck source=../modules/restore.sh
. "$SYSREMOTE_ROOT_DIR/modules/restore.sh"
# shellcheck source=../modules/audit.sh
. "$SYSREMOTE_ROOT_DIR/modules/audit.sh"
# shellcheck source=../modules/maintenance.sh
. "$SYSREMOTE_ROOT_DIR/modules/maintenance.sh"
# shellcheck source=../modules/schedule.sh
. "$SYSREMOTE_ROOT_DIR/modules/schedule.sh"
# shellcheck source=../modules/monitoring.sh
. "$SYSREMOTE_ROOT_DIR/modules/monitoring.sh"
# shellcheck source=../lib/commands.sh
. "$SYSREMOTE_ROOT_DIR/lib/commands.sh"
# shellcheck source=../lib/cli.sh
. "$SYSREMOTE_ROOT_DIR/lib/cli.sh"

main "$@"
