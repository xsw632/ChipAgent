# Feature Landscape

**Domain:** MCP Server-driven ORFS/sky130hd backend for ChipAgent Claude Code plugin
**Researched:** 2026-04-01
**Milestone:** v1.1.5 sky130hd MCP Backend
**Target level:** task2 进阶要求 (full-flow MCP tools, auto-advance 6 stages, per-stage metrics, PPA summary)

## Context: What Exists vs What Is New

The existing v1.1.2 PnR pipeline uses standalone Tcl scripts (synth.tcl, pnr.tcl) running Yosys and OpenROAD directly on the host against nangate45 PDK. The v1.1.5 milestone **replaces** this with:

1. An MCP Server (TypeScript) that wraps `docker exec` calls into the `openroad/orfs:latest` container
2. ORFS `make` targets instead of standalone Tcl scripts
3. sky130hd PDK instead of nangate45
4. Auto-generated `config.mk` and `constraint.sdc` for ORFS consumption
5. Per-stage metric extraction from ORFS logs/reports/metadata.json
6. PPA summary report replacing the current pnr-report-formatter agent

**Dependency:** Compiled Verilog from existing `/chip-agent:compile` or `/chip-agent:workflow` pipeline (unchanged).

---

## Table Stakes

Features users (and the task2 grading rubric) expect. Missing = incomplete submission.

| # | Feature | Why Expected | Complexity | Dependencies | Notes |
|---|---------|-------------|------------|--------------|-------|
| T1 | **MCP Server with `run_stage` tool** | task2 requires MCP Server wrapping ORFS make targets; `run_stage` is the primary tool for executing any of the 6 ORFS stages via `docker exec` | Med | Docker running, container alive | Must accept `stage` (synth/floorplan/place/cts/route/finish) and `design_config` path. Executes `docker exec orfs-agent make -C /OpenROAD-flow-scripts/flow DESIGN_CONFIG=/workspace/config.mk <stage>`. Returns stdout/stderr and exit code. |
| T2 | **MCP Server with `get_report` tool** | task2 requires at least 2 MCP tools; `get_report` reads back log/report files from the container for a given stage | Med | T1 (stages must have run) | Reads from `logs/sky130hd/<DESIGN>/base/` and `reports/sky130hd/<DESIGN>/base/` inside container via `docker exec cat`. Returns file contents as text. |
| T3 | **sky130hd `config.mk` auto-generation** | ORFS make flow requires a design-level config.mk; task2 rubric checks that Agent auto-generates it | Med | Verilog file exists, module name known | Must set: `PLATFORM=sky130hd`, `DESIGN_NAME`, `VERILOG_FILES=/workspace/<module>.v`, `SDC_FILE=/workspace/constraint.sdc`, `CORE_UTILIZATION` (default 40). Write to `design/config.mk` (host) which maps to `/workspace/config.mk` (container). |
| T4 | **sky130hd `constraint.sdc` auto-generation** | ORFS requires SDC; existing generate_sdc.sh produces nangate45-style SDC; must produce ORFS-compatible SDC for sky130hd | Low | Verilog file (for sequential/combinational detection) | Reuse existing sequential-vs-combinational detection logic. SDC format matches ORFS gcd example: `create_clock -name core_clock -period $clk_period [get_ports clk]` with 20% I/O delay. Clock port name must match actual Verilog port (Chisel uses `clock` not `clk`). |
| T5 | **Skill orchestrating full 6-stage ORFS flow** | 进阶要求 requires Skill auto-advancing all stages: synth -> floorplan -> place -> cts -> route -> finish | High | T1, T3, T4, MCP server running | Rewrite `/chip-agent:pnr` to call MCP tools sequentially. Each stage: call `run_stage`, check exit code, extract per-stage metrics via `get_report`, proceed or stop. Must handle the 6 ORFS make targets in order. |
| T6 | **Per-stage metric extraction** | 进阶要求 explicitly requires per-stage key metric extraction (area, WNS/TNS, DRC) | Med | T2 (report retrieval) | After each stage completes, parse logs/reports for stage-specific metrics. synth: cell count, area. floorplan: core area, utilization. place: density, congestion. cts: clock skew. route: WNS, TNS, DRC count. finish: final area, power, timing. |
| T7 | **PPA summary report** | 进阶要求 requires PPA (Performance, Power, Area) summary at end of flow | Med | T6 (all metrics collected) | Aggregate metrics from all stages into formatted report. Performance = WNS/TNS/clock period. Power = total/internal/switching/leakage in uW. Area = cell count, design area, utilization. Display in conversation. |
| T8 | **Docker container lifecycle management** | task2 specifies long-running container pattern with `docker run -d` + volume mount + `docker exec` | Low | Docker installed | `docker run -d --name orfs-agent -v $(pwd)/design:/workspace openroad/orfs:latest sleep infinity`. MCP server must check container exists and is running before executing. Container name configurable. |
| T9 | **`.mcp.json` project-scoped configuration** | task2 submission structure expects `.claude/.mcp.json` configuring the MCP server | Low | T1 server built | stdio transport: `{ "mcpServers": { "chip-backend": { "type": "stdio", "command": "node", "args": ["mcp-server/dist/index.js"] } } }`. Must work with `claude mcp add` or direct file edit. |
| T10 | **`/chip-agent:initialize` Docker + sky130hd detection** | Users need to know if Docker and the ORFS container are available before running PnR | Low | Existing initialize skill | Add Docker detection (`docker --version`), container status check (`docker ps --filter name=orfs-agent`), and sky130hd PDK availability check (inside container: `test -d /OpenROAD-flow-scripts/flow/platforms/sky130hd`). Update env.json with new capability flags. |

---

## Differentiators

Features that exceed 进阶要求, moving toward 满分要求. Not required but valued for higher marks.

| # | Feature | Value Proposition | Complexity | Dependencies | Notes |
|---|---------|-------------------|------------|--------------|-------|
| D1 | **Failure diagnosis by error type** | 满分要求: auto-diagnose timing violations, congestion, DRC | Med | T6 metrics | Classify failures: timing (WNS < 0), congestion (placement density too high), DRC (violations > 0). Map to specific remediation parameters. |
| D2 | **Parameter retry on failure** | 满分要求: adjust PLACE_DENSITY, CLOCK_PERIOD and re-run | High | D1, T3 (regenerate config.mk) | On timing failure: increase clock period by 50% (reuse existing v1.1.2 pattern). On congestion: decrease PLACE_DENSITY. On DRC: increase ROUTING_LAYER_ADJUSTMENT. Regenerate config.mk + SDC, clean affected stages, re-run. Max 3 attempts. |
| D3 | **Multi-run QoR comparison** | 满分要求: compare different configuration results side by side | Med | D2 (multiple runs needed) | Store each run's PPA summary with config parameters. Display comparison table: run#, clock_period, place_density, WNS, TNS, power, area. Let user pick best. |
| D4 | **MCP `get_metrics` tool** | Extract structured JSON metrics from ORFS metadata.json instead of parsing logs | Low | T1 (container running), ORFS generates metadata.json after finish | `docker exec orfs-agent cat results/sky130hd/<DESIGN>/base/metadata.json`. More reliable than log parsing. Falls back to log parsing if metadata.json missing. |
| D5 | **MCP `clean_stage` tool** | Clean a specific stage's outputs to enable selective re-run | Low | T1 | `docker exec orfs-agent make -C /OpenROAD-flow-scripts/flow DESIGN_CONFIG=/workspace/config.mk clean_<stage>`. Useful for retry workflows. |
| D6 | **MCP `check_container` tool** | Health check: verify container running, tools accessible, PDK present | Low | T8 | Returns JSON with container status, tool versions, PDK path validity. Prevents cryptic failures when container is down. |
| D7 | **Layout image extraction** | ORFS finish stage generates visualization images (final_all.webp etc.) in reports/ | Low | T5 (finish stage complete) | Copy images from container to host workspace. Reference in PPA report. Provides visual verification of layout quality. |

---

## Anti-Features

Features to explicitly NOT build. These would waste time or cause problems.

| # | Anti-Feature | Why Avoid | What to Do Instead |
|---|-------------|-----------|-------------------|
| A1 | **Run ORFS tools natively (no Docker)** | task2 explicitly requires Docker-based execution. Native Yosys/OpenROAD would bypass the Docker requirement and create environment inconsistency. | Always use `docker exec` through the MCP server. The existing v1.1.2 native Tcl scripts become dead code for this milestone. |
| A2 | **Build custom Tcl scripts for sky130hd** | ORFS Makefile already contains battle-tested Tcl scripts for each stage. Custom scripts duplicate effort and miss ORFS optimizations (timing repair, filler insertion, PDN generation). | Use ORFS `make` targets which invoke ORFS's own Tcl scripts internally. |
| A3 | **Multi-PDK support** | Out of scope per PROJECT.md. sky130hd only per task2 requirement. Adding nangate45/asap7 support adds complexity with zero grading benefit. | Hardcode sky130hd in config.mk generation. Add multi-PDK as future milestone. |
| A4 | **Hierarchical synthesis** | Chisel-generated modules are small enough for flat synthesis. ORFS hierarchical flow adds complexity. | Use flat ORFS flow (default). |
| A5 | **MCP HTTP/SSE remote transport** | Overkill for local plugin. stdio transport is simpler, has no network overhead, and auto-manages server lifecycle. | Use stdio transport exclusively. MCP server runs as child process of Claude Code. |
| A6 | **Persistent container state between sessions** | Creates stale state bugs. ORFS outputs depend on config.mk which may change between runs. | Always `clean_all` before full flow run. Host-side volume mount preserves user files. |
| A7 | **GDS export via standalone KLayout script** | ORFS `make finish` stage already handles GDS merge via its own KLayout integration. The v1.1.2 def2gds.py becomes unnecessary. | Let ORFS finish stage produce `6_final.gds`. Copy it from container. |
| A8 | **DRC/LVS verification beyond ORFS built-in** | Out of scope per PROJECT.md. Requires KLayout ruledecks and Magic. ORFS finish stage does basic DRC check already. | Rely on ORFS built-in DRC check in route/finish stages. Report DRC count from logs. |
| A9 | **Watch mode / auto-restart on file change** | Learned from v1.0: creates infinite loops. Explicit slash command invocation is safer. | User explicitly invokes `/chip-agent:pnr` when ready. |
| A10 | **Multiple simultaneous container instances** | Adds orchestration complexity. Single design at a time is sufficient for task2. | Single named container `orfs-agent`. One design flow at a time. |

---

## Feature Dependencies

```
T8 (Docker container) ─────────────────────────────────────┐
                                                            v
T3 (config.mk gen) ──┐                            T1 (run_stage tool)
                      ├──> T5 (6-stage Skill) ──> T6 (per-stage metrics)
T4 (SDC gen) ─────────┘         |                          |
                                v                          v
                      T2 (get_report tool)         T7 (PPA summary)
                                                           |
T10 (initialize update)                             D1 (failure diagnosis)
                                                           |
T9 (.mcp.json)                                     D2 (parameter retry)
                                                           |
                                                    D3 (QoR comparison)
```

Key ordering constraints:
- T1 and T2 (MCP tools) must exist before T5 (orchestrating Skill) can call them
- T3 and T4 (config generation) must exist before T5 can prepare ORFS inputs
- T8 (container) must be running before T1 can execute anything
- T6 (metrics) feeds into T7 (PPA report) and D1 (diagnosis)
- D1 (diagnosis) enables D2 (retry) enables D3 (comparison)

---

## MCP Tool Specification Detail

### Tool 1: `run_stage`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `stage` | string enum | YES | One of: `synth`, `floorplan`, `place`, `cts`, `route`, `finish` |
| `design_config` | string | YES | Path to config.mk inside container (default: `/workspace/config.mk`) |
| `container_name` | string | NO | Docker container name (default: `orfs-agent`) |

**Returns:** `{ success: boolean, exit_code: number, stdout: string, stderr: string, duration_ms: number }`

**Implementation:** `docker exec <container> make -C /OpenROAD-flow-scripts/flow DESIGN_CONFIG=<design_config> <stage>`

### Tool 2: `get_report`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `design_name` | string | YES | Module name (e.g., `ALU`) |
| `stage` | string enum | YES | Stage to get report for |
| `report_type` | string enum | NO | `log`, `report`, `result` (default: `log`) |
| `container_name` | string | NO | Docker container name (default: `orfs-agent`) |

**Returns:** `{ content: string, path: string }` -- file contents and container-internal path

**Implementation:** `docker exec <container> cat <path>` where path is computed from stage number and type:
- Logs: `logs/sky130hd/<DESIGN>/base/<stage_prefix>_*.log`
- Reports: `reports/sky130hd/<DESIGN>/base/<stage_prefix>_*.rpt`
- Results: `results/sky130hd/<DESIGN>/base/<stage_prefix>_*`

### Tool 3 (differentiator): `get_metrics`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `design_name` | string | YES | Module name |
| `container_name` | string | NO | Docker container name |

**Returns:** Structured JSON with all ORFS metrics from `metadata.json`

### Tool 4 (differentiator): `clean_stage`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `stage` | string enum | YES | Stage to clean |
| `design_config` | string | YES | Path to config.mk |
| `container_name` | string | NO | Docker container name |

**Implementation:** `docker exec <container> make -C /OpenROAD-flow-scripts/flow DESIGN_CONFIG=<design_config> clean_<stage>`

### Tool 5 (differentiator): `check_container`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `container_name` | string | NO | Docker container name |

**Returns:** `{ running: boolean, tools: { yosys: string, openroad: string, klayout: string }, pdk: { sky130hd: boolean, path: string } }`

---

## config.mk Generation Detail

The auto-generated `config.mk` for a ChipAgent module must produce:

```makefile
export PLATFORM    = sky130hd
export DESIGN_NAME = <ModuleName>
export VERILOG_FILES = /workspace/<ModuleName>.v
export SDC_FILE      = /workspace/constraint.sdc

export CORE_UTILIZATION ?= 40
export PLACE_DENSITY    ?= 0.60
export TNS_END_PERCENT  ?= 100
```

Key notes:
- Paths use container-internal `/workspace/` prefix (volume-mounted from host `design/` directory)
- `CORE_UTILIZATION` defaults to 40 (matching ORFS gcd example); can be overridden for retry
- `PLACE_DENSITY` defaults to 0.60; adjustable for congestion retry
- `?=` syntax allows command-line override without regenerating config.mk
- ORFS platform-level config.mk handles all PDK paths (LIB_FILES, SC_LEF, GDS_FILES, etc.)

## constraint.sdc Generation Detail

For sequential modules (clock detected in Verilog):

```tcl
current_design <ModuleName>

set clk_name  core_clock
set clk_port  [get_ports clock]
set clk_period <period_ns>

create_clock -name $clk_name -period $clk_period $clk_port

set non_clock_inputs [lsearch -all -inline -not -exact [all_inputs] $clk_port]
set_input_delay  [expr $clk_period * 0.2] -clock $clk_name $non_clock_inputs
set_output_delay [expr $clk_period * 0.2] -clock $clk_name [all_outputs]
```

For combinational modules (no clock):

```tcl
current_design <ModuleName>

set clk_period <period_ns>

create_clock -name virtual_clk -period $clk_period

set_input_delay  0.0 -clock virtual_clk [all_inputs]
set_output_delay 0.0 -clock virtual_clk [all_outputs]
set_max_delay $clk_period -from [all_inputs] -to [all_outputs]
```

Note: Chisel `io.clock` compiles to port named `clock` in generated Verilog, not `clk` (which is ORFS gcd convention). SDC generation must use the actual port name from the Verilog.

---

## Per-Stage Metrics Extraction Detail

| Stage | ORFS Make Target | Key Metrics to Extract | Source File(s) |
|-------|-----------------|----------------------|----------------|
| Synthesis | `synth` | Cell count, design area (um2), buffer count | `logs/sky130hd/<DESIGN>/base/1_1_yosys.log` |
| Floorplan | `floorplan` | Core area (um2), die area (um2), utilization % | `logs/sky130hd/<DESIGN>/base/2_1_floorplan.log` |
| Placement | `place` | Placement density, HPWL (half-perimeter wirelength), congestion % | `logs/sky130hd/<DESIGN>/base/3_5_place_dp.log` |
| CTS | `cts` | Clock skew (ps), buffer count, max latency | `logs/sky130hd/<DESIGN>/base/4_1_cts.log` |
| Route | `route` | WNS (ns), TNS (ns), DRC violation count, wirelength | `logs/sky130hd/<DESIGN>/base/5_2_route.log`, `reports/sky130hd/<DESIGN>/base/5_route_drc.rpt` |
| Finish | `finish` | Final area, final WNS/TNS, total power (uW), GDS file path | `logs/sky130hd/<DESIGN>/base/6_report.log`, `results/sky130hd/<DESIGN>/base/6_final.gds` |

Alternative: After `make finish`, ORFS generates `metadata.json` in the logs directory with all metrics in structured JSON. The `get_metrics` tool (D4) can read this directly instead of parsing individual log files.

---

## PPA Report Format

The PPA summary report adapts the existing pnr-report-formatter agent pattern for ORFS outputs:

```
=== PPA Report: <ModuleName> (sky130hd) ===

Performance:
  Clock Period:  XX.X ns
  WNS:           X.XX ns (MET/VIOLATED)
  TNS:           X.XX ns
  Clock Skew:    X.XX ps

Power:
  Internal:      XX.X uW  (XX.X%)
  Switching:     XX.X uW  (XX.X%)
  Leakage:       XX.X uW  (XX.X%)
  Total:         XX.X uW

Area:
  Cell Count:    XXX
  Design Area:   XXXX um^2
  Utilization:   XX%

DRC:             X violations

Per-Stage Summary:
  [1] Synthesis:  XXX cells, XXX um^2
  [2] Floorplan:  XXX um^2 die, XX% util
  [3] Placement:  density X.XX
  [4] CTS:        XX buffers, X.XX ps skew
  [5] Route:      WNS X.XX ns, X DRC
  [6] Finish:     GDS exported

Artifacts:
  Config:    design/config.mk
  SDC:       design/constraint.sdc
  GDS:       results/sky130hd/<DESIGN>/base/6_final.gds
  Logs:      logs/sky130hd/<DESIGN>/base/
  Reports:   reports/sky130hd/<DESIGN>/base/
```

---

## MVP Recommendation

Prioritize for 进阶要求 level (minimum viable for full marks at that tier):

1. **T8** - Docker container lifecycle (foundation for everything)
2. **T1** - `run_stage` MCP tool (core execution capability)
3. **T2** - `get_report` MCP tool (observability)
4. **T3** - config.mk auto-generation (ORFS input)
5. **T4** - constraint.sdc auto-generation (ORFS input)
6. **T5** - 6-stage orchestrating Skill (the main workflow)
7. **T6** - Per-stage metric extraction (required for 进阶)
8. **T7** - PPA summary report (required for 进阶)
9. **T9** - .mcp.json configuration (submission requirement)
10. **T10** - Initialize update (user-facing polish)

**Defer to stretch goals:** D1-D7 (failure diagnosis, retry, QoR comparison, extra MCP tools)

**Implementation order rationale:**
- T8 first because nothing works without a running container
- T1+T2 next because they are the MCP foundation the Skill calls
- T3+T4 can be built in parallel (independent input file generators)
- T5 ties everything together once tools and inputs exist
- T6+T7 are the metrics layer on top of the stage execution
- T9+T10 are configuration/polish best done last

---

## Sources

- [ORFS GitHub Repository](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts)
- [ORFS Flow Tutorial](https://openroad-flow-scripts.readthedocs.io/en/latest/tutorials/FlowTutorial.html)
- [ORFS Flow Variables](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html)
- [ORFS Adding New Designs](https://openroad-flow-scripts.readthedocs.io/en/latest/user/AddingNewDesign.html)
- [ORFS sky130hd platform config.mk](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/flow/platforms/sky130hd/config.mk)
- [ORFS sky130hd gcd design config.mk](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/flow/designs/sky130hd/gcd/config.mk)
- [ORFS Metrics Documentation](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/contrib/Metrics.md)
- [ORFS DeepWiki Overview](https://deepwiki.com/The-OpenROAD-Project/OpenROAD-flow-scripts)
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)
- [MCP Official Specification](https://modelcontextprotocol.io/specification/2025-03-26)
- [Claude Code MCP Documentation](https://code.claude.com/docs/en/mcp)
- [ORFS Docker Shell Documentation](https://openroad-flow-scripts.readthedocs.io/en/latest/user/DockerShell.html)
