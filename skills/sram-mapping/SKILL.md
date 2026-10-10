---
name: sram-mapping
description: "Analyze Verilog RTL to identify SRAM macro instances and determine their mapping to sky130hd process SRAM macros or standard-cell alternatives."
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# chip-agent:sram-mapping

Analyze Verilog RTL to identify all SRAM/memory macro instances and determine their mapping to sky130hd process SRAM macros or standard-cell alternatives.

## Usage

```
/chip-agent:sram-mapping <verilog_dir_or_file>
```

**Examples:**

```
/chip-agent:sram-mapping /home/mingzhenjia/Desktop/chipyard/sims/verilator/generated-src/chipyard.harness.TestHarness.TinyRocketConfig/gen-collateral
/chip-agent:sram-mapping MyDesign/ALU8/workspace/generated/ALU8.v
/chip-agent:sram-mapping /path/to/rtl/dir
```

## Instructions

**Determine the project root directory** from the user's current working project (the directory containing `scripts/` and `chisel-project/`; `MyDesign/` is created on first use), not from the skill's installation location. Use that directory as the base for all relative paths below.

## Pipeline

### Step 0 -- Parse Arguments

```bash
INPUT="$ARGUMENTS"  # file or directory
ORFS_PLATFORMS="<project-root>/OpenROAD-flow-scripts/flow/platforms"
```

Validate:
```bash
if [ -d "$INPUT" ]; then
    MODE="dir"
elif [ -f "$INPUT" ]; then
    MODE="file"
else
    echo "ERROR: '$INPUT' not found."
    exit 1
fi
```

### Step 1 -- Identify Memory Modules

Scan all Verilog/SystemVerilog files for memory array declarations and SRAM macro wrappers.

**1a. Find behavioral memories (reg arrays):**

```bash
if [ "$MODE" = "dir" ]; then
    grep -rn 'reg \[.*\] \w\+\[0:' "$INPUT"/*.sv "$INPUT"/*.v 2>/dev/null
else
    grep -n 'reg \[.*\] \w\+\[0:' "$INPUT"
fi
```

For each match, extract:
- **Module name**: enclosing `module ... endmodule`
- **Array dimensions**: `reg [W:0] name [0:D]` -> width = W+1, depth = D+1
- **Ports**: look for read/write signals in the always block

**1b. Find SRAM wrapper modules (mems.conf style):**

Check for memory configuration files:
```bash
find "$(dirname "$INPUT")" -maxdepth 2 -name "*.mems.conf" -exec cat {} \;
```

Each line in mems.conf has format:
```
name <instance> depth <D> width <W> ports <port_type> [mask_gran <G>]
```

Port types:
- `rw` -- single read-write port
- `mrw` -- masked read-write port (byte-level write enable)
- `r` -- read-only port
- `w` -- write-only port

**1c. Find register file modules (rf_combMem style):**

```bash
grep -rn "module rf_combMem\|module rf_" "$INPUT"/*.sv "$INPUT"/*.v 2>/dev/null
```

Register files are multi-port (typically 2R+1W) behavioral memories.

**1d. Find Queue/FIFO memories (ram_combMem style):**

```bash
grep -rn "module ram_combMem" "$INPUT"/*.sv "$INPUT"/*.v 2>/dev/null
```

These are small FIFO buffers with simple 1RW ports.

### Step 2 -- Trace Hierarchy

For each identified memory module, trace its instantiation path up to the top-level module.

```bash
# Find where memory module M is instantiated
grep -rn "\b${MODULE_NAME}\b" "$INPUT"/*.sv "$INPUT"/*.v 2>/dev/null | grep -v "^.*${MODULE_NAME}.sv:" | grep -v "^.*${MODULE_NAME}.v:"
```

Build the hierarchy chain from leaf memory to top module (e.g., `ChipTop > RocketTile > DCache > data_arrays_0 > data_arrays_0_ext`).

### Step 3 -- Enumerate sky130hd SRAM Macros

Scan the local ORFS platform for available SRAM macros:

```bash
if [ -d "$ORFS_PLATFORMS/sky130ram" ]; then
    for d in "$ORFS_PLATFORMS"/sky130ram/sky130_sram_*/; do
        macro=$(basename "$d")
        # Extract interface from Verilog model
        head -30 "$d"/*.v 2>/dev/null | grep -E "module|parameter|input|output"
    done
fi
```

For each macro, extract:
- **Name**: e.g., `sky130_sram_1rw1r_128x256_8`
- **Configuration**: decode from name: `<ports>_<width>x<depth>_<write_width>`
- **Port types**: from Verilog interface
- **Total capacity**: width * depth bits

### Step 4 -- Compute Mapping

For each identified memory in the RTL, compute the best mapping strategy.

**Mapping decision rules (in priority order):**

1. **Dual-port memories (2R+1W, 2RW):** Always standard-cell DFF — no sky130 macro supports multi-port.
2. **Depth <= 8:** Standard-cell DFF — too small to benefit from SRAM.
3. **FIFO/Queue (ram_combMem*):** Standard-cell DFF — typically small and simple.
4. **Register file (rf_combMem):** Standard-cell DFF — dual-port, no matching macro.
5. **Cache SRAM (_ext modules) with compatible ports:**
   - **Direct macro match:** depth <= macro_max_depth AND width <= macro_width → `strategy: "sram_macro"`, set `macro` and `tiles: 1`
   - **Depth tiling:** depth > macro_max_depth AND port compatible → `strategy: "multi_macro_tiling"`, compute `tiles = ceil(depth / macro_depth)`, set `macro`
   - **Width + depth tiling:** depth > macro_max_depth AND width > macro_width → `strategy: "multi_macro_tiling"`, compute both width and depth tiles, set `macro`
   - **Width waste only matters for small memories:** width waste > 50% is acceptable for large-depth memories (tiling amortizes the overhead)

**IMPORTANT on port compatibility:**
- `sky130_sram_1rw1r_*` macros have port type `1rw1r` (1 read-write + 1 read-only port)
- These macros support byte-level write masking via `wmask0` — so `mrw` (masked read-write) IS compatible
- The 1rw1r port can serve masked 1RW by using port 0 (read-write with wmask) and leaving port 1 (read-only) disabled (csb1=1)
- Therefore: `rw`, `mrw`, and `1rw` port types are ALL compatible with `sky130_sram_1rw1r_*` macros

**Mapping template for each _ext memory:**

For each `_ext` module identified in mems.conf:
1. Determine depth, width, ports, mask_gran from mems.conf
2. If ports contain "2R" or "2RW" → standard_cell
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

**Mapping table format:**

For each memory, output:

| RTL Memory | Depth | Width | Ports | Mapping Strategy | sky130 Macro | Tiles | Notes |
|------------|-------|-------|-------|------------------|--------------|-------|-------|

### Step 5 -- Generate Report

Present a formatted report:

```
=== SRAM Mapping Analysis ===

Source: <input path>
Process: sky130hd
Available macros: <N> sky130_sram_* variants

## Memory Instances

### Cache SRAM (Configurable -- replaceable with hard macros)

| # | Module | Depth x Width | Ports | Hierarchy | Mapping |
|---|--------|---------------|-------|-----------|---------|
| 1 | data_arrays_0_ext | 4096x32 | 1RW+mask | ChipTop>...>DCache | <strategy> |
| 2 | tag_array_0_ext | 64x21 | 1RW | ChipTop>...>DCache | <strategy> |
| 3 | data_arrays_0_0_ext | 1024x32 | 1RW | ChipTop>...>ICache | <strategy> |

### Register File

| # | Module | Size | Ports | Mapping |
|---|--------|------|-------|---------|
| 4 | rf_combMem | 31x32 | 2R+1W | Standard-cell DFF |

### Queue/FIFO Buffers

| # | Module | Size | Count | Mapping |
|---|--------|------|-------|---------|
| 5 | ram_combMem_* | 1-256 deep | <N> instances | Standard-cell DFF |

## Mapping Recommendations

<per-memory recommendation with rationale>

## Summary

- Total memory bits: <sum of all depth*width>
- SRAM macro candidates: <N> (list which memories could use macros)
- Standard-cell only: <N> (list which memories must use DFFs)
- Recommended approach: <overall strategy>
```

### Step 6 -- Save Mapping Config

Write a mapping configuration file that can be consumed by downstream PnR flows. In the unified `/chip-agent:chipyard` flow this output should be staged into the module workspace:

```bash
OUTPUT_DIR="<directory containing the analyzed RTL>"
cat > "$OUTPUT_DIR/sram_mapping.json" << 'JSONEOF'
{
  "process": "sky130hd",
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

## Pipeline Stages

| # | Stage | Description |
|---|-------|-------------|
| 0 | Parse Arguments | Validate input file/directory |
| 1 | Identify Memories | Scan for reg arrays, mems.conf, rf_combMem, ram_combMem |
| 2 | Trace Hierarchy | Build instantiation chains from leaf to top |
| 3 | Enumerate Macros | List available sky130hd SRAM macros |
| 4 | Compute Mapping | Apply decision rules for each memory |
| 5 | Generate Report | Present formatted mapping analysis |
| 6 | Save Config | Write sram_mapping.json for downstream use |

## Input

$ARGUMENTS

A path to either:
- A directory of Verilog/SystemVerilog files (e.g., Chipyard gen-collateral directory)
- A single Verilog file

## Output

Upon completion:
- Formatted mapping report displayed in conversation
- `sram_mapping.json` in the input directory (optional)

## Decision Rules Reference

| Condition | Strategy |
|-----------|----------|
| Dual-port (2R+1W, 2RW, etc.) | Standard-cell DFF (no matching macro) |
| Depth <= 8 | Standard-cell DFF (too small to benefit) |
| FIFO/Queue (ram_combMem*) | Standard-cell DFF (typically small, simple) |
| Register file (rf_combMem) | Standard-cell DFF (dual-port, no matching macro) |
| Depth <= macro_depth AND width <= macro_width AND port compatible | Direct SRAM macro (`sram_macro`) |
| Depth > macro_depth AND port compatible (rw, mrw, 1rw) | Multi-macro depth tiling (`multi_macro_tiling`) |
| Width > macro_width AND port compatible | Multi-macro width+depth tiling (`multi_macro_tiling`) |
| Width waste > 50% AND depth small | Consider standard-cell (tiling amortizes overhead for large depth) |

**Port compatibility with sky130_sram_1rw1r_*:** `rw`, `mrw`, and `1rw` are all compatible (macros support byte-level wmask).

## Anti-Patterns

- DO NOT assume all memories can map to SRAM macros -- many are too small or have incompatible ports
- DO NOT ignore `mask_gran` in mems.conf -- byte-masked writes require specific macro support
- DO NOT suggest macro tiling without computing the wrapper overhead (address decode + data mux)
- DO NOT skip the hierarchy trace -- knowing where a memory lives is critical for floorplanning
