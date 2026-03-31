#!/usr/bin/env bash
# Pre-flight validation of nangate45 PDK files
# Exits 0 if all required files exist, 1 otherwise
set -euo pipefail

source "$(dirname "$0")/_common.sh" 2>/dev/null || true
PLUGIN_ROOT="${PLUGIN_ROOT:-}"

# Resolve PDK path: env var > env.json > error
PDK_DIR="${NANGATE45_DIR:-}"

if [ -z "$PDK_DIR" ]; then
  ENV_JSON="$PLUGIN_ROOT/.chipagent/env.json"
  if [ -f "$ENV_JSON" ] && command -v jq >/dev/null 2>&1; then
    PDK_DIR=$(jq -r '.pdk.nangate45.path // empty' "$ENV_JSON")
  fi
fi

if [ -z "$PDK_DIR" ]; then
  echo "ERROR: nangate45 PDK path not found."
  echo "Run /chip-agent:initialize first, or set NANGATE45_DIR environment variable."
  exit 1
fi

# Required PDK files
REQUIRED_FILES=(
  "lib/NangateOpenCellLibrary_typical.lib"
  "lef/NangateOpenCellLibrary.tech.lef"
  "lef/NangateOpenCellLibrary.macro.mod.lef"
  "gds/NangateOpenCellLibrary.gds"
  "rcx_patterns.rules"
)

MISSING=0
for rel_path in "${REQUIRED_FILES[@]}"; do
  full_path="$PDK_DIR/$rel_path"
  if [ ! -f "$full_path" ]; then
    echo "ERROR: Required PDK file missing: $full_path"
    MISSING=$((MISSING + 1))
  fi
done

if [ "$MISSING" -gt 0 ]; then
  echo "PDK validation failed: $MISSING file(s) missing in $PDK_DIR"
  exit 1
fi

echo "PDK validation passed: $PDK_DIR"
exit 0
