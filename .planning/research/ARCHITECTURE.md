# Architecture: sky130hd MCP Backend

**Project:** ChipAgent v1.1.5
**Researched:** 2026-04-01
**Overall confidence:** HIGH (based on verified ORFS installation at ~/OpenROAD-flow-scripts, sky130hd platform files present, task2.md requirements analyzed, MCP SDK docs verified via official sources)

---

## Executive Summary

v1.1.5 replaces the standalone nangate45 Tcl-script PnR flow (v1.1.2) with an ORFS-driven sky130hd flow exposed through an MCP Server. The key architectural change: **Claude Code calls MCP tools instead of invoking bash scripts directly.** The MCP Server wraps `docker exec` calls to an ORFS container (with a local-fallback path for development), generates config.mk/constraint.sdc from spec.json, invokes ORFS make targets per-stage, extracts metrics from ORFS output directories, and returns structured results.

The architecture introduces three new components (MCP Server, config generator, ORFS wrapper) while modifying four existing ones (pnr skill, initialize skill, detect-env.sh, env.json schema). All components upstream of PnR (generate, compile, lint, simulate) remain untouched.

---

## Architectural Decision: ORFS Makefile via MCP (not standalone Tcl)

**v1.1.2 chose standalone Tcl.** That was correct for nangate45 because:
- ORFS complexity was unnecessary for small Chisel modules
- nangate45 platform files could be consumed directly by standalone Tcl
- The rigid ORFS directory structure conflicted with workspace conventions

**v1.1.5 must use the ORFS Makefile.** The reasons are different now:
1. **Task2 requirement is explicit:** "ORFS 后端自动化流程框架, 通过 `make` 驱动完整后端流程" -- the assignment mandates using ORFS make targets, not standalone Tcl.
2. **Docker container model:** The ORFS Docker image (`openroad/orfs:latest`) has ORFS installed at `/OpenROAD-flow-scripts/flow/`. The canonical usage is `make DESIGN_CONFIG=...` inside the container.
3. **sky130hd platform has more complex flow requirements** than nangate45: the PDN Tcl, tapcell Tcl, fastroute config, fill.json, latch/clkgate mapping files, and adder mapping are all consumed by ORFS's synthesis and PnR scripts -- not trivially replicated in standalone Tcl.
4. **Per-stage make targets** (`synth`, `floorplan`, `place`, `cts`, `route`, `finish`) allow the MCP Server to execute stages individually while still leveraging ORFS's internal dependency tracking.

**The MCP Server wraps ORFS make.** It does not replace it. The server generates `config.mk` and `constraint.sdc`, copies them into the container workspace, then invokes `make DESIGN_CONFIG=/workspace/config.mk <target>` via `docker exec`.

---

## Component Architecture

### New Components

| Component | Type | Location | Responsibility |
|-----------|------|----------|----------------|
| MCP Server | TypeScript process | `mcp-server/src/index.ts` | Expose ORFS tools to Claude Code via stdio MCP protocol |
| Config Generator | TypeScript module | `mcp-server/src/config-gen.ts` | Generate config.mk and constraint.sdc from spec.json + Verilog analysis |
| ORFS Runner | TypeScript module | `mcp-server/src/orfs-runner.ts` | Execute ORFS make targets via docker exec (or local make --file) |
| Metric Extractor | TypeScript module | `mcp-server/src/metrics.ts` | Parse ORFS output directories for timing/power/area/DRC metrics |
| `.mcp.json` | Config file | `.mcp.json` (project root) | Register MCP Server with Claude Code |

### Modified Components

| Component | Change | Why |
|-----------|--------|-----|
| `skills/pnr/SKILL.md` | Rewrite to call MCP tools instead of bash scripts | MCP tools replace direct script invocation |
| `skills/initialize/SKILL.md` | Add Docker detection, sky130hd detection | New environment requirements |
| `scripts/detect-env.sh` | Add Docker, sky130hd PDK detection | Pre-flight for Docker + ORFS |
| `.chipagent/env.json` | New fields: `docker`, `pdk.sky130hd`, `orfs` | Track Docker and sky130hd availability |
| `CLAUDE.md` | Add MCP Server description, update tech stack | Document new components |
| `agents/pnr-report-formatter.md` | Update for ORFS report format (different from standalone) | ORFS produces reports in different paths/formats |

### Deprecated/Removed Components

| Component | Status | Replacement |
|-----------|--------|-------------|
| `scripts/synth.sh` | Deprecated (keep for nangate45 fallback) | MCP `run_stage` tool with target=synth |
| `scripts/synth.tcl` | Deprecated (keep for nangate45 fallback) | ORFS internal synthesis scripts |
| `scripts/pnr.sh` | Deprecated (keep for nangate45 fallback) | MCP `run_stage` tool with target=route/finish |
| `scripts/pnr.tcl` | Deprecated (keep for nangate45 fallback) | ORFS internal PnR scripts |
| `scripts/generate_sdc.sh` | Deprecated | MCP `generate_config` tool (config-gen.ts) |
| `scripts/validate-pdk.sh` | Deprecated | MCP `check_environment` tool |
| `scripts/def2gds.py` | Deprecated | ORFS `finish` target includes GDS merge |

### Unchanged Components

All components upstream of PnR remain untouched:
- `skills/generate/`, `skills/workflow/`, `skills/compile/`, `skills/lint/`, `skills/simulate/`, `skills/debug/`
- `agents/requirement-parser.md`, `agents/chisel-generator.md`, `agents/testbench-generator.md`, `agents/debug-analyzer.md`, `agents/project-init.md`
- `scripts/compile.sh`, `scripts/lint.sh`, `scripts/simulate.sh`, `scripts/setup.sh`, `scripts/_common.sh`

---

## MCP Server Architecture

### Server Structure

```
mcp-server/
  package.json              # name: "chipagent-mcp-server", dependencies
  tsconfig.json             # TypeScript config (ESM, Node 18+)
  src/
    index.ts                # Entry point: McpServer + StdioServerTransport
    tools/
      check-environment.ts  # Tool: validate Docker + ORFS + sky130hd
      generate-config.ts    # Tool: produce config.mk + constraint.sdc
      run-stage.ts          # Tool: execute one ORFS make target
      get-report.ts         # Tool: extract metrics from ORFS output
      get-log.ts            # Tool: read stage log for diagnosis
    lib/
      orfs-runner.ts        # Docker exec / local make wrapper
      config-gen.ts         # config.mk + SDC template generation
      metrics.ts            # Parse ORFS reports/logs/metadata.json
      docker.ts             # Docker container management helpers
      paths.ts              # Path resolution (container vs local)
```

### MCP Tools Exposed

Five tools cover the full ORFS backend flow. Each tool maps to a `server.tool()` registration with Zod schema validation.

#### Tool 1: `check_environment`

**Purpose:** Validate that Docker, ORFS container, and sky130hd platform are available.

**Parameters:** None.

**Returns:**
```json
{
  "docker_available": true,
  "container_running": true,
  "container_name": "orfs-agent",
  "orfs_path": "/OpenROAD-flow-scripts/flow",
  "sky130hd_available": true,
  "yosys_version": "0.53+...",
  "openroad_version": "v2.0-...",
  "ready": true
}
```

**Implementation:** Runs `docker exec orfs-agent yosys -version` and `docker exec orfs-agent openroad -version`. Checks for `/OpenROAD-flow-scripts/flow/platforms/sky130hd/config.mk` inside container.

#### Tool 2: `generate_config`

**Purpose:** Generate `config.mk` and `constraint.sdc` for a module based on spec.json and Verilog analysis.

**Parameters:**
```typescript
{
  module_name: z.string().describe("PascalCase module name, e.g., ALU"),
  verilog_path: z.string().describe("Absolute path to compiled Verilog file"),
  spec_json_path: z.string().optional().describe("Path to spec.json for clock info"),
  clock_period_ns: z.number().optional().describe("Override clock period in ns (default: auto-detect)"),
  core_utilization: z.number().optional().describe("Core utilization percentage (default: 40)"),
  place_density: z.number().optional().describe("Placement density 0-1 (default: 0.60)")
}
```

**Returns:** Paths to generated config.mk and constraint.sdc, plus the detected module type (sequential/combinational).

**Implementation:**
1. Read Verilog file, extract `module` name (authoritative).
2. Grep for `always @(posedge` to detect sequential vs combinational.
3. Read spec.json `clock_period_ns` if available, else default 5.0 ns (sky130hd needs more relaxed timing than nangate45).
4. Generate `config.mk` with PLATFORM=sky130hd, DESIGN_NAME, VERILOG_FILES, SDC_FILE, CORE_UTILIZATION, PLACE_DENSITY.
5. Generate `constraint.sdc` following the gcd example pattern (sky130hd-compatible format).
6. Write both to `MyDesign/<Module>/workspace/pnr/`.
7. Copy Verilog file to the workspace design source directory for ORFS to find.

#### Tool 3: `run_stage`

**Purpose:** Execute a single ORFS flow stage via make.

**Parameters:**
```typescript
{
  module_name: z.string().describe("Module name"),
  stage: z.enum(["synth", "floorplan", "place", "cts", "route", "finish"]).describe("ORFS make target"),
  config_path: z.string().describe("Path to config.mk in workspace")
}
```

**Returns:**
```json
{
  "success": true,
  "stage": "synth",
  "elapsed_seconds": 12.3,
  "log_path": "/workspace/logs/sky130hd/ALU/base/1_1_yosys.log",
  "results_path": "/workspace/results/sky130hd/ALU/base/",
  "error_summary": null
}
```

**Implementation:**
1. Copy config.mk and constraint.sdc and Verilog into the Docker container workspace.
2. Run `docker exec orfs-agent make -C /OpenROAD-flow-scripts/flow DESIGN_CONFIG=/workspace/config.mk <stage>` with a timeout.
3. Capture exit code, parse last 50 lines of log on failure.
4. On success, copy result files back to host workspace.

**Local fallback:** When Docker is unavailable and ORFS is installed locally (detected at `~/OpenROAD-flow-scripts`), run `make --file=$HOME/OpenROAD-flow-scripts/flow/Makefile DESIGN_CONFIG=<path>/config.mk <stage>` directly.

#### Tool 4: `get_report`

**Purpose:** Extract structured metrics from ORFS output for a completed (or partially completed) flow.

**Parameters:**
```typescript
{
  module_name: z.string().describe("Module name"),
  stage: z.enum(["synth", "floorplan", "place", "cts", "route", "finish", "all"]).describe("Which stage metrics to extract"),
  config_path: z.string().describe("Path to config.mk for directory resolution")
}
```

**Returns:** Structured JSON with stage-appropriate metrics:
```json
{
  "stage": "route",
  "metrics": {
    "cell_count": 156,
    "design_area_um2": 8234.5,
    "utilization_pct": 12.3,
    "wns_ns": 0.42,
    "tns_ns": 0.0,
    "drc_violations": 0,
    "total_power_uw": 45.2,
    "internal_power_uw": 28.1,
    "switching_power_uw": 12.3,
    "leakage_power_uw": 4.8
  },
  "timing_met": true,
  "report_paths": {
    "timing": "...",
    "power": "...",
    "area": "..."
  }
}
```

**Implementation:** Reads ORFS output from `results/sky130hd/<DESIGN_NAME>/base/` and `reports/sky130hd/<DESIGN_NAME>/base/`. Parses `synth_stat.txt`, timing reports, power reports via regex. Falls back to `metadata.json` if available (ORFS generates this at flow end).

#### Tool 5: `get_log`

**Purpose:** Retrieve and tail stage log for diagnosis when a stage fails.

**Parameters:**
```typescript
{
  module_name: z.string().describe("Module name"),
  stage: z.enum(["synth", "floorplan", "place", "cts", "route", "finish"]).describe("Which stage log"),
  lines: z.number().optional().describe("Number of lines from end (default: 100)")
}
```

**Returns:** Log text content and file path.

**Implementation:** Reads from ORFS `logs/sky130hd/<DESIGN_NAME>/base/` directory. The log filenames follow ORFS convention: `1_1_yosys.log`, `2_1_floorplan.log`, `3_1_place_gp_skip_io.log`, `4_1_cts.log`, `5_1_grt.log`/`5_2_route.log`, `6_1_merge.log`.

### MCP Registration

The MCP Server connects to Claude Code via stdio transport. Registration in `.mcp.json` at project root:

```json
{
  "mcpServers": {
    "chipagent-orfs": {
      "type": "stdio",
      "command": "node",
      "args": ["mcp-server/build/index.js"],
      "env": {
        "DOCKER_CONTAINER": "orfs-agent",
        "ORFS_DIR": "${ORFS_DIR:-/home/mingzhenjia/OpenROAD-flow-scripts}"
      }
    }
  }
}
```

**Why stdio transport:** Claude Code runs locally. The MCP Server needs to exec Docker commands and access the local filesystem. Stdio is the standard transport for local MCP servers.

**Why not HTTP transport:** No need for remote access. HTTP adds complexity (CORS, port allocation, process management) with no benefit for a local tool server.

---

## Data Flow: Skill -> MCP -> ORFS -> Results -> Reports

```
USER invokes /chip-agent:pnr ALU
  |
  v
[pnr SKILL.md] -- orchestration layer (Claude reads SKILL.md instructions)
  |
  |  1. Call MCP tool: check_environment
  |     <- { ready: true, ... }
  |
  |  2. Call MCP tool: generate_config
  |     -> { module_name: "ALU", verilog_path: ".../ALU.v", ... }
  |     <- { config_mk: ".../config.mk", sdc: ".../constraint.sdc", type: "combinational" }
  |
  |  3. For each stage in [synth, floorplan, place, cts, route, finish]:
  |     Call MCP tool: run_stage
  |       -> { module_name: "ALU", stage: "synth", config_path: ".../config.mk" }
  |       <- { success: true, elapsed_seconds: 5.2, ... }
  |
  |     Call MCP tool: get_report
  |       -> { module_name: "ALU", stage: "synth" }
  |       <- { metrics: { cell_count: 156, ... } }
  |
  |     If stage fails:
  |       Call MCP tool: get_log
  |         -> { module_name: "ALU", stage: "synth", lines: 100 }
  |         <- { log: "...", path: "..." }
  |       Diagnose and decide: retry with adjusted params or stop
  |
  |  4. Call MCP tool: get_report (stage: "all")
  |     <- { complete PPA summary }
  |
  |  5. Format and present PPA summary report
  v
USER sees formatted PPA report in conversation
```

### Internal Data Flow Within MCP Server

```
[generate_config tool]
  |
  |  Reads: MyDesign/ALU/workspace/generated/ALU.v
  |  Reads: MyDesign/ALU/workspace/spec.json (optional)
  |
  |  Writes to host:
  |    MyDesign/ALU/workspace/pnr/config.mk
  |    MyDesign/ALU/workspace/pnr/constraint.sdc
  |
  v
[run_stage tool]
  |
  |  docker cp: config.mk, constraint.sdc, ALU.v -> container:/workspace/
  |  docker exec: make -C /OpenROAD-flow-scripts/flow
  |                     DESIGN_CONFIG=/workspace/config.mk synth
  |
  |  ORFS inside container:
  |    Reads: /workspace/config.mk -> PLATFORM=sky130hd, DESIGN_NAME=ALU
  |    Reads: /OpenROAD-flow-scripts/flow/platforms/sky130hd/config.mk
  |    Runs: Yosys with platform .lib, .lef, mapping files
  |    Writes: results/sky130hd/ALU/base/1_synth.odb
  |            results/sky130hd/ALU/base/1_2_yosys.v
  |            logs/sky130hd/ALU/base/1_1_yosys.log
  |            reports/sky130hd/ALU/base/synth_stat.txt
  |
  |  docker cp: results/, reports/, logs/ -> host MyDesign/ALU/workspace/pnr/
  |
  v
[get_report tool]
  |
  |  Reads: MyDesign/ALU/workspace/pnr/results/sky130hd/ALU/base/
  |  Reads: MyDesign/ALU/workspace/pnr/reports/sky130hd/ALU/base/
  |  Parses: synth_stat.txt, timing reports, power reports
  |
  |  Returns: structured JSON metrics
  v
```

---

## config.mk Generation from spec.json/Verilog

### Template

The generated `config.mk` for a ChipAgent module targeting sky130hd:

```makefile
export PLATFORM    = sky130hd
export DESIGN_NAME = <MODULE_NAME>

export VERILOG_FILES = /workspace/src/<MODULE_NAME>.v
export SDC_FILE      = /workspace/constraint.sdc

export CORE_UTILIZATION = <40 default, configurable>
export PLACE_DENSITY    = <0.60 default, configurable>
export TNS_END_PERCENT  = 100
```

**Paths are container-relative.** The Verilog file and SDC are copied into the container's `/workspace/` directory. ORFS resolves the sky130hd platform files relative to its own installation at `/OpenROAD-flow-scripts/flow/platforms/sky130hd/`.

### constraint.sdc Generation

Following the sky130hd GCD example pattern (verified from ORFS source):

**Sequential module:**
```tcl
current_design <MODULE_NAME>

set clk_name  core_clock
set clk_port_name clock
set clk_period <PERIOD_NS>
set clk_io_pct 0.2

set clk_port [get_ports $clk_port_name]

create_clock -name $clk_name -period $clk_period $clk_port

set non_clock_inputs [all_inputs -no_clocks]

set_input_delay  [expr $clk_period * $clk_io_pct] -clock $clk_name $non_clock_inputs
set_output_delay [expr $clk_period * $clk_io_pct] -clock $clk_name [all_outputs]
```

**Combinational module:**
```tcl
current_design <MODULE_NAME>

set clk_period <PERIOD_NS>

create_clock -name virtual_clk -period $clk_period

set_input_delay  0.0 -clock virtual_clk [all_inputs]
set_output_delay 0.0 -clock virtual_clk [all_outputs]
set_max_delay $clk_period -from [all_inputs] -to [all_outputs]
```

### Key Differences from v1.1.2 SDC

| Aspect | v1.1.2 (nangate45) | v1.1.5 (sky130hd) |
|--------|---------------------|---------------------|
| Default clock period | 2.0 ns | 5.0 ns (sky130 is slower, 130nm) |
| Clock port name | `clock` (Chisel default) | `clock` (same, Chisel default) |
| SDC format | Minimal | Follows ORFS GCD example (more variables) |
| `current_design` | Present | Present |
| IO delay fraction | 20% of period | 20% of period |

### Generation Logic

1. Read `spec.json` for `clock_period_ns` (if present, use it; otherwise default 5.0 ns).
2. Read Verilog file, extract module name with `grep -m1 '^module '`.
3. Detect sequential vs combinational: `grep 'always @(posedge'` in Verilog.
4. If sequential, extract clock port name: look for `input clock` or `input clk` pattern in Verilog port list.
5. Write config.mk with absolute container paths.
6. Write constraint.sdc using the appropriate template.

---

## Container Workspace Layout

When the MCP Server prepares a run, the Docker container workspace looks like this:

```
/workspace/                        # Mounted or copied into container
  src/
    ALU.v                          # Compiled Verilog (copied from host)
  config.mk                       # Generated by MCP Server
  constraint.sdc                   # Generated by MCP Server

# ORFS creates these under /OpenROAD-flow-scripts/flow/:
/OpenROAD-flow-scripts/flow/
  results/sky130hd/ALU/base/       # Stage output files (.odb, .v, .sdc)
  logs/sky130hd/ALU/base/          # Stage log files
  reports/sky130hd/ALU/base/       # Stage report files
  objects/sky130hd/ALU/base/       # Internal working files
```

### Host Workspace Layout (after results are copied back)

```
MyDesign/ALU/workspace/
  generated/ALU.v                  # (existing, unchanged)
  sim/                             # (existing, unchanged)
  spec.json                        # (existing, unchanged)
  pnr/                             # (modified: ORFS-based layout)
    config.mk                      # Generated by MCP Server
    constraint.sdc                 # Generated by MCP Server
    results/                       # Copied from container
      sky130hd/ALU/base/
        1_synth.odb
        1_2_yosys.v
        2_floorplan.odb
        3_place.odb
        4_cts.odb (if sequential)
        5_route.odb
        6_final.gds
    logs/                          # Copied from container
      sky130hd/ALU/base/
        1_1_yosys.log
        2_1_floorplan.log
        ...
    reports/                       # Copied from container
      sky130hd/ALU/base/
        synth_stat.txt
        5_route_drc.rpt
        ...
```

---

## Docker Integration

### Container Lifecycle

The task2 specification mandates a **long-running container** model:

```bash
# One-time setup (done by initialize skill or user)
docker run -d --name orfs-agent \
  -v $(pwd)/design:/workspace \
  openroad/orfs:latest sleep infinity

# All subsequent operations use docker exec
docker exec orfs-agent make -C /OpenROAD-flow-scripts/flow \
  DESIGN_CONFIG=/workspace/config.mk synth
```

The MCP Server manages this lifecycle:
1. `check_environment` verifies the container exists and is running.
2. If container is not running, the tool returns instructions for starting it.
3. The MCP Server does NOT auto-start the container (avoid side effects in tool calls).

### File Transfer Strategy

**Option A (volume mount):** Mount host workspace directory as `/workspace` in container. Simplest, but requires the container to be started with the right mount point.

**Option B (docker cp):** Copy files in/out per stage. More flexible (works regardless of mount), but slower.

**Recommendation: Volume mount as primary, docker cp as fallback.** The `generate_config` tool writes files to the host workspace, which is visible to the container via the mount. The `get_report` tool reads from the same mounted directory. If the mount is not configured, fall back to `docker cp`.

### Local Fallback (No Docker)

When ORFS is installed locally (as it is on this machine at `~/OpenROAD-flow-scripts`), the MCP Server uses `make --file` directly:

```bash
make --file=$HOME/OpenROAD-flow-scripts/flow/Makefile \
  DESIGN_CONFIG=$(pwd)/MyDesign/ALU/workspace/pnr/config.mk synth
```

This requires adjusting config.mk paths to be host-absolute instead of container-relative. The `orfs-runner.ts` module abstracts this difference.

### Environment Detection Flow

```
[detect-env.sh] (updated)
  |
  |  1. Check Docker: docker --version, docker info
  |  2. Check ORFS container: docker inspect orfs-agent
  |  3. Check local ORFS: ~/OpenROAD-flow-scripts/flow/Makefile
  |  4. Check sky130hd PDK:
  |     - Container: docker exec orfs-agent test -f /OpenROAD-flow-scripts/flow/platforms/sky130hd/config.mk
  |     - Local: test -f ~/OpenROAD-flow-scripts/flow/platforms/sky130hd/config.mk
  |  5. Check tools in container: docker exec orfs-agent yosys -version / openroad -version
  |
  v
[.chipagent/env.json] (updated schema)
{
  "docker": {
    "installed": true,
    "version": "27.x",
    "orfs_container": {
      "exists": true,
      "running": true,
      "name": "orfs-agent",
      "image": "openroad/orfs:latest"
    }
  },
  "pdk": {
    "sky130hd": {
      "installed": true,
      "source": "container",
      "path": "/OpenROAD-flow-scripts/flow/platforms/sky130hd"
    },
    "nangate45": { ... }
  },
  "orfs": {
    "installed": true,
    "source": "local",
    "path": "/home/mingzhenjia/OpenROAD-flow-scripts",
    "flow_dir": "/home/mingzhenjia/OpenROAD-flow-scripts/flow"
  },
  "capabilities": {
    "can_compile": true,
    "can_lint": true,
    "can_simulate": true,
    "can_synthesize": true,
    "can_pnr": true,
    "can_gds": true,
    "can_orfs_docker": true,
    "can_orfs_local": true
  }
}
```

---

## sky130hd Platform Constants

From the verified `~/OpenROAD-flow-scripts/flow/platforms/sky130hd/config.mk`:

| Constant | Value | Notes |
|----------|-------|-------|
| PROCESS | 130 (nm) | Much larger feature size than nangate45 |
| TECH_LEF | `sky130_fd_sc_hd.tlef` | Technology LEF |
| SC_LEF | `sky130_fd_sc_hd_merged.lef` | Standard cell LEF |
| LIB_FILES | `sky130_fd_sc_hd__tt_025C_1v80.lib` | Typical corner, 25C, 1.8V |
| PLACE_SITE | `unithd` | Differs from nangate45 `FreePDK45_38x28_10R_NP_162NW_34O` |
| PLACE_DENSITY | 0.60 (default) | Higher than nangate45 0.30 |
| TAP_CELL_NAME | `sky130_fd_sc_hd__tapvpwrvgnd_1` | Differs from nangate45 `TAPCELL_X1` |
| FILL_CELLS | `sky130_fd_sc_hd__fill_1/2/4/8` | Differs from nangate45 |
| MIN_ROUTING_LAYER | met1 | |
| MAX_ROUTING_LAYER | met5 | Only 5 metal layers (vs nangate45's 10) |
| MIN_CLK_ROUTING_LAYER | met3 | |
| IO_PLACER_H/V | met3 / met2 | |
| ABC_DRIVER_CELL | `sky130_fd_sc_hd__buf_1` | |
| RCX_RULES | `rcx_patterns.rules` (symlink to sky130hs) | |
| PWR_NETS_VOLTAGES | VDD 1.8 | |
| GND_NETS_VOLTAGES | VSS 0.0 | |
| PDN_TCL | `pdn.tcl` (platform-specific) | |

**Key difference from nangate45:** sky130hd has only 5 metal layers (met1-met5), not 10. The default PLACE_DENSITY is 0.60, not 0.30. Clock period must be more relaxed (5-10 ns typical for small designs, vs 2 ns for nangate45).

---

## ORFS Make Targets Mapping

Each ORFS stage maps to a make target. The MCP `run_stage` tool accepts these as the `stage` parameter.

| Stage | Make Target | Dependencies | Key Outputs |
|-------|-------------|--------------|-------------|
| Synthesis | `synth` | RTL Verilog, SDC, .lib, .lef | `1_synth.odb`, `1_2_yosys.v`, `synth_stat.txt` |
| Floorplan | `floorplan` | synth output | `2_floorplan.odb`, `2_floorplan.sdc` |
| Placement | `place` | floorplan output | `3_place.odb`, `3_place.sdc` |
| CTS | `cts` | place output | `4_cts.odb` |
| Routing | `route` | cts output | `5_route.odb`, `5_route_drc.rpt` |
| Finishing | `finish` | route output | `6_final.gds`, final reports |

**Note:** ORFS handles dependencies internally. Running `make ... finish` will automatically run all prerequisite stages. However, the Skill should invoke stages individually to provide per-stage progress reporting and metric extraction.

### Clean Targets

Each stage has a clean target: `clean_synth`, `clean_floorplan`, `clean_place`, `clean_cts`, `clean_route`, `clean_finish`. Plus `clean_all` for full reset. These are useful for retry logic.

---

## Suggested Build Order

### Phase 1: MCP Server Scaffold + Environment Detection

**Build:**
1. Create `mcp-server/` directory with `package.json`, `tsconfig.json`, basic project structure.
2. Install `@modelcontextprotocol/sdk`, `zod`, TypeScript.
3. Implement `src/index.ts` with McpServer + StdioServerTransport.
4. Implement `check_environment` tool (docker detection, ORFS detection, sky130hd validation).
5. Update `scripts/detect-env.sh` to add Docker + sky130hd detection.
6. Create `.mcp.json` at project root to register the server.

**Test:** `claude mcp list` shows `chipagent-orfs` server. `check_environment` returns accurate status.

**Rationale:** Must be first -- all subsequent tools depend on the MCP Server scaffold and environment detection.

### Phase 2: Config Generation (config.mk + constraint.sdc)

**Build:**
1. Implement `config-gen.ts` with config.mk and SDC templates for sky130hd.
2. Implement `generate_config` MCP tool.
3. Handle sequential vs combinational detection.
4. Handle spec.json clock_period_ns reading.

**Test:** `generate_config` for ALU produces valid config.mk and constraint.sdc. SDC format matches ORFS sky130hd/gcd example.

**Rationale:** Config generation is prerequisite for any ORFS make invocation. No Docker dependency for testing (just file generation).

### Phase 3: ORFS Runner + Synthesis Stage

**Build:**
1. Implement `orfs-runner.ts` with Docker exec and local make fallback.
2. Implement `run_stage` MCP tool.
3. Implement `get_log` MCP tool.
4. Test with `synth` target only (fastest stage, ~5-15s).

**Test:** `run_stage(stage="synth")` produces gate-level netlist. `get_log(stage="synth")` returns Yosys log.

**Rationale:** Synthesis is the first ORFS stage and fastest to iterate on. Validates the full Docker exec pipeline.

### Phase 4: Metric Extraction + Full Flow

**Build:**
1. Implement `metrics.ts` with parsers for synth_stat.txt, timing reports, power reports, DRC reports.
2. Implement `get_report` MCP tool.
3. Test full 6-stage flow: synth -> floorplan -> place -> cts -> route -> finish.
4. Verify GDS output from finish stage.

**Test:** `get_report(stage="all")` returns complete PPA metrics. GDS file is produced.

**Rationale:** Metric extraction validates that ORFS outputs are parseable. Full flow validates end-to-end.

### Phase 5: Skill Rewrite + PPA Report

**Build:**
1. Rewrite `skills/pnr/SKILL.md` to use MCP tools instead of bash scripts.
2. Update `agents/pnr-report-formatter.md` for ORFS report format.
3. Update `skills/initialize/SKILL.md` for Docker + sky130hd detection.
4. Implement per-stage progress reporting in the Skill.
5. Implement PPA summary report format.

**Test:** `/chip-agent:pnr ALU` runs full flow end-to-end and presents formatted PPA report.

**Rationale:** Skill depends on all MCP tools being functional. Report formatter needs real ORFS output to validate against.

### Phase 6: Auto-Retry + Error Diagnosis (Stretch)

**Build:**
1. Add timing violation detection in Skill (check WNS from get_report).
2. Implement clock period relaxation retry (increase period, re-run from synth).
3. Add placement density adjustment for congestion failures.
4. Add error type classification from log analysis.

**Test:** Module with tight timing constraint triggers auto-retry with relaxed period and succeeds.

**Rationale:** Retry logic depends on working metrics extraction and stage re-run capability. This is the "satisfaction requirements" level from task2.

---

## Anti-Patterns to Avoid

### Do NOT Run ORFS from Host Against Container Paths

ORFS config.mk paths must be container-relative when using Docker exec. A config.mk with host paths like `/home/mingzhenjia/...` will fail inside the container.

### Do NOT Skip `synth` When Re-Running from a Later Stage

ORFS's make tracks dependencies via ODB files. But if config.mk or SDC changes, all stages should re-run. Use `clean_all` before re-running when parameters change.

### Do NOT Use console.log() in MCP Server

MCP stdio transport uses stdout for JSON-RPC messages. Any `console.log()` corrupts the protocol. Use `console.error()` or a file-based logger.

### Do NOT Assume 2ns Clock Period for sky130hd

sky130hd is 130nm technology. Typical timing is 5-10ns for small modules. Using 2ns (the nangate45 default) will cause immediate timing violations.

### Do NOT Hard-Code ORFS Output Directory Structure

ORFS directories follow the pattern `<type>/sky130hd/<DESIGN_NAME>/base/`. The `base` is the FLOW_VARIANT (default). Do not assume a flat structure.

### Do NOT Mount the Entire ChipAgent Directory into Docker

Only mount the per-module workspace. Mounting the entire plugin directory exposes source code, .claude-plugin/, and other sensitive files to the container.

### Do NOT Block on Docker Operations Without Timeout

ORFS routing can take 10+ minutes for medium designs. All `docker exec` calls must have configurable timeouts (default: 10 minutes per stage).

---

## Integration Points Summary

| Integration Point | From | To | Data Format |
|-------------------|------|-----|-------------|
| Claude Code -> MCP Server | Skill (SKILL.md) | MCP tool calls | JSON-RPC via stdio |
| MCP Server -> Docker | orfs-runner.ts | docker exec commands | Shell commands |
| MCP Server -> ORFS | docker exec | make targets | DESIGN_CONFIG env var |
| ORFS -> Results | make output | results/logs/reports dirs | ODB, Verilog, GDS, text |
| MCP Server -> Claude Code | MCP tool return | Skill reads result | JSON (structured metrics) |
| spec.json -> config.mk | config-gen.ts | ORFS config | Makefile format |
| Verilog -> SDC | config-gen.ts | ORFS constraints | Tcl SDC format |
| env.json -> MCP Server | detect-env.sh | server configuration | JSON |

---

## Sources

- ORFS sky130hd platform config: `/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/sky130hd/config.mk` (verified locally, 2026-04-01) [HIGH confidence]
- ORFS sky130hd GCD design config: `/home/mingzhenjia/OpenROAD-flow-scripts/flow/designs/sky130hd/gcd/config.mk` (verified locally) [HIGH confidence]
- ORFS sky130hd GCD constraint.sdc: `/home/mingzhenjia/OpenROAD-flow-scripts/flow/designs/sky130hd/gcd/constraint.sdc` (verified locally) [HIGH confidence]
- ORFS Makefile targets: `/home/mingzhenjia/OpenROAD-flow-scripts/flow/Makefile` (verified locally, grep confirmed synth/floorplan/place/cts/route/finish targets) [HIGH confidence]
- ORFS variables.mk: `/home/mingzhenjia/OpenROAD-flow-scripts/flow/scripts/variables.mk` (verified locally, directory layout confirmed) [HIGH confidence]
- MCP TypeScript SDK: [github.com/modelcontextprotocol/typescript-sdk](https://github.com/modelcontextprotocol/typescript-sdk) [HIGH confidence]
- MCP Server build guide: [modelcontextprotocol.io/docs/develop/build-server](https://modelcontextprotocol.io/docs/develop/build-server) [HIGH confidence]
- Claude Code MCP configuration: [code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp) [HIGH confidence]
- @modelcontextprotocol/sdk npm: [npmjs.com/package/@modelcontextprotocol/sdk](https://www.npmjs.com/package/@modelcontextprotocol/sdk) [HIGH confidence]
- ORFS tutorial: [github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/tutorials/FlowTutorial.md](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/tutorials/FlowTutorial.md) [HIGH confidence]
- ORFS adding new designs: [github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/user/AddingNewDesign.md](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/user/AddingNewDesign.md) [HIGH confidence]
- task2.md requirements: `/home/mingzhenjia/ChipAgent/task2.md` (verified locally) [HIGH confidence]
- ChipAgent v1.1.2 architecture: `/home/mingzhenjia/ChipAgent/.planning/research/ARCHITECTURE.md` (previous version, used as baseline) [HIGH confidence]
- Existing pnr skill: `/home/mingzhenjia/ChipAgent/skills/pnr/SKILL.md` (verified locally) [HIGH confidence]
- Existing detect-env.sh: `/home/mingzhenjia/ChipAgent/scripts/detect-env.sh` (verified locally) [HIGH confidence]
- Existing synth.sh/pnr.sh/synth.tcl/pnr.tcl: verified locally, used to understand current architecture [HIGH confidence]
