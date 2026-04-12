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
#   1. Bare module name (e.g. ALU8)              → MyDesign/<Module>/workspace/generated
#   2. MyDesign/<Module> explicit path            → MyDesign/<Module>/workspace/generated
#   3. workspace/<Module> old path (compat)       → workspace/<Module>/generated
ARG="${1:-}"
if [ -n "$ARG" ]; then
  if [[ "$ARG" == "workspace/"* ]]; then
    # Mode 3: old workspace/ path (backward compat)
    case "$ARG" in
      /*) WORKSPACE_DIR="$ARG" ;;
      *)  WORKSPACE_DIR="$PLUGIN_ROOT/$ARG" ;;
    esac
    GENERATED_DIR="$WORKSPACE_DIR/generated"
  else
    # Mode 1 or 2: bare name or MyDesign/<Module>
    if [[ "$ARG" == */* ]]; then
      # Explicit path like MyDesign/ALU8
      case "$ARG" in
        /*) GENERATED_DIR="$ARG/workspace/generated" ;;
        *)  GENERATED_DIR="$PLUGIN_ROOT/$ARG/workspace/generated" ;;
      esac
    else
      # Bare module name → MyDesign/<Module>
      GENERATED_DIR="$PLUGIN_ROOT/MyDesign/$ARG/workspace/generated"
    fi
  fi
else
  GENERATED_DIR="$PLUGIN_ROOT/generated"
fi
WARNINGS_LOG="$GENERATED_DIR/lint-warnings.log"

# Waiver file: prefer per-module, fall back to global
if [ -f "$GENERATED_DIR/chisel-warnings.vlt" ]; then
  WAIVER_FILE="$GENERATED_DIR/chisel-warnings.vlt"
elif [ -f "$PLUGIN_ROOT/generated/chisel-warnings.vlt" ]; then
  WAIVER_FILE="$PLUGIN_ROOT/generated/chisel-warnings.vlt"
else
  WAIVER_FILE=""
fi

# Find all .v files
V_FILES=$(find "$GENERATED_DIR" -maxdepth 1 -name "*.v" 2>/dev/null)
if [ -z "$V_FILES" ]; then
  echo "LINT ERROR: No .v files found in $GENERATED_DIR"
  exit 1
fi

# Build waiver args
WAIVER_ARGS=()
if [ -n "$WAIVER_FILE" ] && [ -f "$WAIVER_FILE" ]; then
  WAIVER_ARGS=("$WAIVER_FILE")
fi

# Error pass: lint each file individually
LINT_PASS=true
for vfile in $V_FILES; do
  TMPLOG=$(mktemp)
  trap "rm -f $TMPLOG" EXIT
  EXIT_CODE=0
  verilator --lint-only "${WAIVER_ARGS[@]}" "$vfile" > "$TMPLOG" 2>&1 || EXIT_CODE=$?
  if [ "$EXIT_CODE" -ne 0 ]; then
    echo "LINT ERRORS in $(basename "$vfile"):"
    cat "$TMPLOG"
    LINT_PASS=false
  fi
  rm -f "$TMPLOG"
done

# Warning-capture pass: truncate log first, then append per-file
: > "$WARNINGS_LOG"
for vfile in $V_FILES; do
  verilator --lint-only -Wall -Wno-fatal "${WAIVER_ARGS[@]}" "$vfile" 2>&1 \
    | grep '^%Warning' >> "$WARNINGS_LOG" || true
done

# Report warnings
if [ -s "$WARNINGS_LOG" ]; then
  WARN_COUNT=$(wc -l < "$WARNINGS_LOG")
  echo "Lint warnings ($WARN_COUNT):"
  cat "$WARNINGS_LOG"
fi

# Final result
if [ "$LINT_PASS" = true ]; then
  echo "LINT PASSED: All files clean"
  exit 0
else
  echo "LINT FAILED: Fix errors above and retry"
  exit 1
fi
