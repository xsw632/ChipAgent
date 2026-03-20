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
ARG="${1:-}"
if [[ "$ARG" == */* ]]; then
  # Workspace mode: argument is a path like workspace/Foo
  case "$ARG" in
    /*) WORKSPACE_DIR="$ARG" ;;
    *)  WORKSPACE_DIR="$PLUGIN_ROOT/$ARG" ;;
  esac
  MODULE=$(basename "$WORKSPACE_DIR")
  GENERATED_DIR="$WORKSPACE_DIR/generated"
  SIM_DIR="$WORKSPACE_DIR/sim"
  LOG_DIR="$WORKSPACE_DIR/sim/logs"
  OBJ_DIR="$WORKSPACE_DIR/sim/obj_dir"
else
  # v1.0 mode: argument is a bare module name
  MODULE="${ARG:-ALU}"
  GENERATED_DIR="$PLUGIN_ROOT/generated"
  SIM_DIR="$PLUGIN_ROOT/sim"
  LOG_DIR="$SIM_DIR/logs"
  OBJ_DIR="$SIM_DIR/obj_dir"
fi

# Waiver file: prefer per-module, fall back to global
if [ -f "$GENERATED_DIR/chisel-warnings.vlt" ]; then
  WAIVER_FILE="$GENERATED_DIR/chisel-warnings.vlt"
elif [ -f "$PLUGIN_ROOT/generated/chisel-warnings.vlt" ]; then
  WAIVER_FILE="$PLUGIN_ROOT/generated/chisel-warnings.vlt"
else
  WAIVER_FILE=""
fi

# Build waiver args to suppress known Chisel warnings during verilation
WAIVER_ARGS=()
if [ -n "$WAIVER_FILE" ] && [ -f "$WAIVER_FILE" ]; then
  WAIVER_ARGS=("$WAIVER_FILE")
fi

# Ensure workspace sim directories exist
mkdir -p "$LOG_DIR" "$OBJ_DIR"

# 1. Verilate: generate C++ model from Verilog + testbench
echo "Verilating $MODULE..."
verilator --cc "$GENERATED_DIR/$MODULE.v" \
  --exe "$SIM_DIR/tb_$MODULE.cpp" \
  --Mdir "$OBJ_DIR" \
  -CFLAGS "-std=c++17 -I$PLUGIN_ROOT/sim" \
  "${WAIVER_ARGS[@]}"

# 2. Build: compile the simulation binary
echo "Building simulation binary..."
make -C "$OBJ_DIR" -f "V$MODULE.mk" -j"$(nproc)"

# 3. Run: execute simulation and capture output
mkdir -p "$LOG_DIR"

SIM_EXIT=0
"$OBJ_DIR/V$MODULE" 2>&1 | tee "$LOG_DIR/sim_result.log" || SIM_EXIT=${PIPESTATUS[0]}

# 4. Report result
if [ "$SIM_EXIT" -eq 0 ]; then
  echo "SIM PASSED"
else
  echo "SIM FAILED"
fi

exit "$SIM_EXIT"
