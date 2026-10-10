#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
if [ -n "$_COMMON_INIT_FAILED" ]; then
  echo "ERROR: Could not determine plugin root directory." >&2
  echo "Set CLAUDE_PLUGIN_ROOT or run from the scripts/ directory." >&2
  exit 1
fi

ARG="${1:-}"
if [ -z "$ARG" ]; then
  echo "Usage: compile.sh <ModuleName | MyDesign/ModuleName | workspace/ModuleName>" >&2
  exit 1
fi
resolve_module_paths "$ARG"

export SBT_OPTS="-Dsbt.supershell=false"

mkdir -p "$OUTPUT_DIR"

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

$TIMEOUT_CMD sbt --batch "runMain chipagent.Generate --module $MODULE --target-dir $OUTPUT_DIR" > "$LOG" 2>&1 || EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  SV_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.sv" -o -name "*.v" \) 2>/dev/null | wc -l)
  if [ "$SV_COUNT" -gt 0 ]; then
    echo "Compilation successful:"
    find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.sv" -o -name "*.v" \) -print
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
  echo "Check $PROJECT_DIR/build.sbt and source files in $PROJECT_DIR/src/main/scala/chipagent/"
  exit 1
fi
