---
name: chipyard-local
description: "Local Chipyard flow: generate RTL from a local Chipyard installation, run SRAM mapping, stage artifacts into MyDesign, and hand off to PnR."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
  - mcp__chipagent-backend__check_environment
  - mcp__chipagent-backend__generate_config
---

# chip-agent:chipyard-local

Local Chipyard frontend flow: generate RTL from a local Chipyard installation, run SRAM mapping analysis, stage all artifacts into the ChipAgent workspace, and hand off to `/chip-agent:pnr`.

## Usage

```
/chip-agent:chipyard-local <config>
```

**Example:**

```
/chip-agent:chipyard-local tinyrocket
/chip-agent:chipyard-local TinyRocketConfig
```

## Instructions

**Determine the project root directory** from the user's current working project (the directory containing `scripts/` and `chisel-project/`; `MyDesign/` is created on first use), not from the skill's installation location. Use that directory as the base for all relative paths below.

## Pipeline

### Step 0 -- Parse Arguments and Normalize

```bash
PROJECT_ROOT="<project-root>"
RAW_CONFIG="$ARGUMENTS"
```

Normalize the config name:
- If the argument contains no uppercase letters and no `Config` suffix, capitalize the first letter and append `Config`.
- Examples: `tinyrocket` -> `TinyRocketConfig`, `TinyRocket` -> `TinyRocketConfig`, `TinyRocketConfig` -> `TinyRocketConfig`
- If the argument is empty, default to `TinyRocketConfig`.

```bash
# Normalization logic (pseudo-code, execute as bash)
if [ -z "$RAW_CONFIG" ]; then
    CONFIG="TinyRocketConfig"
elif echo "$RAW_CONFIG" | grep -qE '[A-Z]'; then
    # Already has uppercase -- assume user knows what they're doing
    if echo "$RAW_CONFIG" | grep -qE 'Config$'; then
        CONFIG="$RAW_CONFIG"
    else
        CONFIG="${RAW_CONFIG}Config"
    fi
else
    # All lowercase -- capitalize first letter and append Config
    FIRST=$(echo "${RAW_CONFIG:0:1}" | tr '[:lower:]' '[:upper:]')
    REST="${RAW_CONFIG:1}"
    CONFIG="${FIRST}${REST}Config"
fi
```

Display:
```
=== Chipyard Unified Flow (Local) ===
Config: $CONFIG
```

### Step 1 -- Verify Environment

Read `$PROJECT_ROOT/.chipagent/env.json`. Extract:
- `chipyard.path` -> `CHIPYARD_DIR`
- `chipyard.riscv_path` -> `RISCV`
- `orfs.flow_path` -> `ORFS_FLOW_PATH`

If `chipyard.installed` is not `true`, STOP with:
```
Chipyard installation not detected.
Install Chipyard or set the path in .chipagent/env.json.
```

If `orfs.installed` is not `true`, STOP with:
```
ORFS not installed. PnR handoff requires OpenROAD-flow-scripts.
```

Call `mcp__chipagent-backend__check_environment` to verify ORFS/sky130hd readiness.

Verify Chipyard directory:
```bash
test -d "$CHIPYARD_DIR" && test -f "$CHIPYARD_DIR/build.sbt"
```

If invalid, STOP with clear error.

### Step 2 -- Validate Config Exists

```bash
grep -r "class ${CONFIG}\b" "$CHIPYARD_DIR/generators/" --include="*.scala" -l
```

If not found, list available configs:
```bash
grep -r "class \w\+Config extends Config" "$CHIPYARD_DIR/generators/chipyard/src/main/scala/config/" --include="*.scala" -h | sed 's/class /  - /;s/ extends.*//'
```

STOP with: `Config '<ConfigName>' not found. Available configs listed above.`

### Step 3 -- Generate Verilog

Run Chipyard Verilog generation:

```bash
cd "$CHIPYARD_DIR/sims/verilator" && \
export RISCV="$CHIPYARD_DIR/.conda-env/riscv-tools" && \
export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8" && \
export PATH="$CHIPYARD_DIR/.conda-env/bin:$PATH" && \
make verilog CONFIG="$CONFIG" ENABLE_YOSYS_FLOW=1 2>&1 | tail -80
```

**Timeout:** 600000ms (10 minutes). Chipyard elaboration is slow.

**`ENABLE_YOSYS_FLOW=1` is mandatory.** It appends `disallowPackedArrays` to firtool's MFC lowering options (see `$CHIPYARD_DIR/common.mk` around line 212). Without it, firtool emits SystemVerilog packed-array assignment patterns like `wire [2:0][8:0] _GEN = '{9'h0, 9'h0, 9'h0}`, which yosys cannot parse (`ERROR: syntax error, unexpected OP_CAST`) and ORFS synthesis aborts in `1_1_yosys_canonicalize`. The flag only changes emit lowering -- functional behavior and module hierarchy are unchanged.

**Error handling:**
- `firtool: command not found` -> ensure `$CHIPYARD_DIR/.conda-env/bin` is in PATH
- `RISCV is unset` -> export `RISCV=$CHIPYARD_DIR/.conda-env/riscv-tools`
- sbt failure -> show error, suggest `cd $CHIPYARD_DIR && sbt --batch "compile"`

### Step 4 -- Locate Output Artifacts

```bash
GEN_BASE="$CHIPYARD_DIR/sims/verilator/generated-src/chipyard.harness.TestHarness.$CONFIG"
GEN_DIR="$GEN_BASE/gen-collateral"
MEMS_CONF="$GEN_BASE/chipyard.harness.TestHarness.$CONFIG.mems.conf"
```

Verify:
```bash
test -d "$GEN_DIR" && echo "Found gen-collateral: $(ls "$GEN_DIR"/*.sv 2>/dev/null | wc -l) SV files"
test -f "$GEN_DIR/ChipTop.sv" && echo "Top module: ChipTop.sv"
test -f "$MEMS_CONF" && echo "Memory config: $MEMS_CONF"
```

If `ChipTop.sv` is missing, STOP with:
```
ChipTop.sv not found in generated output.
Generation may have failed or used a different top module.
```

### Step 5 -- Run SRAM Mapping Analysis

Execute the SRAM mapping analysis inline (same logic as `/chip-agent:sram-mapping`):

**5a. Read memory config:**
```bash
cat "$MEMS_CONF"
```

**5b. Identify memory modules:**
```bash
# Find behavioral memories
grep -rn 'reg \[.*\] \w\+\[0:' "$GEN_DIR"/*.sv 2>/dev/null | head -20

# Find register file modules
grep -rn "module rf_combMem" "$GEN_DIR"/*.sv 2>/dev/null

# Count FIFO memories
ls "$GEN_DIR"/ram_combMem*.sv 2>/dev/null | wc -l
```

**5c. Scan for available sky130hd SRAM macros:**
```bash
ORFS_PLATFORMS="$ORFS_FLOW_PATH/platforms"
if [ -d "$ORFS_PLATFORMS/sky130ram" ]; then
    ls "$ORFS_PLATFORMS"/sky130ram/sky130_sram_*/ 2>/dev/null | head -20
else
    echo "No sky130ram macros found in ORFS platforms"
fi
```

**5d. Compute mapping** per the decision rules:

Decision rules (in priority order):

1. **Dual-port memories (2R+1W, 2RW):** Always standard-cell DFF -- no sky130 macro supports multi-port.
2. **Depth <= 8:** Standard-cell DFF -- too small to benefit from SRAM.
3. **FIFO/Queue (ram_combMem*):** Standard-cell DFF -- typically small and simple.
4. **Register file (rf_combMem):** Standard-cell DFF -- dual-port, no matching macro.
5. **Cache SRAM (_ext modules) with compatible ports:**
   - **Direct macro match:** depth <= macro_max_depth AND width <= macro_width -> `strategy: "sram_macro"`, set `macro` and `tiles: 1`
   - **Depth tiling:** depth > macro_max_depth AND port compatible -> `strategy: "multi_macro_tiling"`, compute `tiles = ceil(depth / macro_depth)`, set `macro`
   - **Width + depth tiling:** depth > macro_max_depth AND width > macro_width -> `strategy: "multi_macro_tiling"`, compute both width and depth tiles, set `macro`
   - **Width waste only matters for small memories:** width waste > 50% is acceptable for large-depth memories (tiling amortizes the overhead)

**IMPORTANT on port compatibility:**
- `sky130_sram_1rw1r_*` macros have port type `1rw1r` (1 read-write + 1 read-only port)
- These macros support byte-level write masking via `wmask0` -- so `mrw` (masked read-write) IS compatible
- The 1rw1r port can serve masked 1RW by using port 0 (read-write with wmask) and leaving port 1 (read-only) disabled (csb1=1)
- Therefore: `rw`, `mrw`, and `1rw` port types are ALL compatible with `sky130_sram_1rw1r_*` macros

**Mapping template for each _ext memory:**

For each `_ext` module identified in mems.conf:
1. Determine depth, width, ports, mask_gran from mems.conf
2. If ports contain "2R" or "2RW" -> standard_cell
3. Otherwise, find the best-fit sky130_sram_1rw1r macro:
   - Prefer macros where `macro_depth >= depth` (direct match, no tiling)
   - For depth > any macro depth, choose macro with largest depth and compute tiles
   - For width, choose macro with `macro_width >= width` (use lower bits of data bus)
4. Set `strategy`, `macro`, `tiles`, and `rationale` in the mapping

**Example mapping for TinyRocketConfig:**

| RTL Module | Depth x Width | Ports | Strategy | Macro | Tiles |
|------------|---------------|-------|----------|-------|-------|
| data_arrays_0_ext | 4096x32 | mrw (mask_gran=8) | multi_macro_tiling | sky130_sram_1rw1r_128x256_8 | 16 per byte_lane × 4 lanes = 64 |
| tag_array_0_ext | 64x21 | rw | sram_macro | sky130_sram_1rw1r_44x64_8 | 1 |
| data_arrays_0_0_ext | 1024x32 | rw | multi_macro_tiling | sky130_sram_1rw1r_128x256_8 | 4 |
| rf_combMem | 31x32 | 2R+1W | standard_cell | null | null |
| ram_combMem_* | varies | 1RW | standard_cell | null | null |

**5e. Present formatted report** showing each memory with its mapping strategy.

**5f. Write mapping config:**
```bash
cat > "$GEN_DIR/sram_mapping.json" << 'JSONEOF'
{
  "process": "sky130hd",
  "source_config": "<CONFIG>",
  "available_macros": [
    {"name": "sky130_sram_1rw1r_128x256_8", "depth": 256, "width": 128, "ports": "1rw1r"},
    {"name": "sky130_sram_1rw1r_64x256_8",  "depth": 256, "width": 64,  "ports": "1rw1r"},
    {"name": "sky130_sram_1rw1r_80x64_8",   "depth": 64,  "width": 80,  "ports": "1rw1r"},
    {"name": "sky130_sram_1rw1r_44x64_8",   "depth": 64,  "width": 44,  "ports": "1rw1r"}
  ],
  "mappings": [
    {
      "rtl_module": "data_arrays_0_ext",
      "depth": 4096,
      "width": 32,
      "ports": "mrw",
      "mask_gran": 8,
      "strategy": "multi_macro_tiling",
      "macro": "sky130_sram_1rw1r_128x256_8",
      "tiles": 64,
      "tiling_detail": "4 byte_lanes x 16 depth_tiles",
      "rationale": "Byte-lane decomposition: 4x8-bit lanes, each depth-tiled 16 ways (4096/256)"
    },
    {
      "rtl_module": "tag_array_0_ext",
      "depth": 64,
      "width": 21,
      "ports": "rw",
      "mask_gran": null,
      "strategy": "sram_macro",
      "macro": "sky130_sram_1rw1r_44x64_8",
      "tiles": 1,
      "tiling_detail": null,
      "rationale": "Direct match: depth 64 matches macro depth, use lower 21 of 44 data bits"
    },
    {
      "rtl_module": "data_arrays_0_0_ext",
      "depth": 1024,
      "width": 32,
      "ports": "rw",
      "mask_gran": null,
      "strategy": "multi_macro_tiling",
      "macro": "sky130_sram_1rw1r_128x256_8",
      "tiles": 4,
      "tiling_detail": "4 depth_tiles, use lower 32 of 128 data bits",
      "rationale": "Depth tiling: 1024/256=4 tiles, width waste acceptable for large memory"
    },
    {
      "rtl_module": "rf_combMem",
      "depth": 31,
      "width": 32,
      "ports": "2R+1W",
      "strategy": "standard_cell",
      "macro": null,
      "tiles": null,
      "rationale": "Dual-port register file; no matching sky130 macro"
    },
    {
      "rtl_module": "ram_combMem_*",
      "depth": "varies",
      "width": "varies",
      "ports": "1RW",
      "count": 16,
      "strategy": "standard_cell",
      "macro": null,
      "tiles": null,
      "rationale": "Small FIFO buffers; standard-cell DFF"
    }
  ]
}
JSONEOF
```

**IMPORTANT:** The `mappings` array must include `macro` and `tiles` fields for any memory with `strategy: "sram_macro"` or `strategy: "multi_macro_tiling"`. These fields are required by `/chip-agent:chipyard-pnr` Step 3 to generate SRAM override Verilog. For `multi_macro_tiling`, also include `tiling_detail` describing the decomposition (e.g., "4 byte_lanes x 16 depth_tiles").

### Step 6 -- Stage Artifacts into MyDesign

Create the ChipAgent workspace structure for downstream PnR:

```bash
DEST="$PROJECT_ROOT/MyDesign/$CONFIG/workspace/generated"
mkdir -p "$DEST"

# Concatenate SV files with ChipTop.sv FIRST so the top module appears first
# (ORFS/MCP backend detects DESIGN_NAME from the first `module` declaration)
cat "$GEN_DIR/ChipTop.sv" "$GEN_DIR"/DigitalTop.sv > "$DEST/${CONFIG}.v"
# Append remaining SV files (excluding ChipTop and DigitalTop already included)
for f in "$GEN_DIR"/*.sv "$GEN_DIR"/*.v; do
    case "$(basename "$f")" in
        ChipTop.sv|DigitalTop.sv) ;; # already included
        *) cat "$f" >> "$DEST/${CONFIG}.v" ;;
    esac
done
echo "Staged: $DEST/${CONFIG}.v ($(wc -l < "$DEST/${CONFIG}.v") lines)"

# Copy memory config
cp "$MEMS_CONF" "$DEST/mems.conf" 2>/dev/null

# Copy SRAM mapping
cp "$GEN_DIR/sram_mapping.json" "$DEST/sram_mapping.json" 2>/dev/null
```

Write a spec.json for the PnR flow:

```bash
# Determine the PnR top module: NOT ChipTop (which includes TestHarness),
# but the tile-level module (e.g. RocketTile for Rocket configs)
PNR_TOP_MODULE="ChipTop"  # default; will be overridden for known configs

# Auto-detect tile module from the Verilog hierarchy
# For Rocket-based configs, the tile module is typically *Tile
TILE_MODULE=$(grep -oE 'module [A-Za-z0-9_]*Tile\b' "$DEST/${CONFIG}.v" 2>/dev/null | head -1 | sed 's/^module //')
# If multiple *Tile modules found, prefer "RocketTile" for Rocket configs, otherwise pick the shortest
if [ -n "$(grep -oE 'module [A-Za-z0-9_]*Tile\b' "$DEST/${CONFIG}.v" 2>/dev/null)" ]; then
    TILE_CANDIDATES=$(grep -oE 'module [A-Za-z0-9_]*Tile\b' "$DEST/${CONFIG}.v" 2>/dev/null | sed 's/^module //' | sort -u)
    # Prefer exact "RocketTile" if present, else pick the shortest candidate
    if echo "$TILE_CANDIDATES" | grep -qx 'RocketTile'; then
        TILE_MODULE="RocketTile"
    else
        TILE_MODULE=$(echo "$TILE_CANDIDATES" | awk '{print length, $0}' | sort -n | head -1 | awk '{print $2}')
    fi
fi
if [ -n "$TILE_MODULE" ]; then
    PNR_TOP_MODULE="$TILE_MODULE"
    echo "Auto-detected PnR top module: $PNR_TOP_MODULE"
fi

cat > "$PROJECT_ROOT/MyDesign/$CONFIG/workspace/spec.json" << SPECEOF
{
  "module_name": "$CONFIG",
  "source": "chipyard",
  "top_module": "ChipTop",
  "pnr_top_module": "$PNR_TOP_MODULE",
  "clock_port": "clock",
  "clock_period_ns": 10,
  "chipyard_config": "$CONFIG",
  "chipyard_path": "$CHIPYARD_DIR",
  "generated_from": "$GEN_DIR"
}
SPECEOF
```

**NOTE:** `top_module` is `ChipTop` (the Chipyard elaboration top), while `pnr_top_module` is the tile-level module used for PnR synthesis (e.g., `RocketTile`). The `chipyard-pnr` skill uses `pnr_top_module` as the `DESIGN_NAME` in ORFS config.

### Step 7 -- Verify Staging and Hand Off

Verify the staged artifacts:
```bash
test -f "$DEST/${CONFIG}.v" && echo "OK: Verilog staged"
test -f "$PROJECT_ROOT/MyDesign/$CONFIG/workspace/spec.json" && echo "OK: spec.json created"
wc -l "$DEST/${CONFIG}.v"
```

Present the final report:

```
=== Chipyard Flow Complete (Local) ===

Config:        <CONFIG>
Source:        <GEN_DIR>
Staged to:     <DEST>/<CONFIG>.v
Top module:    ChipTop
SRAM mapping:  <summary of mapping decisions>

Workspace:
  MyDesign/<CONFIG>/
    workspace/
      generated/<CONFIG>.v   -- flattened Verilog
      generated/mems.conf    -- memory config
      generated/sram_mapping.json
      spec.json              -- PnR metadata

Next step:
  /chip-agent:chipyard-pnr <CONFIG>
```

The handoff is now ready. The user can run `/chip-agent:chipyard-pnr <CONFIG>` (NOT `/chip-agent:pnr`) to start the specialized Chipyard+SRAM PnR flow on the staged Verilog.

**IMPORTANT:** `/chip-agent:pnr` will automatically detect this is a Chipyard design and redirect to `/chip-agent:chipyard-pnr`. Either command works, but `chipyard-pnr` is preferred for clarity.

## Pipeline Stages

| # | Stage | Description |
|---|-------|-------------|
| 0 | Parse & Normalize | Normalize config name, set variables |
| 1 | Verify Environment | Check chipyard, ORFS, sky130hd via env.json |
| 2 | Validate Config | Confirm config class exists in Scala sources |
| 3 | Generate Verilog | Run `make verilog CONFIG=<name>` |
| 4 | Locate Output | Find and verify gen-collateral directory |
| 5 | SRAM Mapping | Analyze memories and compute sky130hd mapping |
| 6 | Stage Artifacts | Copy/flatten RTL into MyDesign workspace |
| 7 | Verify & Hand Off | Confirm staging and print PnR handoff command |

## Input

$ARGUMENTS

A Chipyard config name (e.g., `tinyrocket`, `TinyRocket`, or `TinyRocketConfig`).

## Output

Upon completion:
- Generated Verilog staged in `MyDesign/<Config>/workspace/generated/<Config>.v`
- SRAM mapping analysis in `MyDesign/<Config>/workspace/generated/sram_mapping.json`
- `spec.json` with clock port, period, and top module metadata
- Ready for `/chip-agent:pnr <Config>`

## Anti-Patterns

- DO NOT skip environment verification -- Chipyard requires specific Java, sbt, and firtool versions
- DO NOT run `make verilog` without setting `RISCV` environment variable
- DO NOT use `make -j` -- sbt manages its own parallelism
- DO NOT skip the SRAM mapping step -- it informs floorplanning decisions during PnR
- DO NOT include TestHarness modules in the flattened Verilog -- only include modules under ChipTop
