#!/usr/bin/env bash
# Compatibility entry point; keep all installation logic in bin/install.js.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "$SCRIPT_DIR/../bin/install.js" "$@"
