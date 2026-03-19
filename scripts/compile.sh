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
OUTPUT_DIR="$PLUGIN_ROOT/generated"

export SBT_OPTS="-Dsbt.supershell=false"

mkdir -p "$OUTPUT_DIR"

LOG=$(mktemp)
trap "rm -f $LOG" EXIT

echo "Compiling Chisel to Verilog..."
cd "$PROJECT_DIR"

EXIT_CODE=0
timeout 120 sbt --batch "runMain chipagent.Generate --target-dir $OUTPUT_DIR" > "$LOG" 2>&1 || EXIT_CODE=$?

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
