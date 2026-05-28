---
name: chipyard-pnr-docker
description: "Docker Chipyard PnR flow: nosram preprocessing, SRAM override generation, multi-round ORFS PnR on sky130hd via Docker containers with adaptive parameter tuning."
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
  - Agent
  - WebSearch
  - WebFetch
  - mcp__chipagent-backend__check_environment
  - mcp__chipagent-backend__generate_config
  - mcp__chipagent-backend__run_stage
  - mcp__chipagent-backend__get_report
  - mcp__chipagent-backend__diagnose_failure
  - mcp__chipagent-backend__clean_design
  - mcp__chipagent-backend__compare_runs
---

# chip-agent:chipyard-pnr-docker

End-to-end Chipyard PnR flow using Docker containers:
1. Find already-generated Verilog from `/chip-agent:chipyard`
2. Generate SRAM override modules (via sram-mapping subagent)
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
/chip-agent:chipyard-pnr-docker <config> [work_dir]
```

**Examples:**

```
/chip-agent:chipyard-pnr-docker tinyrocket
/chip-agent:chipyard-pnr-docker TinyRocketConfig
/chip-agent:chipyard-pnr-docker tinyrocket /path/to/try
/chip-agent:chipyard-pnr-docker tinyrocket 100MHz
/chip-agent:chipyard-pnr-docker tinyrocket 10ns
```

Create the checklist and go on.
```
□ Parse arguments and setup work directory
□ Verify environment (Docker, ORFS, sky130hd)
□ Locate generated Verilog
□ Consolidate split SV files into single nosram.sv
□ Generate SRAM override modules (sram-mapping agent)
□ Identify clock ports from ChipTop
□ Generate ORFS config.mk and constraint.sdc
□ Run multi-round PnR iteration (3 rounds adaptive)
□ Compare rounds and select best result
```

## Instructions

**Determine the project root directory** by finding the nearest ancestor directory of this skill file that contains `.claude`. Use that directory as the base for all relative paths below.

## Critical Pitfalls (READ FIRST)

These are non-obvious failure modes discovered through production runs. **Every one of these will cause the flow to fail silently or catastrophically if ignored.**

### Pitfall 0: TinyRocket default caches overflow 16 GB RAM at PDN (CRITICAL)

**Problem:** Default `With1TinyCore` uses D$ nSets=256 (16 KB scratchpad) and I$ nSets=64 (4 KB). This produces behavioral arrays of depth **4096** (D$ data) and **1024** (I$ data). sky130 SRAM macros max out at 256 deep, so a faithful mapping needs 16-way and 4-way depth tiling. With ~4 D$ banks × 16 tiles = ~64 macros plus icache/tag → **70+ physical SRAM macros**, die explodes to ~10000×10000 µm, and `pdngen` stdcell grid insertion (`[INFO PDN-0001] Inserting grid: grid`) peaks at **~14 GB RSS** → OOM killed on a 16 GB system.

**Verify the symptom:** the floorplan log dies with `Command terminated by signal 9` immediately after `Inserting grid: grid` (before any macro grid lines). `mems.conf` shows `data_arrays_0_0_ext depth 4096`. `2_2_floorplan_macro.tcl` has 50+ lines.

**Why simplifying PDN does NOT fix it:** the bottleneck is the stdcell met4/met5 stripe graph, which scales with die area. Die area is driven by SRAM macro count. Adding swap also doesn't help — OOM killer triggers on RSS, not virtual memory; swap thrash just delays the kill.

**Solution:** Shrink the Chipyard cache config so each array fits in one sky130 SRAM macro (depth ≤ 256). Edit `generators/rocket-chip/src/main/scala/subsystem/Configs.scala`, change `With1TinyCore`'s `dcache.nSets` from 256→16 and `icache.nSets` from 64→16 (1 KB caches each). After this, `mems.conf` shows depth ≤ 256, override needs only ~6 macros, die ~2551×2551 µm, PDN peak **~4.5 GB**, full flow fits in 7 GB.

Trade-off: 1 KB caches are functional but tiny. Only suitable for baremetal/bringup demos, not Linux. Verified: 50 MHz target → fmax 50.56 MHz, WNS 0, TNS 0, DRC 0, 189 MB GDS, route peak 6.5 GB.

### Pitfall 1: FF-based SRAMs cause OOM in routing (CRITICAL)

**Problem:** If behavioral SRAM modules (`data_arrays_0_0_ext`, etc.) are synthesized to flip-flops, the design explodes from ~100K cells to millions of cells. Detailed routing (`5_2_route`) will be killed by OOM killer (signal 9) at 13+ GB memory.

**Root cause:** `data_arrays_0_0_ext` is 4096x8 = 32,768 flip-flops per instance. With multiple instances, this creates hundreds of thousands of FFs that bloat the design.

**Solution:** Use the **nosram + SRAM override** approach:
1. Use the Chipyard-generated behavioral Verilog as-is (modules are undefined external modules)
2. Provide `sram_override.v` that replaces behavioral SRAMs with `sky130_sram_*` macro instantiations
3. Blackbox the `sky130_sram_*` macros during synthesis via `SYNTH_BLACKBOXES`
4. Provide LEF/LIB/GDS files so OpenROAD can place the physical SRAM macros

**NEVER** provide behavioral SRAM stubs (reg arrays) as substitutes — this causes the OOM problem.

### Pitfall 2: ENABLE_YOSYS_FLOW is mandatory

**Problem:** Without `ENABLE_YOSYS_FLOW=1`, firtool emits SystemVerilog packed-array patterns (`wire [2:0][8:0] _GEN = '{9'h0, ...}`) that Yosys cannot parse, causing `ERROR: syntax error, unexpected OP_CAST` in `1_1_yosys_canonicalize`.

**Solution:** Always pass `ENABLE_YOSYS_FLOW=1` to `make buildfile` or `make verilog`. In Chipyard's `vlsi/tutorial.mk`, the `sky130-openroad` tutorial already sets this flag, but verify it is set.

**What it does** (from `chipyard/common.mk`):
1. Enables SFC LowFIRRTL lowering with `ReplSeqMem` for SRAM extraction
2. Appends `disallowPackedArrays` to MFC lowering options

### Pitfall 3: Duplicate module definitions

**Problem:** If you concatenate `EICG_wrapper.v`, `IOCell.v`, `plusarg_reader.v` files AND they are already in the `top.f` filelist, Yosys errors: `ERROR: Re-definition of module \EICG_wrapper!`

**Solution:** Only concatenate files from the `top.f` filelist (which already includes stubs). Do NOT manually append stub files that are already in the list.

### Pitfall 4: SYNTH_MEMORY_MAX_BITS too small (if using behavioral fallback)

**Problem:** If you fall back to behavioral SRAMs (FF-based), ORFS errors: `Error: Synthesized memory size 4096 exceeds SYNTH_MEMORY_MAX_BITS`

**Solution:** Set `SYNTH_MEMORY_MAX_BITS = 131072` in config.mk. But this only applies to the FF-based fallback — the preferred SRAM macro approach does NOT need this.

### Pitfall 5: SRAM blackbox cost information

**Problem:** If you use `(* blackbox *)` attribute on SRAM modules without providing LEF/LIB, ORFS errors: `ERROR: Missing cost information on instanced blackbox sram22_*`

**Solution:** Do NOT use custom sram22 blackbox stubs. Instead, use the ORFS-provided `sky130_sram_*` macros which have LEF/LIB/GDS files. Set `SYNTH_BLACKBOXES` in config.mk and provide `ADDITIONAL_LEFS/LIBS/GDS`.

### Pitfall 6: Chipyard VLSI flow vs simulation flow

**Problem:** `make verilog` (simulation flow) generates TestHarness + ChipTop in split SV files. `make buildfile` (VLSI flow) generates ChipTop-only in `top.f` filelist with SRAM MacroCompiler output.

**Solution:** Use the **VLSI flow** (`make buildfile tutorial=sky130-openroad`) for ORFS. It produces a clean `top.f` filelist (ChipTop only, no TestHarness) and SRAM wrapper modules. The simulation flow includes TestHarness modules that are not needed and complicate the design.

## Multi-Round PnR Iteration Strategy (混合模式)

本流程至少执行 **3 轮** PnR 迭代。**用户设定目标频率，AI 根据每轮诊断结果自适应调参。**

### 用户输入

用户只需提供：
- **目标频率** (target frequency)，例如 `100MHz` → `clock_period_ns = 10`
- 可选：最大轮次数（默认 3）

AI 根据目标频率和每轮诊断结果，自主决定每轮的具体参数。

### 调参参数 (Parameter Knobs)

| 参数 | 说明 | 调整方向 |
|------|------|----------|
| `clock_period_ns` | 时钟周期（纳秒）= 1000 / freq_mhz | 逐步逼近目标频率 |
| `core_utilization` | 核心利用率（%） | 拥塞→降低，时序宽松→提高 |
| `place_density` | 布局密度（0.0–1.0） | 拥塞→降低，时序宽松→提高 |
| `gpl_timing_driven` | 时序驱动布局 | WNS 负值大→开启 |
| `gpl_routability_driven` | 可布线性驱动布局 | DRC violations 多→开启 |
| `setup_slack_margin` | 时序裕量（ns） | 逐步收紧至 0.05ns |

### 已验证 Baseline（注入知识）

以下参数组合已在 TinyRocketConfig + sky130hd 上通过完整 PnR 流程验证，**无需重复验证**：

| 参数 | 验证值 | 验证结果 |
|------|--------|----------|
| `clock_period_ns` | 20 (50MHz) | WNS=0.00, TNS=0.00, DRC=0 |
| `core_utilization` | 50 | Area=3,001,640µm², util=51% |
| `place_density` | 0.65 | 无拥塞问题 |
| `gpl_timing_driven` | 1 | **关键**：不开则 WNS=-0.12ns |
| `gpl_routability_driven` | 1 | DRC=0 |
| `setup_slack_margin` | 0.3 | 时序裕量充足 |
| 设计 fmax 上限 | ~54MHz | critical path ~18.4ns，无法通过 PnR 调参突破 |
| SRAM 宏数量 | 6 | 5×sky130_sram_1rw1r_64x256_8 + 1×sky130_sram_1rw1r_44x64_8 |

**使用规则**：
- 当用户指定的 baseline ≤ 50MHz 时，**跳过基准验证轮**，Round 1 直接使用 `baseline_clock_ns`（已知可通过）
- 当用户指定的 target > fmax 上限时，AI 应在 Round 1 尝试 target，失败后收敛到可实现频率附近
- 所有轮次默认启用 `gpl_timing_driven=1`

### 自适应调参逻辑

**Round 1（探索轮）**：直接使用 baseline 频率（已验证可通），如果是 baseline=target 则直接跑 target。
```json
{
  "clock_period_ns": "<baseline_clock_ns>",
  "core_utilization": 50,
  "place_density": 0.65,
  "gpl_timing_driven": true,
  "gpl_routability_driven": true,
  "setup_slack_margin": 0.3
}
```
> Round 1 直接跑 baseline 频率（如 50MHz/20ns），因为已知可通过。Round 2 开始向 target 推进。

**Round 2+（推进轮）**：AI 调用 `diagnose_failure` 和 `get_report` 读取上轮结果，然后根据以下信号调整参数：

| 诊断信号 | 含义 | AI 应采取的调整 |
|----------|------|-----------------|
| WNS << 0（如 < -2ns） | 严重时序违例 | 放宽 clock_period (+2ns)，降低 utilization (-5%)，开启 gpl_timing_driven |
| WNS 略负（如 -0.5ns） | 轻微时序违例 | 微调 clock_period (+0.5ns)，降低 place_density (-0.05)，收紧 slack_margin |
| WNS >= 0 | 时序满足 | 可以收紧 clock_period (-1ns)，提高 utilization (+5%) |
| DRC violations > 0 | 布线问题 | 降低 place_density (-0.1)，降低 utilization (-5%)，开启 gpl_routability_driven |
| TNS 很大 | 多条路径违例 | 大幅放宽 clock_period，降低 utilization |
| TNS 接近 0 | 只有少量路径违例 | 微调即可 |
| routing congestion hotspots | 局部拥塞 | 降低 place_density，开启 gpl_routability_driven |
| OOM / 超时 | 资源不足 | 降低 utilization 和 place_density |

**调参原则：**
1. 每轮只调整 1-2 个参数，不要同时大幅改动多个参数
2. 时序违例优先解决，再追求面积/功耗优化
3. 如果 WNS >= 0 且 DRC == 0，说明当前参数可行，可以尝试收紧 clock 继续逼近目标
4. 如果连续两轮 WNS 没有改善，说明已到极限，停止迭代
5. slack_margin 从 0.3ns 逐步收紧至 0.05ns，但不要在时序违例时收紧

### 轮次间操作

每轮结束后：

1. **调用 `get_report`** 获取本轮 finish/route 阶段的详细指标
2. **调用 `diagnose_failure`** 分析失败原因或时序问题
3. **调用 `compare_runs` 保存本轮结果**
4. **AI 根据诊断信号决定下一轮参数**（参考上表）
5. **更新 `config.mk`** 和 `constraint.sdc`
6. **调用 `clean_design`** 清除 ORFS 缓存
7. **启动新一轮 pnr-round-executor**

### 终止条件

满足以下任一条件时停止迭代：
- WNS >= 0 且 DRC violations == 0（时序和布线都满足）
- 达到最大轮次数（默认 3 轮）
- 连续两轮 WNS 改善 < 0.1ns（已收敛）
- clock_period 已达到用户目标频率

### 最终选优

所有轮次完成后，调用 `compare_runs(action="recommend")` 获取最佳结果建议，综合比较各轮的 WNS/TNS/面积/DRC violations/功耗，选择 PPA 最优的一轮作为最终结果。

## Pipeline

### Step 0 -- Parse Arguments and Setup

```bash
PROJECT_ROOT="<project-root>"
RAW_CONFIG="$ARGUMENTS"
# Extract design name from config for workspace path
# tinyrocket -> TinyRocket, TinyRocketConfig -> TinyRocket
if [ -z "$RAW_CONFIG" ]; then
    RAW_CONFIG="tinyrocket"
fi
if echo "$RAW_CONFIG" | grep -qE '[A-Z]'; then
    DESIGN=$(echo "$RAW_CONFIG" | sed 's/Config$//')
else
    FIRST=$(echo "${RAW_CONFIG:0:1}" | tr '[:lower:]' '[:upper:]')
    REST="${RAW_CONFIG:1}"
    DESIGN="${FIRST}${REST}"
fi
WORK_DIR="$PROJECT_ROOT/MyDesign/$DESIGN/workspace/pnr"

# Parse optional target frequency
# Usage: /chip-agent:chipyard-pnr-docker tinyrocket 100MHz
#        /chip-agent:chipyard-pnr-docker tinyrocket 10ns
#        /chip-agent:chipyard-pnr-docker tinyrocket 基准线是50MHz    (baseline + implicit target)
#        /chip-agent:chipyard-pnr-docker tinyrocket                   (no target → AI decides)
TARGET_FREQ_MHZ=""
TARGET_CLOCK_NS=""
BASELINE_FREQ_MHZ=""
BASELINE_CLOCK_NS=""
# AI parses RAW_CONFIG to determine:
#   BASELINE_FREQ_MHZ/CLOCK_NS: the "已知可通过" frequency (e.g., 50MHz/20ns)
#   TARGET_FREQ_MHZ/CLOCK_NS: the goal frequency (e.g., 100MHz/10ns)
# If only baseline is given (e.g., "基准线是50MHz"), target defaults to pushing beyond baseline
# If only target is given, baseline defaults to validated 50MHz (from injected knowledge)
# If neither, AI uses adaptive strategy
```

Normalize config name (same as `/chip-agent:chipyard`):
- `tinyrocket` → `TinyRocketConfig`
- `TinyRocket` → `TinyRocketConfig`
- `TinyRocketConfig` → `TinyRocketConfig`

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
    REST="${RAW_CONFIG:1}"
    CONFIG="${FIRST}${REST}Config"
fi
```

Create work directory:
```bash
mkdir -p "$WORK_DIR"
```

Echo:
```bash
echo "=== Chipyard-PnR (Docker) ==="
echo "Config: $CONFIG"
echo "Work: $WORK_DIR"
```

### Step 1 -- Verify Environment

```bash
# Read env.json for paths
ORFS_FLOW_PATH=$(jq -r '.orfs.flow_path' "$PROJECT_ROOT/.chipagent/env.json" 2>/dev/null)
```

Verify Docker is available:
```bash
docker info >/dev/null 2>&1 || STOP "Docker not available"
```

Verify ORFS inside Docker:
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

Call `mcp__chipagent-backend__check_environment` to verify Docker/ORFS/sky130hd readiness.

### Step 2 -- Locate Generated Verilog

```bash
VERILOG="$PROJECT_ROOT/MyDesign/$DESIGN/workspace/generated/${CONFIG}.v"
SRAM_MAP="$PROJECT_ROOT/MyDesign/$DESIGN/workspace/generated/sram_mapping.json"
SPEC="$PROJECT_ROOT/MyDesign/$DESIGN/workspace/spec.json"

test -f "$VERILOG" || STOP "Verilog not found: $VERILOG. Run /chip-agent:chipyard $DESIGN first."
test -f "$SRAM_MAP" && echo "SRAM mapping: found" || echo "SRAM mapping: not found (will generate)"
test -f "$SPEC" && echo "spec.json: found" || echo "spec.json: not found"

echo "Verilog: $(wc -l < "$VERILOG") lines"
```

### Step 3 -- Consolidate Verilog Files

Merge the split SV files into a single file. The generated Verilog from `/chip-agent:chipyard` should already be consolidated, but verify and ensure a single nosram file exists.

```bash
NOSRAM_V="$WORK_DIR/${CONFIG}_nosram.v"

# If the staged Verilog exists, use it directly (already consolidated from chipyard-docker)
if [ -f "$VERILOG" ]; then
    cp "$VERILOG" "$NOSRAM_V"
else
    STOP "Verilog not found at $VERILOG"
fi

echo "Consolidated: $NOSRAM_V ($(wc -l < "$NOSRAM_V") lines)"
```

**Verify no duplicate modules:**
```bash
# Should show 0 — all modules should be unique
grep "^module " "$NOSRAM_V" | sort | uniq -d | wc -l
```

**Verify no behavioral SRAM modules remain:**
```bash
grep -c '^module.*_ext' "$NOSRAM_V" && echo "WARNING: _ext modules remain" || echo "No _ext modules: OK"
```

### Step 4 -- Generate SRAM Override Modules

**Delegate to `sram-mapping` subagent.**

The SRAM override generation involves complex tiling logic (depth splitting, column grouping, wmask expansion, read MUX). Invoke the dedicated `sram-mapping` agent which encapsulates the full mapping analysis and code generation.

Spawn the `sram-mapping` agent (from `agents/sram-mapping.md`) with this context in the prompt:

```
GEN_DIR: <path to gen-collateral directory>
OUTPUT_DIR: <path to work directory>
ORFS_FLOW_PATH: <path to ORFS flow/ directory>
```

Example:
```
Agent(
  subagent_type: "sram-mapping",
  description: "Generate SRAM override modules",
  prompt: "Generate SRAM override modules for Chipyard design.
    GEN_DIR: /home/user/chipyard/vlsi/generated-src/chipyard.harness.TestHarness.TinyRocketConfig/gen-collateral
    OUTPUT_DIR: /home/user/ChipAgent-Test/try
    ORFS_FLOW_PATH: /home/user/OpenROAD-flow-scripts/flow"
)
```

The agent will:
1. Read `mems.conf` to parse SRAM specs (depth, width, ports, mask_gran)
2. Find behavioral module instantiation sites to infer port interfaces
3. Select the best-fit `sky130_sram_*` macro for each SRAM
4. Design the tiling strategy (depth tiles, column groups, bit slicing)
5. Generate `$WORK_DIR/sram_override.v` with correct override modules
6. Write `$WORK_DIR/sram_mapping.json` with structured mapping metadata
7. Perform a Yosys compile check

**After the agent completes, verify the output:**

```bash
test -f "$WORK_DIR/sram_override.v" || STOP "sram-mapping agent did not produce sram_override.v"
test -f "$WORK_DIR/sram_mapping.json" || STOP "sram-mapping agent did not produce sram_mapping.json"
```

**Extract SRAM macro list** from the generated mapping for Step 6:

```bash
USED_MACROS=$(jq -r '.mappings[] | select(.macro != null) | .macro' "$WORK_DIR/sram_mapping.json" | sort -u)
echo "Used SRAM macros: $USED_MACROS"
```

This macro list is needed in Step 6 to populate `SYNTH_BLACKBOXES`, `ADDITIONAL_LEFS/LIBS/GDS`, and `DONT_USE_CELLS` in config.mk.

### Step 5 -- Identify Clock Ports

Read the ChipTop module ports:
```bash
grep -A30 "^module ChipTop" "$WORK_DIR/${CONFIG}_nosram.v" | head -20
```

Typical TinyRocketConfig ChipTop clock ports:
- `clock_uncore_clock` — main core clock (10ns period)
- `serial_tl_clock` — serial link clock
- `jtag_TCK` — JTAG clock (100ns period)

### Step 6 -- Generate ORFS Config

Use `mcp__chipagent-backend__generate_config` to create base config, then manually enhance it.

**6a. Generate base config:**

Note: `workspace_dir` is the output directory for config.mk and constraint.sdc.
The tool writes files directly to this directory (no extra `/pnr` appended).

```
mcp__chipagent-backend__generate_config(
  module_name="ChipTop",
  verilog_path="$WORK_DIR/${CONFIG}_nosram.v",
  workspace_dir="$WORK_DIR/pnr",
  clock_port="clock_uncore_clock",
  clock_period_ns=10,
  core_utilization=55,
  place_density=0.65
)
```

**6b. Overwrite config.mk with full Chipyard-specific settings:**

The MCP-generated config is a minimal template. Replace it with the full config that includes SRAM macro paths, blackboxes, and physical constraints. The SRAM macro list is dynamically built from `sram_mapping.json` generated by `/chip-agent:sram-mapping`.

```bash
SRAM_DIR="$ORFS_FLOW_PATH/platforms/sky130ram"

# Build SRAM macro lists dynamically from sram_mapping.json
MACROS=$(jq -r '.mappings[] | select(.macro != null) | .macro' "$WORK_DIR/sram_mapping.json" | sort -u)
MACRO_LIST=$(echo "$MACROS" | tr '\n' ' ')

# Build VERILOG_FILES: nosram + override + each macro's behavioral .v
VERILOG_LIST="$WORK_DIR/${CONFIG}_nosram.v $WORK_DIR/sram_override.v"
for m in $MACROS; do
    VERILOG_LIST="$VERILOG_LIST $SRAM_DIR/$m/$m.v"
done

# Build ADDITIONAL_LEFS/LIBS/GDS lines
LEFS=""; LIBS=""; GDS=""
for m in $MACROS; do
    LEFS="$LEFS $SRAM_DIR/$m/$m.lef"
    LIBS="$LIBS $SRAM_DIR/$m/${m}_TT_1p8V_25C.lib"
    GDS="$GDS $SRAM_DIR/$m/$m.gds"
done

# Format as backslash-continued Makefile lines
VERILOG_LINES=$(echo "$VERILOG_LIST" | sed 's/  */ \\\n    /g')
LEF_LINES=$(echo "$LEFS" | sed 's/^ *//' | sed 's/  */ \\\n    /g')
LIB_LINES=$(echo "$LIBS" | sed 's/^ *//' | sed 's/  */ \\\n    /g')
GDS_LINES=$(echo "$GDS" | sed 's/^ *//' | sed 's/  */ \\\n    /g')

cat > "$WORK_DIR/pnr/config.mk" << CFGEOF
export DESIGN_NAME = ChipTop
export PLATFORM = sky130hd
export DESIGN_NICKNAME = tinyRocket

export VERILOG_FILES = \\
    $VERILOG_LINES

export SDC_FILE = $WORK_DIR/pnr/constraint.sdc

# Blackbox SRAM macros during synthesis (Yosys leaves them as abstract blocks)
export SYNTH_BLACKBOXES = $MACRO_LIST

# SRAM macro physical files for OpenROAD floorplan/place/route
export ADDITIONAL_LEFS = \\
    $LEF_LINES
export ADDITIONAL_LIBS = \\
    $LIB_LINES
export ADDITIONAL_GDS = \\
    $GDS_LINES

# Prevent ABC from mapping to SRAM cells
export DONT_USE_CELLS += $MACRO_LIST

# Hierarchical synthesis to preserve SRAM blackbox instances
export SYNTH_HIERARCHICAL = 1
export SYNTH_MINIMUM_KEEP_SIZE = 1000
export ABC_AREA = 1

# Physical parameters (validated: TinyRocket 50MHz on sky130hd, R2 pass)
export CORE_UTILIZATION = 50
export PLACE_DENSITY = 0.65
export GPL_TIMING_DRIVEN = 1
export GPL_ROUTABILITY_DRIVEN = 1
export SETUP_SLACK_MARGIN = 0.3
export MACRO_PLACE_HALO = 20 20

# CTS tuning
export CTS_CLUSTER_SIZE = 20
export CTS_CLUSTER_DIAMETER = 50

export TNS_END_PERCENT = 100
export SKIP_ANTENNA_REPAIR_POST_DRT = 1
export NUM_CORES = 4

# Skip IR drop analysis (SRAM halo blocks PDN vias)
export PWR_NETS_VOLTAGES =
export GND_NETS_VOLTAGES =
CFGEOF
```

**6c. Write SDC with multi-clock constraints:**

```bash
cat > "$WORK_DIR/pnr/constraint.sdc" << SDCEOF
current_design ChipTop
create_clock -name core_clock -period 10 [get_ports clock_uncore_clock]
create_clock -name serial_clock -period 10 [get_ports serial_tl_clock]
create_clock -name jtag_clock -period 100 [get_ports jtag_TCK]
# NOTE: For multi-round iteration, update core_clock period here to match round's clock_period_ns
set_clock_groups -asynchronous -group {core_clock} -group {serial_clock} -group {jtag_clock}
set_input_delay -clock core_clock 0 [all_inputs -no_clocks]
set_output_delay -clock core_clock 0 [all_outputs]
SDCEOF
```

### Step 7 -- Run ORFS Full Flow

Run the full ORFS flow in a **background subagent** so the main agent remains responsive and can report progress to the user.

**7a. Clean previous run (direct MCP call):**
```
mcp__chipagent-backend__clean_design(
  config_mk_path="$WORK_DIR/pnr/config.mk",
  orfs_flow_path="$ORFS_FLOW_PATH/flow"
)
```

**7b. Initialize progress file and iteration state:**

```bash
# Set total rounds (minimum 3, maximum 5)
TOTAL_ROUNDS=3

# Round 1 parameters: use baseline clock directly (already validated to pass)
# When baseline ≤ 50MHz, skip validation — Round 1 runs baseline, Round 2+ pushes toward target
R1_CLOCK="${BASELINE_CLOCK_NS:-${TARGET_CLOCK_NS:-10}}"
R1_UTIL=50
R1_DENSITY=0.65
R1_TIMING_DRIVEN=1
R1_ROUTABILITY_DRIVEN=1
R1_SLACK_MARGIN=0.3

cat > "$WORK_DIR/pnr/progress.json" << EOF
{"round":1,"total_rounds":$TOTAL_ROUNDS,"current_stage":"starting","stages_completed":[],"stages_remaining":["synth","floorplan","place","cts","route","finish"],"status":"running","latest_metrics":{},"failed_stage":null,"timestamp":"$(date -Iseconds)","target_freq_mhz":"${TARGET_FREQ_MHZ:-adaptive}","target_clock_ns":"${TARGET_CLOCK_NS:-adaptive}"}
EOF

# Create iteration history file for AI decision-making
cat > "$WORK_DIR/pnr/iteration_history.json" << 'EOF'
{"rounds":[]}
EOF
```

**7c. Spawn background round executor (Round 1 — baseline):**

Spawn the `pnr-round-executor` agent with `run_in_background: true`:

```
Agent(
  subagent_type: "pnr-round-executor",
  description: "PnR Round 1: ChipTop (tinyRocket) — baseline",
  run_in_background: true,
  prompt: "
    module: ChipTop
    project_root: $PROJECT_ROOT
    round_number: 1
    total_rounds: 3
    restart_from: synth
    current_params: { clock_period_ns: $R1_CLOCK, core_utilization: $R1_UTIL, place_density: $R1_DENSITY, gpl_timing_driven: $R1_TIMING_DRIVEN, gpl_routability_driven: $R1_ROUTABILITY_DRIVEN, setup_slack_margin: $R1_SLACK_MARGIN }
    config_mk: $WORK_DIR/pnr/config.mk
    design_name: ChipTop
    orfs_flow_path: $ORFS_FLOW_PATH/flow
    clock_port: clock_uncore_clock
    progress_file: $WORK_DIR/pnr/progress.json
    NOTE: Stage timeouts: synth=30min, floorplan=60min, place=30min, cts=30min, route=120min, finish=30min.
  "
)
```

**7d. Set up progress polling with ScheduleWakeup:**

Schedule a recurring wakeup every 10 minutes to check progress and report to the user:

```
ScheduleWakeup(
  delaySeconds: 600,
  reason: "Check ChipTop PnR progress",
  prompt: "<same prompt as the original /chip-agent:chipyard-pnr-docker invocation>"
)
```

On each wakeup, read `$WORK_DIR/pnr/progress.json` and report:
```
cat "$WORK_DIR/pnr/progress.json"
```

Format the report as:
```
PnR Progress: Round X/3 — <current_stage>
  Completed: <stages_completed list>
  Remaining: <stages_remaining list>
  Params: clock=<ns>ns, util=<%>%, density=<d>, slack_margin=<sm>ns
  Latest: <latest_metrics summary (WNS, area, violations)>
```

If `status === "running"`: continue polling (ScheduleWakeup again).
If `status === "pass"` or `status === "fail"`: stop polling and proceed to Step 7e.

**7e. Handle round completion — diagnose and decide next parameters:**

When the background agent completes, you will receive a task notification. At that point:
1. Stop the ScheduleWakeup (CronDelete)
2. Read the final `$WORK_DIR/pnr/progress.json`
3. **Save round results** via `compare_runs`:
   ```
   mcp__chipagent-backend__compare_runs(
     action="save",
     workspace_dir="$WORK_DIR",
     run={"round": <current_round>, "config": {<params>}, "metrics": {<from progress.json>}, "status": "pass"|"fail"}
   )
   ```

4. **Collect detailed metrics** via MCP:
   ```
   mcp__chipagent-backend__get_report(design_name="ChipTop", stage="finish", orfs_flow_path="$ORFS_FLOW_PATH/flow")
   mcp__chipagent-backend__get_report(design_name="ChipTop", stage="route", orfs_flow_path="$ORFS_FLOW_PATH/flow")
   ```

5. **Diagnose results** — call `diagnose_failure` to get AI-readable analysis:
   ```
   mcp__chipagent-backend__diagnose_failure(
     stage="finish",
     success=<true|false>,
     current_clock_period_ns=<current CP>,
     current_core_utilization=<current CU>,
     current_place_density=<current PD>,
     sdc_content=<read constraint.sdc>,
     finish_report_content=<from get_report>
   )
   ```

6. **AI decides next round parameters** based on the diagnostic signals:
   - Read WNS, TNS, DRC violations, area, power from the reports
   - Apply the "自适应调参逻辑" table (see Multi-Round Strategy section)
   - Determine the next round's `{clock_period_ns, core_utilization, place_density, gpl_timing_driven, gpl_routability_driven, setup_slack_margin}`
   - Record the decision rationale in `iteration_history.json`

**7f. Launch next round (if more rounds remain and termination conditions not met):**

Check termination conditions first:
- If WNS >= 0 AND DRC == 0: **success**, proceed to Step 8
- If `current_round >= total_rounds`: **max rounds reached**, proceed to Step 8
- If consecutive WNS improvement < 0.1ns: **converged**, proceed to Step 8

Otherwise, launch next round with AI-decided parameters:

1. **Update `config.mk`** with the AI-decided parameters:
   ```bash
   # CP, CU, PD, GTD, GRD, SSM are the AI-decided values from Step 7e
   sed -i "s/^export CORE_UTILIZATION = .*/export CORE_UTILIZATION = $CU/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export PLACE_DENSITY = .*/export PLACE_DENSITY = $PD/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export GPL_TIMING_DRIVEN = .*/export GPL_TIMING_DRIVEN = $GTD/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export GPL_ROUTABILITY_DRIVEN = .*/export GPL_ROUTABILITY_DRIVEN = $GRD/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export SETUP_SLACK_MARGIN = .*/export SETUP_SLACK_MARGIN = $SSM/" "$WORK_DIR/pnr/config.mk"
   ```

2. **Update `constraint.sdc`** with new clock period:
   ```bash
   sed -i "s/-period [0-9]* \[get_ports clock_uncore_clock\]/-period $CP [get_ports clock_uncore_clock]/" "$WORK_DIR/pnr/constraint.sdc"
   sed -i "s/-period [0-9]* \[get_ports serial_tl_clock\]/-period $CP [get_ports serial_tl_clock]/" "$WORK_DIR/pnr/constraint.sdc"
   ```

3. **Clean ORFS cache:**
   ```
   mcp__chipagent-backend__clean_design(
     config_mk_path="$WORK_DIR/pnr/config.mk",
     orfs_flow_path="$ORFS_FLOW_PATH/flow"
   )
   ```

4. **Update progress.json:**
   ```bash
   cat > "$WORK_DIR/pnr/progress.json" << EOF
   {"round":$NEXT_ROUND,"total_rounds":$TOTAL_ROUNDS,"current_stage":"starting","stages_completed":[],"stages_remaining":["synth","floorplan","place","cts","route","finish"],"status":"running","latest_metrics":{},"failed_stage":null,"timestamp":"$(date -Iseconds)","target_freq_mhz":"${TARGET_FREQ_MHZ:-adaptive}","target_clock_ns":"${TARGET_CLOCK_NS:-adaptive}"}
   EOF
   ```

5. **Spawn next round executor** with AI-decided params:
   ```
   Agent(
     subagent_type: "pnr-round-executor",
     description: "PnR Round $NEXT_ROUND: ChipTop (tinyRocket) — adaptive",
     run_in_background: true,
     prompt: "
       module: ChipTop
       project_root: $PROJECT_ROOT
       round_number: $NEXT_ROUND
       total_rounds: $TOTAL_ROUNDS
       restart_from: synth
       current_params: { clock_period_ns: $CP, core_utilization: $CU, place_density: $PD, gpl_timing_driven: $GTD, gpl_routability_driven: $GRD, setup_slack_margin: $SSM }
       config_mk: $WORK_DIR/pnr/config.mk
       design_name: ChipTop
       orfs_flow_path: $ORFS_FLOW_PATH/flow
       clock_port: clock_uncore_clock
       progress_file: $WORK_DIR/pnr/progress.json
       NOTE: Stage timeouts: synth=30min, floorplan=60min, place=30min, cts=30min, route=120min, finish=30min.
     "
   )
   ```

6. **Resume ScheduleWakeup** for the new round (same as Step 7d).

7. **Loop back to Step 7e** when this round completes.

**Total runtime:** ~82 minutes per round, ~4.5 hours for all 3 rounds on a modern machine.

**Memory requirements:**
- Synthesis: ~3 GB
- Floorplan/PDN: ~12 GB (PDN generation is memory-intensive)
- Place: ~2 GB
- CTS: ~2 GB
- Route (DRT): ~7-8 GB
- Finish: ~2 GB

### Step 8 -- Compare Rounds and Select Best Result

**8a. Load all round results and recommend best:**

```
mcp__chipagent-backend__compare_runs(
  action="recommend",
  workspace_dir="$WORK_DIR"
)
```

**8b. Collect detailed metrics for each round** (if not already saved):

```bash
for ROUND in $(seq 1 $TOTAL_ROUNDS); do
  echo "=== Round $ROUND ==="
  cat "$WORK_DIR/pnr/progress_round_${ROUND}.json" 2>/dev/null || echo "(no separate progress file)"
done
```

Collect final metrics via MCP for each round:
```
mcp__chipagent-backend__get_report(design_name="ChipTop", stage="finish", orfs_flow_path="$ORFS_FLOW_PATH/flow")
mcp__chipagent-backend__get_report(design_name="ChipTop", stage="route", orfs_flow_path="$ORFS_FLOW_PATH/flow")
```

**8c. Display comparison table:**

```
=== Chipyard PnR Multi-Round Results: ChipTop (tinyRocket) ===

| Round | Clock(ns) | Util% | Density | Timing-Driven | Routability | Slack Margin | WNS(ns) | TNS(ns) | Area(um^2) | DRC | Power(uW) | Status |
|-------|-----------|-------|---------|---------------|-------------|--------------|---------|---------|------------|-----|-----------|--------|
| R1    | 10        | 55    | 0.65    | -             | Y           | 0.2          | ...     | ...     | ...        | ... | ...       | PASS/FAIL |
| R2    | 8         | 60    | 0.72    | Y             | -           | 0.1          | ...     | ...     | ...        | ... | ...       | PASS/FAIL |
| R3    | 6         | 70    | 0.80    | Y             | Y           | 0.05         | ...     | ...     | ...        | ... | ...       | PASS/FAIL |

Best round: R<X> — <reason>
```

**8d. Report final recommended result:**

```
=== Final Recommended Result ===
Round: R<X>
Clock Period: <ns> ns (<freq> MHz)
WNS: <wns> ns | TNS: <tns> ns
Area: <area> um^2
Power: <power> uW
DRC Violations: <count>
Status: PASS / FAIL
```

**Expected output files** (at `$ORFS_FLOW_PATH/flow/results/sky130hd/tinyRocket/base/`):
| File | Description |
|------|-------------|
| `6_final.gds` | Final GDSII layout (~255 MB) |
| `6_final.odb` | Final OpenDB database (~540 MB) |
| `6_final.v` | Final Verilog netlist (~40 MB) |
| `6_final.spef` | Parasitic extraction (~156 MB) |
| `6_final.def` | Final DEF file (~241 MB) |

## Pipeline Stages Summary

| # | Stage | Duration | Peak Memory | Key Notes |
|---|-------|----------|-------------|-----------|
| 0 | Parse & Setup | - | - | Normalize config, parse target frequency, create work dir |
| 1 | Verify Environment | - | - | Check Docker, ORFS, sky130hd |
| 2 | Locate Verilog | - | - | Find staged Verilog from chipyard-docker |
| 3 | Consolidate SV | ~10 sec | ~100 MB | Verify single nosram file |
| 4 | SRAM Override | - | - | Delegate to `/chip-agent:sram-mapping`, yosys check |
| 5 | Identify Clocks | - | - | Parse ChipTop ports |
| 6 | Generate Config | - | - | config.mk + multi-clock SDC |
| 7a | Clean + Init | ~10 sec | - | `clean_design` + init progress.json + iteration_history.json |
| 7b | PnR Round 1 | ~102 min | ~12 GB | Baseline with relaxed params (AI adapts from here) |
| 7c | Diagnose R1 | ~2 min | - | `get_report` + `diagnose_failure` → AI decides R2 params |
| 7d | PnR Round 2 | ~102 min | ~12 GB | AI-adapted params based on R1 diagnostics |
| 7e | Diagnose R2 | ~2 min | - | `get_report` + `diagnose_failure` → AI decides R3 params |
| 7f | PnR Round 3 | ~102 min | ~12 GB | AI-adapted params based on R2 diagnostics |
| 8 | Compare & Report | - | - | `compare_runs` recommend, display multi-round comparison table |

**Total runtime:** ~5.5 hours for 3 rounds (~102 min each + ~2 min diagnosis between rounds).

## Anti-Patterns

- **NEVER** use behavioral SRAM stubs (reg arrays) — causes OOM in routing (13+ GB)
- **NEVER** omit `ENABLE_YOSYS_FLOW=1` — causes Yosys parse errors on packed arrays
- **NEVER** append stub files that are already in `top.f` — causes duplicate module errors
- **NEVER** use `SYNTH_BLACKBOXES` without `ADDITIONAL_LEFS/LIBS/GDS` — causes missing cost error
- **NEVER** use the simulation flow (`make verilog`) — includes TestHarness modules
- **ALWAYS** use `timeout_minutes=120` for the `route` stage — detailed routing takes up to 120 minutes for complex designs
- **ALWAYS** use `timeout_minutes=30` for the `synth` stage — ABC technology mapping for 70+ modules needs 30 minutes
- **ALWAYS** use `timeout_minutes=30` for the `place` stage — repair_design resize processing 90K+ nets needs 30 minutes
- **NEVER** skip `clean_all` between retries — ORFS caches stale results
- **ALWAYS** verify Yosys compiles the design before running ORFS (Step 4 verification)
- **ALWAYS** set `SYNTH_HIERARCHICAL = 1` — preserves SRAM module boundaries
- **ALWAYS** set `MACRO_PLACE_HALO = 20 20` — prevents standard cells from overlapping SRAM halo
- **ALWAYS** set `DONT_USE_CELLS` for SRAM macros — prevents ABC from using them as logic cells
- **ALWAYS** set `SKIP_ANTENNA_REPAIR_POST_DRT = 1` — avoids OOM during antenna repair
- **ALWAYS** run `clean_design` between PnR rounds — stale ORFS cache causes misleading results
- **ALWAYS** save round results via `compare_runs` before starting the next round
- **ALWAYS** use `compare_runs(action="recommend")` to select the best round objectively
- **NEVER** skip the baseline round (R1) — it validates the flow before aggressive tuning
- **NEVER** enable both `gpl_timing_driven` and `gpl_routability_driven` in early rounds — they conflict and can cause poor placement
- **PREFER** starting with routability-driven in R1, then timing-driven in R2, then both in R3 only if needed
- **NEVER** use local paths inside Docker — use `/OpenROAD-flow-scripts/flow` paths
- **NEVER** run ORFS on host — always inside `openroad/orfs` Docker container
- **NEVER** skip nosram preprocessing — behavioral SRAM modules cause OOM
- **NEVER** use `SWAP_ARITH_OPERATORS=1` — causes ABC crash on large designs
- **NEVER** set `NUM_CORES` > 4 on systems with < 16GB RAM

## Input

$ARGUMENTS

A Chipyard config name (e.g., `tinyrocket`, `TinyRocketConfig`). Optional arguments:
- **Work directory**: `/path/to/try`
- **Target frequency**: `100MHz` or `10ns` (AI will adaptively tune parameters to reach this target over multiple rounds)

## Output

Upon completion:
- GDS: `$ORFS_FLOW/results/sky130hd/tinyRocket/base/6_final.gds`
- Netlist: `$ORFS_FLOW/results/sky130hd/tinyRocket/base/6_final.v`
- SPEF: `$ORFS_FLOW/results/sky130hd/tinyRocket/base/6_final.spef`
- Reports: `$ORFS_FLOW/reports/sky130hd/tinyRocket/base/`
- Timing/area/DRC summary displayed in conversation
