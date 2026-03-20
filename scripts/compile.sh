#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# Convert MSYS/Cygwin paths to mixed-mode (C:/...) for JVM compatibility on Windows
if command -v cygpath >/dev/null 2>&1; then
  PLUGIN_ROOT="$(cygpath -m "$PLUGIN_ROOT")"
fi
if [ -z "$PLUGIN_ROOT" ]; then
  echo "ERROR: Could not determine plugin root directory." >&2
  echo "Set CLAUDE_PLUGIN_ROOT or run from the scripts/ directory." >&2
  exit 1
fi
PROJECT_DIR="$PLUGIN_ROOT/chisel-project"

# --- Workspace-aware path resolution ---
WORKSPACE_ARG="${1:-}"
if [ -n "$WORKSPACE_ARG" ]; then
  case "$WORKSPACE_ARG" in
    /*) WORKSPACE_DIR="$WORKSPACE_ARG" ;;
    *)  WORKSPACE_DIR="$PLUGIN_ROOT/$WORKSPACE_ARG" ;;
  esac
  MODULE=$(basename "$WORKSPACE_DIR")
  OUTPUT_DIR="$WORKSPACE_DIR/generated"
else
  OUTPUT_DIR="$PLUGIN_ROOT/generated"
  MODULE=""
fi

export SBT_OPTS="-Dsbt.supershell=false"

mkdir -p "$OUTPUT_DIR"
if [ -n "$MODULE" ]; then
  mkdir -p "$WORKSPACE_DIR/generated" "$WORKSPACE_DIR/sim/logs"
fi

LOG=$(mktemp 2>/dev/null || echo "${TEMP:-/tmp}/chipagent-compile-$$.log")
trap "rm -f \"$LOG\"" EXIT

echo "Compiling Chisel to Verilog..."
cd "$PROJECT_DIR"

EXIT_CODE=0
# Use GNU timeout if available; skip on Windows where timeout.exe is a different command
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout 120"
elif timeout --version >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout 120"
else
  TIMEOUT_CMD=""
fi
if [ -n "$MODULE" ]; then
  $TIMEOUT_CMD sbt --batch "runMain chipagent.Generate --module $MODULE --target-dir $OUTPUT_DIR" > "$LOG" 2>&1 || EXIT_CODE=$?
else
  $TIMEOUT_CMD sbt --batch "runMain chipagent.Generate --target-dir $OUTPUT_DIR" > "$LOG" 2>&1 || EXIT_CODE=$?
fi

if [ "$EXIT_CODE" -eq 0 ]; then
  SV_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.sv" -o -name "*.v" \) 2>/dev/null | wc -l)
  if [ "$SV_COUNT" -gt 0 ]; then
    echo "Compilation successful:"
    ls "$OUTPUT_DIR"/*.sv "$OUTPUT_DIR"/*.v 2>/dev/null
  else
    echo "WARNING: sbt exited 0 but no .sv files found in $OUTPUT_DIR"
    cat "$LOG"
    exit 1
  fi
else
  echo "BUILD ERROR: $(date -Iseconds)"
  echo "---"
  cat "$LOG"
  echo "---"
  echo "Check chisel-project/build.sbt and source files in chisel-project/src/main/scala/chipagent/"
  exit 1
fi
