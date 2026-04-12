#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
if [ -n "$_COMMON_INIT_FAILED" ]; then
  echo "ERROR: Could not determine plugin root directory." >&2
  echo "Set CLAUDE_PLUGIN_ROOT or run from the scripts/ directory." >&2
  exit 1
fi

# --- Path resolution ---
# Three modes supported:
#   1. Bare module name (e.g. ALU8)              → MyDesign/<Module>/...
#   2. MyDesign/<Module> explicit path            → MyDesign/<Module>/...
#   3. workspace/<Module> old path (compat)       → workspace/<Module>/generated (chisel-project at root)
ARG="${1:-}"
if [ -n "$ARG" ]; then
  if [[ "$ARG" == "workspace/"* ]]; then
    # Mode 3: old workspace/ path (backward compat)
    case "$ARG" in
      /*) WORKSPACE_DIR="$ARG" ;;
      *)  WORKSPACE_DIR="$PLUGIN_ROOT/$ARG" ;;
    esac
    MODULE=$(basename "$WORKSPACE_DIR")
    PROJECT_DIR="$PLUGIN_ROOT/chisel-project"
    OUTPUT_DIR="$WORKSPACE_DIR/generated"
  else
    # Mode 1 or 2: bare name or MyDesign/<Module>
    MODULE=$(basename "$ARG")
    if [[ "$ARG" == */* ]]; then
      # Explicit path like MyDesign/ALU8
      case "$ARG" in
        /*) PROJECT_DIR="$ARG/chisel-project" ;;
        *)  PROJECT_DIR="$PLUGIN_ROOT/$ARG/chisel-project" ;;
      esac
    else
      # Bare module name → MyDesign/<Module>
      PROJECT_DIR="$PLUGIN_ROOT/MyDesign/$ARG/chisel-project"
    fi
    OUTPUT_DIR="$(dirname "$PROJECT_DIR")/workspace/generated"
  fi
else
  echo "Usage: compile.sh <ModuleName>" >&2
  echo "  e.g.  compile.sh ALU8           (→ MyDesign/ALU8/)" >&2
  echo "  e.g.  compile.sh MyDesign/ALU8  (→ MyDesign/ALU8/)" >&2
  echo "  (workspace/ALU8 also accepted for backward compat)" >&2
  exit 1
fi

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
