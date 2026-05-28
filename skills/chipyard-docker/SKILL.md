---
name: chipyard-docker
description: "Docker Chipyard flow: generate RTL from a Chipyard config via Docker, run SRAM mapping, stage artifacts into MyDesign, and hand off to PnR."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
---

# chip-agent:chipyard-docker

Unified Chipyard frontend flow: generate RTL from the `ucbbar/chipyard-image` Docker image, run SRAM mapping analysis, stage all artifacts into the ChipAgent workspace, and hand off to `/chip-agent:chipyard-pnr`.

## Docker Strategy

All Chipyard operations run **inside Docker containers** with local filesystem volumes mounted via `-v`:

| Volume | Container Path | Host Path | Purpose |
|--------|---------------|-----------|---------|
| Output | `/out` | `<PLUGIN_ROOT>/MyDesign` | Staging generated Verilog to local workspace |
| Chipyard | `/chipyard` | `/root/chipyard` (in container) | Read-only source |
| ORFS | `/orfs` | `/OpenROAD-flow-scripts` (in orfs container) | Read sky130hd PDK |

## Usage

```
/chip-agent:chipyard tinyrocket
```

## Pipeline

### Step 0 -- Parse Arguments and Normalize

```bash
PLUGIN_ROOT="<project-root>"
RAW_CONFIG="$ARGUMENTS"
```

Normalize:
- `tinyrocket` -> `TinyRocketConfig`
- `TinyRocket` -> `TinyRocketConfig`
- `TinyRocketConfig` -> `TinyRocketConfig`
- If empty, default to `TinyRocketConfig`

```bash
if [ -z "$RAW_CONFIG" ]; then
    CONFIG="TinyRocketConfig"
elif echo "$RAW_CONFIG" | grep -qE '[A-Z]'; then
    if echo "$RAW_CONFIG" | grep -qE 'Config$'; then
        CONFIG="$RAW_CONFIG"
    else
        CONFIG="${RAW_CONFIG}Config"
    fi
else
    FIRST=$(echo "${RAW_CONFIG:0:1}" | tr '[:lower:]' '[:upper:]')
    CONFIG="${FIRST}${RAW_CONFIG:1}Config"
fi
```

Display:
```
=== Chipyard Unified Flow (Docker) ===
Config: $CONFIG
```

### Step 1 -- Verify Environment

**Use ucbbar/chipyard-image Docker to verify:**

```bash
docker run --rm \
  ucbbar/chipyard-image:latest \
  bash -c "
    echo 'Chipyard: /root/chipyard'
    test -f /root/chipyard/build.sbt && echo '  build.sbt: OK' || echo '  build.sbt: MISSING'
    test -d /root/chipyard/generators && echo '  generators: OK'
    java -version 2>&1 | head -1
    sbt --version 2>&1 | tail -1
  "
```

Also verify ORFS via openroad/orfs Docker:

```bash
docker run --rm openroad/orfs:latest \
  bash -c "
    echo 'ORFS: /OpenROAD-flow-scripts'
    test -f /OpenROAD-flow-scripts/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib && echo '  sky130hd: OK' || echo '  sky130hd: MISSING'
  "
```

### Step 2 -- Validate Config Exists

**Run inside Chipyard Docker:**

```bash
docker run --rm \
  ucbbar/chipyard-image:latest \
  bash -c "grep -r 'class ${CONFIG}\b' /root/chipyard/generators/ --include='*.scala' -l 2>/dev/null"
```

If not found, list available configs:
```bash
docker run --rm ucbbar/chipyard-image:latest \
  bash -c "grep -r 'class \w\+Config extends Config' /root/chipyard/generators/chipyard/src/main/scala/config/ --include='*.scala' -h 2>/dev/null | sed 's/class /  - /;s/ extends.*//'"
```

### Step 3 -- Generate Verilog (Docker, with volume mount)

**Run Chipyard elaboration inside Docker, mount output directory:**

```bash
CONFIG="TinyRocketConfig"
PLUGIN_ROOT="/home/sh/snap/worklib/test/ChipAgent"

docker run --rm \
  -v "${PLUGIN_ROOT}/MyDesign:/out" \
  -w /root/chipyard \
  ucbbar/chipyard-image:latest \
  bash -c "
    export JAVA_TOOL_OPTIONS='-Dfile.encoding=UTF-8 -Xmx8G'
    export PATH=/root/chipyard/.conda-env/bin:\$PATH

    cd /root/chipyard

    # Run sbt to generate Verilog
    sbt --batch 'runMain chipyard.Generator --target-dir /out/gen-tmp --top-name ${CONFIG} --split-modules false' 2>&1 | tail -50

    echo '=== SBT DONE ==='
    ls -la /out/gen-tmp/ 2>/dev/null || echo 'No output dir'
  "
```

**Timeout:** 600000ms (10 minutes). Chipyard elaboration is slow.

**Important:** The `ucbbar/chipyard-image` entrypoint is `chipyard/scripts/entrypoint.sh` which may run the harness simulator. Use `--entrypoint bash` to bypass it and run sbt directly.

### Step 4 -- Locate Output Artifacts

**After Docker generation, check mounted output:**

```bash
ls "${PLUGIN_ROOT}/MyDesign/gen-tmp/" 2>/dev/null | head -10
```

The output goes to `/out/gen-tmp/` inside the container, which maps to `${PLUGIN_ROOT}/MyDesign/gen-tmp/` on the host.

Expected output structure:
```
gen-tmp/
├── ChipTop.sv
├── DigitalTop.sv
├── RocketTile.sv (or similar tile)
├── mems.conf
└── ...
```

If `ChipTop.sv` is missing, STOP with error.

### Step 5 -- SRAM Mapping Analysis

**Run inside Chipyard Docker (or locally from the mounted files):**

Read memory config and compute sky130hd mapping. Since the files are now on the local filesystem, you can grep them locally or via Docker:

```bash
GEN_DIR="${PLUGIN_ROOT}/MyDesign/gen-tmp"
MEMS_CONF="${GEN_DIR}/mems.conf"
```

Analyze memories and generate `sram_mapping.json` locally (the files are now on the host at `${PLUGIN_ROOT}/MyDesign/gen-tmp/`):

**5a. Read memory config:**
```bash
cat "$MEMS_CONF" 2>/dev/null || echo "No mems.conf"
```

**5b. Identify memory modules:**
```bash
grep -rn 'reg \[.*\] \w\+\[0:' "$GEN_DIR"/*.sv 2>/dev/null | head -20
grep -rn 'module.*_ext\b' "$GEN_DIR"/*.sv 2>/dev/null | head -10
```

**5c. Generate mapping:**

Use the standard mapping template for TinyRocketConfig:

| RTL Module | Depth x Width | Ports | Strategy | Macro | Tiles |
|------------|---------------|-------|----------|-------|-------|
| data_arrays_0_ext | 4096x32 | mrw (mask_gran=8) | multi_macro_tiling | sky130_sram_1rw1r_128x256_8 | 64 |
| tag_array_0_ext | 64x21 | rw | sram_macro | sky130_sram_1rw1r_44x64_8 | 1 |
| rf_combMem | 31x32 | 2R+1W | standard_cell | null | null |
| ram_combMem_* | varies | 1RW | standard_cell | null | null |

**5d. Write mapping config:**

```bash
cat > "$GEN_DIR/sram_mapping.json" << 'JSONEOF'
{
  "process": "sky130hd",
  "source_config": "TinyRocketConfig",
  "mappings": [
    {"rtl_module": "data_arrays_0_ext", "depth": 4096, "width": 32, "ports": "mrw", "mask_gran": 8, "strategy": "multi_macro_tiling", "macro": "sky130_sram_1rw1r_128x256_8", "tiles": 64, "rationale": "Byte-lane decomposition: 4x8-bit lanes x 16 depth-tiles"},
    {"rtl_module": "tag_array_0_ext", "depth": 64, "width": 21, "ports": "rw", "strategy": "sram_macro", "macro": "sky130_sram_1rw1r_44x64_8", "tiles": 1, "rationale": "Direct match, use lower 21 of 44 data bits"},
    {"rtl_module": "rf_combMem", "depth": 31, "width": 32, "ports": "2R+1W", "strategy": "standard_cell", "rationale": "Dual-port register file"},
    {"rtl_module": "ram_combMem_*", "ports": "1RW", "strategy": "standard_cell", "rationale": "Small FIFO buffers"}
  ]
}
JSONEOF
```

### Step 6 -- Stage Artifacts into MyDesign

```bash
PLUGIN_ROOT="/home/sh/snap/worklib/test/ChipAgent"
CONFIG="TinyRocketConfig"
GEN_DIR="${PLUGIN_ROOT}/MyDesign/gen-tmp"
DEST="${PLUGIN_ROOT}/MyDesign/${CONFIG}/workspace/generated"

mkdir -p "$DEST"

# Concatenate SV files with ChipTop.sv FIRST
cat "$GEN_DIR/ChipTop.sv" "$GEN_DIR/DigitalTop.sv" > "$DEST/${CONFIG}.v" 2>/dev/null

# Append remaining SV files
for f in "$GEN_DIR"/*.sv "$GEN_DIR"/*.v; do
    case "$(basename "$f")" in
        ChipTop.sv|DigitalTop.sv) ;;
        *) cat "$f" >> "$DEST/${CONFIG}.v" 2>/dev/null ;;
    esac
done

# Copy supporting files
cp "$GEN_DIR/mems.conf" "$DEST/" 2>/dev/null
cp "$GEN_DIR/sram_mapping.json" "$DEST/" 2>/dev/null

# Remove temp directory
rm -rf "${PLUGIN_ROOT}/MyDesign/gen-tmp"

echo "Staged: $DEST/${CONFIG}.v ($(wc -l < "$DEST/${CONFIG}.v" 2>/dev/null || echo '?') lines)"
```

Write spec.json:

```bash
# Detect PnR top module
TILE_MODULE=$(grep -oE 'module [A-Za-z0-9_]*Tile\b' "$DEST/${CONFIG}.v" 2>/dev/null | sed 's/^module //' | sort -u | grep -x 'RocketTile' || grep -oE 'module [A-Za-z0-9_]*Tile\b' "$DEST/${CONFIG}.v" 2>/dev/null | head -1 | sed 's/^module //')
PNR_TOP="${TILE_MODULE:-ChipTop}"

cat > "$PLUGIN_ROOT/MyDesign/${CONFIG}/workspace/spec.json" << SPECEOF
{
  "module_name": "$CONFIG",
  "source": "chipyard",
  "top_module": "ChipTop",
  "pnr_top_module": "$PNR_TOP",
  "clock_port": "clock",
  "clock_period_ns": 10,
  "chipyard_config": "$CONFIG",
  "chipyard_path": "/root/chipyard",
  "generated_from": "Docker ucbbar/chipyard-image"
}
SPECEOF
```

### Step 7 -- Verify and Report

```bash
test -f "$DEST/${CONFIG}.v" && echo "OK: Verilog staged ($(wc -l < "$DEST/${CONFIG}.v") lines)"
test -f "$DEST/sram_mapping.json" && echo "OK: SRAM mapping staged"
test -f "$DEST/mems.conf" && echo "OK: mems.conf staged"
test -f "$PLUGIN_ROOT/MyDesign/${CONFIG}/workspace/spec.json" && echo "OK: spec.json created"
```

```
=== Chipyard Flow Complete ===

Config:        TinyRocketConfig
Source:        Docker ucbbar/chipyard-image (sbt elaboration)
Staged to:     MyDesign/TinyRocketConfig/workspace/generated/

Next step:
  /chip-agent:chipyard-pnr tinyrocket
```

## Anti-Patterns

- DO NOT copy Chipyard Docker image to local filesystem -- use `-v` mounts instead
- DO NOT run sbt without `--batch` -- it will hang waiting for interactive input
- DO NOT skip the SRAM mapping step -- required for `/chip-agent:chipyard-pnr`
- DO NOT use `--entrypoint` with the default chipyard entrypoint script -- bypass it with `bash -c "..."`
- DO NOT assume local paths for Chipyard/ORFS -- use Docker paths (`/root/chipyard`, `/OpenROAD-flow-scripts`)