#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
if [ -n "$_COMMON_INIT_FAILED" ]; then
  echo "ERROR: Could not determine plugin root directory." >&2
  echo "Set CLAUDE_PLUGIN_ROOT or run from the scripts/ directory." >&2
  exit 1
fi

# --- Argument parsing and path resolution ---
# Three modes (same as synth.sh):
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
  echo "Usage: pnr.sh <ModuleName>" >&2
  echo "  e.g.  pnr.sh ALU              (-> MyDesign/ALU/)" >&2
  echo "  e.g.  pnr.sh MyDesign/ALU     (-> MyDesign/ALU/)" >&2
  echo "  (workspace/ALU also accepted for backward compat)" >&2
  exit 1
fi

# --- Resolve paths ---
VERILOG_PATH="$MODULE_DIR/workspace/generated/${MODULE}.v"
PNR_DIR="$MODULE_DIR/workspace/pnr"
REPORTS_DIR="$PNR_DIR/reports"
NETLIST="$PNR_DIR/${MODULE}.synth.v"

# --- Pre-flight checks ---
# Check synthesized netlist (may need MODULE_NAME from Verilog, check both)
if [ ! -f "$NETLIST" ]; then
  # Will try again after MODULE_NAME extraction below
  :
fi

# Verify SDC exists
if [ ! -f "$PNR_DIR/constraint.sdc" ]; then
  echo "ERROR: SDC file not found: $PNR_DIR/constraint.sdc" >&2
  echo "Run 'scripts/synth.sh $MODULE' first (synth.sh calls generate_sdc.sh)." >&2
  exit 1
fi

# PDK validation
bash "$PLUGIN_ROOT/scripts/validate-pdk.sh"

# --- Extract module name from Verilog (authoritative source) ---
if [ ! -f "$VERILOG_PATH" ]; then
  echo "ERROR: Verilog file not found: $VERILOG_PATH" >&2
  echo "Run 'scripts/compile.sh $MODULE' first to compile Chisel to Verilog." >&2
  exit 1
fi

MODULE_NAME=$(grep -m1 '^module ' "$VERILOG_PATH" | sed 's/^module \([A-Za-z_][A-Za-z0-9_]*\).*/\1/')
if [ -z "$MODULE_NAME" ]; then
  echo "ERROR: Could not extract module name from $VERILOG_PATH" >&2
  exit 1
fi

# Update NETLIST path with authoritative module name
NETLIST="$PNR_DIR/${MODULE_NAME}.synth.v"
if [ ! -f "$NETLIST" ]; then
  echo "ERROR: Synthesized netlist not found: $NETLIST" >&2
  echo "Run 'scripts/synth.sh $MODULE' first." >&2
  exit 1
fi

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

# --- Sequential detection ---
IS_SEQUENTIAL=0
if grep -q 'always @(posedge' "$VERILOG_PATH"; then
  IS_SEQUENTIAL=1
  echo "Module $MODULE_NAME: sequential (clock detected)"
else
  echo "Module $MODULE_NAME: combinational"
fi

# --- Set environment variables for pnr.tcl ---
export DESIGN_NAME="$MODULE_NAME"
export NETLIST
export SDC_FILE="$PNR_DIR/constraint.sdc"
export LIB_FILE="$PDK_DIR/lib/NangateOpenCellLibrary_typical.lib"
export TECH_LEF="$PDK_DIR/lef/NangateOpenCellLibrary.tech.lef"
export CELL_LEF="$PDK_DIR/lef/NangateOpenCellLibrary.macro.mod.lef"
export PDK_DIR
export OUTPUT_DIR="$PNR_DIR"
export REPORTS_DIR
export IS_SEQUENTIAL
export RCX_RULES="$PDK_DIR/rcx_patterns.rules"

# --- Create output directories ---
mkdir -p "$REPORTS_DIR"

# --- Run OpenROAD ---
LOG_FILE=$(mktemp 2>/dev/null || echo "${TEMP:-/tmp}/chipagent-pnr-$$.log")
trap "rm -f \"$LOG_FILE\"" EXIT

echo "Running OpenROAD PnR for $MODULE_NAME..."

EXIT_CODE=0
openroad -no_init -exit -log "$LOG_FILE" "$PLUGIN_ROOT/scripts/pnr.tcl" || EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "ERROR: OpenROAD PnR failed (exit code $EXIT_CODE)" >&2
  echo "--- OpenROAD log (last 50 lines) ---" >&2
  tail -50 "$LOG_FILE" >&2
  echo "---" >&2
  exit 1
fi

# Verify PNR_COMPLETE marker
if ! grep -q 'PNR_COMPLETE' "$LOG_FILE"; then
  echo "ERROR: OpenROAD did not complete successfully (PNR_COMPLETE marker missing)" >&2
  echo "--- OpenROAD log (last 50 lines) ---" >&2
  tail -50 "$LOG_FILE" >&2
  echo "---" >&2
  exit 1
fi

# --- Verify routed DEF ---
ROUTED_DEF="$PNR_DIR/${MODULE_NAME}.routed.def"
if [ ! -f "$ROUTED_DEF" ]; then
  echo "ERROR: Routed DEF not found: $ROUTED_DEF" >&2
  exit 1
fi

# --- Extract reports from log ---
sed -n '/=== TIMING_REPORT_START ===/,/=== TIMING_REPORT_END ===/p' "$LOG_FILE" \
  | grep -v "^=== " > "$REPORTS_DIR/timing.rpt"

sed -n '/=== POWER_REPORT_START ===/,/=== POWER_REPORT_END ===/p' "$LOG_FILE" \
  | grep -v "^=== " > "$REPORTS_DIR/power.rpt"

sed -n '/=== AREA_REPORT_START ===/,/=== AREA_REPORT_END ===/p' "$LOG_FILE" \
  | grep -v "^=== " > "$REPORTS_DIR/area.rpt"

WNS=$(grep '^PNR_WNS:' "$LOG_FILE" | awk '{print $2}')
TNS=$(grep '^PNR_TNS:' "$LOG_FILE" | awk '{print $2}')

# --- Run KLayout GDS export ---
echo "Running KLayout GDS export for $MODULE_NAME..."

GDS_EXIT=0
klayout -zz \
  -rd design_name="$MODULE_NAME" \
  -rd in_def="$PNR_DIR/$MODULE_NAME.routed.def" \
  -rd tech_lef="$TECH_LEF" \
  -rd cell_lef="$CELL_LEF" \
  -rd in_gds="$PDK_DIR/gds/NangateOpenCellLibrary.gds" \
  -rd out_file="$PNR_DIR/$MODULE_NAME.gds" \
  -r "$PLUGIN_ROOT/scripts/def2gds.py" || GDS_EXIT=$?

if [ "$GDS_EXIT" -ne 0 ]; then
  echo "ERROR: KLayout GDS export failed (exit code $GDS_EXIT)" >&2
  exit 1
fi

# --- Verify GDS ---
GDS_FILE="$PNR_DIR/$MODULE_NAME.gds"
if [ ! -s "$GDS_FILE" ]; then
  echo "ERROR: GDS file missing or empty: $GDS_FILE" >&2
  exit 1
fi

# --- Extract area from report ---
AREA=$(grep 'Design area' "$REPORTS_DIR/area.rpt" | head -1)

# --- Determine timing status ---
TIMING_STATUS="UNKNOWN"
if [ -n "$WNS" ]; then
  # Check if WNS is non-negative (timing MET)
  if echo "$WNS" | grep -q '^-'; then
    TIMING_STATUS="VIOLATED"
  else
    TIMING_STATUS="MET"
  fi
fi

# --- Print summary ---
echo ""
echo "===== PnR Summary ====="
echo "  Module:    $MODULE_NAME"
echo "  WNS:       $WNS"
echo "  TNS:       $TNS"
echo "  Timing:    $TIMING_STATUS"
echo "  $AREA"
echo "  DEF:       $ROUTED_DEF"
echo "  GDS:       $GDS_FILE"
echo "  Reports:   $REPORTS_DIR"
echo "========================"
