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
#   1. Bare module name (e.g. ALU8)              → MyDesign/<Module>/workspace/...
#   2. MyDesign/<Module> explicit path            → MyDesign/<Module>/workspace/...
#   3. workspace/<Module> old path (compat)       → workspace/<Module>/sim/...
ARG="${1:-}"
if [ -n "$ARG" ]; then
  if [[ "$ARG" == "workspace/"* ]]; then
    # Mode 3: old workspace/ path (backward compat)
    case "$ARG" in
      /*) WORKSPACE_DIR="$ARG" ;;
      *)  WORKSPACE_DIR="$PLUGIN_ROOT/$ARG" ;;
    esac
    MODULE=$(basename "$WORKSPACE_DIR")
    GENERATED_DIR="$WORKSPACE_DIR/generated"
    SIM_DIR="$WORKSPACE_DIR/sim"
    LOG_DIR="$SIM_DIR/logs"
    OBJ_DIR="$SIM_DIR/obj_dir"
  else
    # Mode 1 or 2: bare name or MyDesign/<Module>
    if [[ "$ARG" == */* ]]; then
      # Explicit path like MyDesign/ALU8
      case "$ARG" in
        /*) BASE="$ARG" ;;
        *)  BASE="$PLUGIN_ROOT/$ARG" ;;
      esac
    else
      # Bare module name → MyDesign/<Module>
      BASE="$PLUGIN_ROOT/MyDesign/$ARG"
    fi
    MODULE=$(basename "$ARG")
    GENERATED_DIR="$BASE/workspace/generated"
    SIM_DIR="$BASE/workspace/sim"
    LOG_DIR="$SIM_DIR/logs"
    OBJ_DIR="$SIM_DIR/obj_dir"
  fi
else
  echo "Usage: simulate.sh <ModuleName>" >&2
  echo "  e.g.  simulate.sh ALU8           (→ MyDesign/ALU8/)" >&2
  echo "  (workspace/ALU8 also accepted for backward compat)" >&2
  exit 1
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
  --trace \
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

# Move VCD trace to logs directory if generated
[ -f trace.vcd ] && mv trace.vcd "$LOG_DIR/$MODULE.vcd"

# 4. Report result
if [ "$SIM_EXIT" -eq 0 ]; then
  echo "SIM PASSED"
else
  echo "SIM FAILED"
fi

"$(dirname "$0")/report.sh" "simulate" "$MODULE" "$SIM_EXIT" "$LOG_DIR/sim_result.log"
exit "$SIM_EXIT"
