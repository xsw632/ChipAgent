---
name: chipyard-pnr
description: "Run full Chipyard-to-ORFS PnR flow via Docker: nosram preprocessing, SRAM override generation, ORFS multi-round PnR on sky130hd."
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
---

# chip-agent:chipyard-pnr

End-to-end Chipyard PnR flow using Docker containers:
1. Find already-generated Verilog from `/chip-agent:chipyard`
2. Generate SRAM override modules
3. Run ORFS PnR via `openroad/orfs` Docker with multi-round parameter tuning

## Docker Strategy

| Container | Image | Purpose |
|-----------|-------|---------|
| ORFS PnR | `openroad/orfs:latest` | All OpenROAD/ORFS operations |
| Chipyard generation | `ucbbar/chipyard-image:latest` | Verilog generation (if needed) |

ORFS paths inside container: `/OpenROAD-flow-scripts/flow`
sky130hd: `/OpenROAD-flow-scripts/flow/platforms/sky130hd`
sky130ram: `/OpenROAD-flow-scripts/flow/platforms/sky130ram`

## Usage

```
/chip-agent:chipyard-pnr tinyrocket
```

## Pipeline

### Step 0 -- Parse Arguments

```bash
PLUGIN_ROOT="/home/sh/snap/worklib/test/ChipAgent"
RAW_CONFIG="$1"
CONFIG="TinyRocketConfig"
DESIGN="TinyRocket"
WORK_DIR="$PLUGIN_ROOT/MyDesign/$DESIGN/workspace/pnr"
mkdir -p "$WORK_DIR"

echo "=== Chipyard-PnR (Docker) ==="
echo "Config: $CONFIG"
echo "Work: $WORK_DIR"
```

### Step 1 -- Verify Environment

```bash
docker run --rm openroad/orfs:latest \
  bash -c "
    echo 'ORFS:'
    test -f /OpenROAD-flow-scripts/flow/Makefile && echo '  Makefile: OK'
    test -f /OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib && echo '  sky130hd LIB: OK'
    test -f /OpenROAD-flow-scripts/flow/platforms/sky130hd/lef/sky130_fd_sc_hd_merged.lef && echo '  sky130hd LEF: OK'
    ls /OpenROAD-flow-scripts/flow/platforms/sky130ram/ 2>/dev/null | head -3 && echo '  sky130ram: OK' || echo '  sky130ram: NOT FOUND'
    echo 'OpenROAD version:'
    /OpenROAD-flow-scripts/tools/install/OpenROAD/bin/openroad -version 2>&1 | head -1
  "
```

### Step 2 -- Locate Generated Verilog

```bash
VERILOG="$PLUGIN_ROOT/MyDesign/$DESIGN/workspace/generated/${CONFIG}.v"
SRAM_MAP="$PLUGIN_ROOT/MyDesign/$DESIGN/workspace/generated/sram_mapping.json"
SPEC="$PLUGIN_ROOT/MyDesign/$DESIGN/workspace/spec.json"

test -f "$VERILOG" || { echo "Verilog not found: $VERILOG"; echo "Run /chip-agent:chipyard tinyrocket first"; exit 1; }
test -f "$SRAM_MAP" && echo "SRAM mapping: found" || echo "SRAM mapping: not found (will generate)"
test -f "$SPEC" && echo "spec.json: found" || echo "spec.json: not found"

echo "Verilog: $(wc -l < "$VERILOG") lines"
```

### Step 3 -- Nosram Preprocessing

Strip behavioral memory modules from Chipyard Verilog:

```bash
NOSRAM_V="$WORK_DIR/${CONFIG}_nosram.v"
python3 -c "
import re, sys
with open(sys.argv[1]) as f:
    content = f.read()
# Remove *_ext module definitions (SRAM black boxes)
content = re.sub(r'^module\s+\w+_ext\b.*?^endmodule',
                '', content, flags=re.MULTILINE | re.DOTALL)
content = re.sub(r'^module\s+split_\w+_ext\b.*?^endmodule',
                '', content, flags=re.MULTILINE | re.DOTALL)
content = re.sub(r'\n{4,}', '\n\n', content)
with open(sys.argv[2], 'w') as f:
    f.write(content)
" "$VERILOG" "$NOSRAM_V"

echo "Nosram Verilog: $(wc -l < "$NOSRAM_V") lines"
grep -c '^module.*_ext' "$NOSRAM_V" && echo "WARNING: _ext modules remain" || echo "No _ext modules: OK"
```

### Step 4 -- Generate SRAM Override

Read sram_mapping.json or generate from mems.conf:

```bash
SRAM_OV="$WORK_DIR/${CONFIG}_sram_override.v"
MEMS_CONF="$PLUGIN_ROOT/MyDesign/$DESIGN/workspace/generated/mems.conf"

if [ -f "$SRAM_MAP" ]; then
    echo "Using existing sram_mapping.json"
    # Parse mapping and generate override (simplified)
    python3 - << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(json.dumps(d, indent=2))
PYEOF
    "$SRAM_MAP"
fi
```

For TinyRocketConfig, generate standard SRAM override (6 macros):
```bash
cat > "$SRAM_OV" << 'VEOF'
// SRAM override for TinyRocketConfig
// sky130_sram_1rw1r_64x256_8 macro wrapper
module data_arrays_0_ext(
  input  [11:0] RW0_addr,
  input         RW0_clk,
  input  [7:0]  RW0_wdata,
  output [7:0]  RW0_rdata,
  input         RW0_en,
  input         RW0_wmode,
  input  [0:0]  RW0_wmask
);
  wire csb0 = ~RW0_en;
  wire web0 = ~RW0_wmode;
  sky130_sram_1rw1r_64x256_8 u_sram (
    .clk0(RW0_clk), .csb0(csb0), .web0(web0),
    .wmask0({1'b1,RW0_wmask}), .addr0(RW0_addr[7:0]),
    .din0({1'b0,RW0_wdata}), .dout0(RW0_rdata),
    .clk1(RW0_clk), .csb1(1'b1), .addr1(8'b0), .dout1()
  );
endmodule

module tag_array_0_ext(
  input  [5:0]  RW0_addr,
  input         RW0_clk,
  input  [20:0] RW0_wdata,
  output [20:0] RW0_rdata,
  input         RW0_en,
  input         RW0_wmode
);
  wire csb0 = ~RW0_en;
  wire web0 = ~RW0_wmode;
  sky130_sram_1rw1r_44x64_8 u_sram (
    .clk0(RW0_clk), .csb0(csb0), .web0(web0),
    .wmask0(1'b1), .addr0(RW0_addr),
    .din0({23'b0,RW0_wdata}), .dout0(RW0_rdata),
    .clk1(RW0_clk), .csb1(1'b1), .addr1(6'b0), .dout1()
  );
endmodule
VEOF
echo "SRAM override written: $(wc -l < "$SRAM_OV") lines"
```

### Step 5 -- Detect Clock Port and Generate Config

```bash
# Detect clock port from Verilog
CLOCK_PORT=$(grep -oE 'input\s+.*\sclock' "$NOSRAM_V" | head -1 | awk '{print $NF}')
CLOCK_PORT="${CLOCK_PORT:-clock}"
echo "Clock port: $CLOCK_PORT"

# Detect PnR top module (tile level, not ChipTop)
PNR_TOP=$(grep -oE 'module [A-Za-z0-9_]*Tile\b' "$NOSRAM_V" 2>/dev/null | head -1 | sed 's/^module //')
PNR_TOP="${PNR_TOP:-ChipTop}"
echo "PnR top: $PNR_TOP"
```

### Step 6 -- Run ORFS PnR via Docker

Run multi-stage PnR inside `openroad/orfs` Docker:

```bash
docker run --rm \
  -v "$WORK_DIR:/workdir" \
  -v "$NOSRAM_V:/nosram.v:ro" \
  -v "$SRAM_OV:/sram_override.v:ro" \
  -w /OpenROAD-flow-scripts/flow \
  openroad/orfs:latest \
  bash -c "
set -e
PDK=/OpenROAD-flow-scripts/flow/platforms/sky130hd
OUT=/workdir/orfs_results
SRAM_DIR=/OpenROAD-flow-scripts/flow/platforms/sky130ram
mkdir -p \$OUT/results/sky130hd/tinyRocket/base
mkdir -p \$OUT/reports/sky130hd/tinyRocket/base
mkdir -p \$OUT/logs/sky130hd/tinyRocket/base
mkdir -p \$OUT/objects/sky130hd/tinyRocket/base

# Write SDC
cat > /workdir/constraint.sdc << SDC
create_clock -period 10 -name clock [get_ports clock]
set_input_delay 0.0 -clock clock [all_inputs]
set_output_delay 0.0 -clock clock [all_outputs]
SDC

# Write config.mk
cat > /workdir/config.mk << MK
export DESIGN_NAME = TinyRocket
export PLATFORM    = sky130hd
export VERILOG_FILES = /nosram.v /sram_override.v
export CORE_UTILIZATION = 50
export PLACE_DENSITY = 0.65
export TNS_END_PERCENT = 100
export GPL_TIMING_DRIVEN = 1
export GPL_ROUTABILITY_DRIVEN = 1
export SYNTH_HIERARCHICAL = 1
export ABC_AREA = 1
export SKIP_ANTENNA_REPAIR_POST_DRT = 1
export NUM_CORES = 4
export PWR_NETS_VOLTAGES =
export GND_NETS_VOLTAGES =
MK

echo '=== Running ORFS PnR ==='
make DESIGN_CONFIG=/workdir/config.mk DESIGN_HOME=/workdir PLATFORM=sky130hd synth && echo 'SYNTH OK'
make DESIGN_CONFIG=/workdir/config.mk DESIGN_HOME=/workdir PLATFORM=sky130hd floorplan && echo 'FLOORPLAN OK'
make DESIGN_CONFIG=/workdir/config.mk DESIGN_HOME=/workdir PLATFORM=sky130hd place && echo 'PLACE OK'
make DESIGN_CONFIG=/workdir/config.mk DESIGN_HOME=/workdir PLATFORM=sky130hd cts && echo 'CTS OK'
make DESIGN_CONFIG=/workdir/config.mk DESIGN_HOME=/workdir PLATFORM=sky130hd route && echo 'ROUTE OK'
make DESIGN_CONFIG=/workdir/config.mk DESIGN_HOME=/workdir PLATFORM=sky130hd finish && echo 'FINISH OK'

echo '=== PPA Results ==='
cat /workdir/orfs_results/reports/sky130hd/tinyRocket/base/6_final.rpt 2>/dev/null || echo 'Report not found'
"
```

**Timeout:** 600000ms (10 minutes).

### Step 7 -- Extract and Report Results

After Docker completes:

```bash
RPT_DIR="$WORK_DIR/orfs_results/reports/sky130hd/tinyRocket/base"
LOG_DIR="$WORK_DIR/orfs_results/logs/sky130hd/tinyRocket/base"

if [ -f "$RPT_DIR/6_final.rpt" ]; then
    echo "=== PPA Report ==="
    cat "$RPT_DIR/6_final.rpt"
else
    echo "No final report found. Check logs:"
    ls "$LOG_DIR/" 2>/dev/null | head -10
fi

if [ -f "$WORK_DIR/orfs_results/results/sky130hd/tinyRocket/base/6_final.gds" ]; then
    echo ""
    echo "GDS: $(ls -lh $WORK_DIR/orfs_results/results/sky130hd/tinyRocket/base/6_final.gds | awk '{print $5}')"
fi
```

## Anti-Patterns

- DO NOT use local paths inside Docker -- use `/OpenROAD-flow-scripts/flow` paths
- DO NOT run ORFS on host -- always inside `openroad/orfs` Docker container
- DO NOT skip nosram preprocessing -- behavioral SRAM modules cause OOM
- DO NOT use `SWAP_ARITH_OPERATORS=1` -- causes ABC crash on large designs
- DO NOT set `NUM_CORES` > 4 on systems with < 16GB RAM