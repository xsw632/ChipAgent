#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
GENERATED_DIR="$PLUGIN_ROOT/generated"
SIM_DIR="$PLUGIN_ROOT/sim"
LOG_DIR="$SIM_DIR/logs"
WAIVER_FILE="$GENERATED_DIR/chisel-warnings.vlt"
MODULE="${1:-ALU}"

# Build waiver args to suppress known Chisel warnings during verilation
WAIVER_ARGS=()
if [ -f "$WAIVER_FILE" ]; then
  WAIVER_ARGS=("$WAIVER_FILE")
fi

# 1. Verilate: generate C++ model from Verilog + testbench
echo "Verilating $MODULE..."
verilator --cc "$GENERATED_DIR/$MODULE.v" \
  --exe "$SIM_DIR/tb_$MODULE.cpp" \
  --Mdir "$SIM_DIR/obj_dir" \
  -CFLAGS "-std=c++17" \
  "${WAIVER_ARGS[@]}"

# 2. Build: compile the simulation binary
echo "Building simulation binary..."
make -C "$SIM_DIR/obj_dir" -f "V$MODULE.mk" -j"$(nproc)"

# 3. Run: execute simulation and capture output
mkdir -p "$LOG_DIR"

SIM_EXIT=0
"$SIM_DIR/obj_dir/V$MODULE" 2>&1 | tee "$LOG_DIR/sim_result.log" || SIM_EXIT=${PIPESTATUS[0]}

# 4. Report result
if [ "$SIM_EXIT" -eq 0 ]; then
  echo "SIM PASSED"
else
  echo "SIM FAILED"
fi

exit "$SIM_EXIT"
