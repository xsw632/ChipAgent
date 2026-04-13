#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
if [ -n "$_COMMON_INIT_FAILED" ]; then
  echo "ERROR: Could not determine plugin root directory." >&2
  exit 1
fi

# --- Arguments ---
MODULE="${1:-}"
if [ -z "$MODULE" ]; then
  echo "Usage: generate_sdc.sh <ModuleName> [ProjectDir]" >&2
  echo "  e.g.  generate_sdc.sh ALU" >&2
  echo "  e.g.  generate_sdc.sh Counter8 MyDesign" >&2
  exit 1
fi

PROJECT_DIR="${2:-MyDesign}"

# --- Locate Verilog file ---
VERILOG_FILE="$PLUGIN_ROOT/$PROJECT_DIR/$MODULE/workspace/generated/$MODULE.v"
if [ ! -f "$VERILOG_FILE" ]; then
  # Try finding any .v file in the generated directory
  GEN_DIR="$PLUGIN_ROOT/$PROJECT_DIR/$MODULE/workspace/generated"
  if [ -d "$GEN_DIR" ]; then
    VERILOG_FILE=$(find "$GEN_DIR" -maxdepth 1 -name '*.v' | head -1)
  fi
  if [ -z "${VERILOG_FILE:-}" ] || [ ! -f "$VERILOG_FILE" ]; then
    echo "ERROR: No Verilog file found for module '$MODULE' in $GEN_DIR" >&2
    exit 1
  fi
fi

# --- Extract module name from Verilog (not filename) ---
MODULE_NAME=$(grep -m1 '^module ' "$VERILOG_FILE" | sed 's/^module \([A-Za-z_][A-Za-z0-9_]*\).*/\1/')
if [ -z "$MODULE_NAME" ]; then
  echo "ERROR: Could not extract module name from $VERILOG_FILE" >&2
  exit 1
fi

# --- Detect sequential vs combinational ---
IS_SEQUENTIAL=false
if grep -qE 'always @\(posedge' "$VERILOG_FILE"; then
  IS_SEQUENTIAL=true
fi

# --- Read clock period from spec.json or use default ---
CLK_PERIOD="2.0"
SPEC_FILE="$PLUGIN_ROOT/$PROJECT_DIR/$MODULE/workspace/spec.json"
if [ -f "$SPEC_FILE" ] && command -v jq >/dev/null 2>&1; then
  SPEC_PERIOD=$(jq -r '.clock_period_ns // empty' "$SPEC_FILE" 2>/dev/null || true)
  if [ -n "$SPEC_PERIOD" ]; then
    CLK_PERIOD="$SPEC_PERIOD"
  fi
fi

# --- Create output directory ---
OUTPUT_DIR="$PLUGIN_ROOT/$PROJECT_DIR/$MODULE/workspace/pnr"
mkdir -p "$OUTPUT_DIR"
SDC_FILE="$OUTPUT_DIR/constraint.sdc"

# --- Write SDC ---
if [ "$IS_SEQUENTIAL" = true ]; then
  MODULE_TYPE="sequential"
  cat > "$SDC_FILE" <<EOF
current_design $MODULE_NAME

set clk_name  core_clock
set clk_port  [get_ports clock]
set clk_period $CLK_PERIOD

create_clock -name \$clk_name -period \$clk_period \$clk_port

set_input_delay  [expr \$clk_period * 0.2] -clock \$clk_name [all_inputs]
set_output_delay [expr \$clk_period * 0.2] -clock \$clk_name [all_outputs]
EOF
else
  MODULE_TYPE="combinational"
  cat > "$SDC_FILE" <<EOF
current_design $MODULE_NAME

set clk_period $CLK_PERIOD

create_clock -name virtual_clk -period \$clk_period

set_input_delay  0.0 -clock virtual_clk [all_inputs]
set_output_delay 0.0 -clock virtual_clk [all_outputs]
set_max_delay \$clk_period -from [all_inputs] -to [all_outputs]
EOF
fi

echo "SDC generated:"
echo "  Module:  $MODULE_NAME"
echo "  Type:    $MODULE_TYPE"
echo "  Period:  ${CLK_PERIOD}ns"
echo "  Output:  $SDC_FILE"
