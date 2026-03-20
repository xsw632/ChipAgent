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
# --- Workspace-aware path resolution ---
WORKSPACE_ARG="${1:-}"
if [ -n "$WORKSPACE_ARG" ]; then
  case "$WORKSPACE_ARG" in
    /*) WORKSPACE_DIR="$WORKSPACE_ARG" ;;
    *)  WORKSPACE_DIR="$PLUGIN_ROOT/$WORKSPACE_ARG" ;;
  esac
  GENERATED_DIR="$WORKSPACE_DIR/generated"
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
