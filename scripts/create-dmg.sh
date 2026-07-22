#!/bin/zsh
set -euo pipefail

# Backward-compatible entry point. New automation should call package_dmg.sh.
SCRIPT_DIR="${0:A:h}"
exec "$SCRIPT_DIR/package_dmg.sh" "$@"
