#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
if [ -n "$_COMMON_INIT_FAILED" ]; then
  echo "ERROR: Could not determine plugin root directory." >&2
  echo "Set CLAUDE_PLUGIN_ROOT or run from the scripts/ directory." >&2
  exit 1
fi

# --- Argument parsing and path resolution ---
# Three modes (same as compile.sh):
#   1. Bare module name (e.g. ALU)              -> MyDesign/<Module>/...
#   2. MyDesign/<Module> explicit path           -> MyDesign/<Module>/...
#   3. workspace/<Module> old path (compat)      -> workspace/<Module>/...
ARG="${1:-}"
if [ -n "$ARG" ]; then
  if [[ "$ARG" == "workspace/"* ]]; then
    # Mode 3: old workspace/ path (backward compat)
    case "$ARG" in
      /*) MODULE_DIR="$ARG" ;;
      *)  MODULE_DIR="$PLUGIN_ROOT/$ARG" ;;
    esac
    MODULE=$(basename "$MODULE_DIR")
  else
    # Mode 1 or 2: bare name or MyDesign/<Module>
    MODULE=$(basename "$ARG")
    if [[ "$ARG" == */* ]]; then
      case "$ARG" in
        /*) MODULE_DIR="$ARG" ;;
        *)  MODULE_DIR="$PLUGIN_ROOT/$ARG" ;;
      esac
    else
      MODULE_DIR="$PLUGIN_ROOT/MyDesign/$MODULE"
    fi
  fi
else
  echo "Usage: synth.sh <ModuleName>" >&2
  echo "  e.g.  synth.sh ALU              (-> MyDesign/ALU/)" >&2
  echo "  e.g.  synth.sh MyDesign/ALU     (-> MyDesign/ALU/)" >&2
  echo "  (workspace/ALU also accepted for backward compat)" >&2
  exit 1
fi

# --- Resolve paths ---
VERILOG_PATH="$MODULE_DIR/workspace/generated/${MODULE}.v"
PNR_DIR="$MODULE_DIR/workspace/pnr"
REPORTS_PATH="$PNR_DIR/reports"

# --- Verify Verilog exists ---
if [ ! -f "$VERILOG_PATH" ]; then
  echo "ERROR: Verilog file not found: $VERILOG_PATH" >&2
  echo "Run 'scripts/compile.sh $MODULE' first to compile Chisel to Verilog." >&2
  exit 1
fi

# --- Extract module name from Verilog (authoritative source) ---
MODULE_NAME=$(grep -m1 '^module ' "$VERILOG_PATH" | sed 's/^module \([A-Za-z_][A-Za-z0-9_]*\).*/\1/')
if [ -z "$MODULE_NAME" ]; then
  echo "ERROR: Could not extract module name from $VERILOG_PATH" >&2
  exit 1
fi

# --- Pre-flight PDK validation ---
bash "$PLUGIN_ROOT/scripts/validate-pdk.sh"

# --- Generate SDC constraints ---
bash "$PLUGIN_ROOT/scripts/generate_sdc.sh" "$MODULE"

# --- Resolve PDK path: env var > env.json > error ---
PDK_DIR="${NANGATE45_DIR:-}"
if [ -z "$PDK_DIR" ]; then
  ENV_JSON="$PLUGIN_ROOT/.chipagent/env.json"
  if [ -f "$ENV_JSON" ] && command -v jq >/dev/null 2>&1; then
    PDK_DIR=$(jq -r '.pdk.nangate45.path // empty' "$ENV_JSON")
  fi
fi
if [ -z "$PDK_DIR" ]; then
  echo "ERROR: nangate45 PDK path not found." >&2
  echo "Run 'scripts/detect-env.sh' first, or set NANGATE45_DIR environment variable." >&2
  exit 1
fi

# --- Set environment variables for synth.tcl ---
export DESIGN_NAME="$MODULE_NAME"
export VERILOG_FILE="$VERILOG_PATH"
export LIB_FILE="$PDK_DIR/lib/NangateOpenCellLibrary_typical.lib"
export OUTPUT_DIR="$PNR_DIR"
export REPORTS_DIR="$REPORTS_PATH"
export SDC_FILE="$PNR_DIR/constraint.sdc"

# --- Create output directories ---
mkdir -p "$REPORTS_PATH"

# --- Run Yosys synthesis ---
LOG=$(mktemp 2>/dev/null || echo "${TEMP:-/tmp}/chipagent-synth-$$.log")
trap "rm -f \"$LOG\"" EXIT

echo "Synthesizing $MODULE_NAME with Yosys..."

EXIT_CODE=0
yosys -c "$PLUGIN_ROOT/scripts/synth.tcl" > "$LOG" 2>&1 || EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "ERROR: Yosys synthesis failed (exit code $EXIT_CODE)" >&2
  echo "--- Yosys log ---" >&2
  cat "$LOG" >&2
  echo "---" >&2
  exit 1
fi

# --- Verify output netlist ---
NETLIST="$PNR_DIR/${MODULE_NAME}.synth.v"
if [ ! -f "$NETLIST" ]; then
  echo "ERROR: Synthesis produced no netlist at $NETLIST" >&2
  echo "--- Yosys log ---" >&2
  cat "$LOG" >&2
  echo "---" >&2
  exit 1
fi

# --- Print synthesis summary ---
GATE_COUNT=$(grep 'Number of cells:' "$REPORTS_PATH/synth_stat.txt" | awk '{print $NF}')
AREA=$(grep 'Chip area for module' "$REPORTS_PATH/synth_stat.txt" | grep -oE '[0-9]+\.[0-9]+' | head -1)

echo "Synthesis complete:"
echo "  Module:  $MODULE_NAME"
echo "  Cells:   $GATE_COUNT"
echo "  Area:    ${AREA}um2"
echo "  Netlist: $NETLIST"
echo "  Report:  $REPORTS_PATH/synth_stat.txt"
