# Project Research Summary: ChipAgent v1.1.5

**Project:** ChipAgent — Claude Code plugin for Chisel-to-GDS automation
**Milestone:** v1.1.5 sky130hd MCP Backend
**Domain:** EDA (Electronic Design Automation) — ASIC backend automation, cloud-first execution model
**Researched:** 2026-04-01
**Confidence:** HIGH

---

## Executive Summary

ChipAgent v1.1.5 replaces the v1.1.2 nangate45 standalone Tcl-based PnR flow with an MCP-Server-driven, Docker-based ORFS make flow targeting the sky130hd open-source PDK. This is a **fundamental architectural shift from direct tool invocation to cloud-native RPC patterns** — Claude Code no longer calls shell scripts, but instead calls MCP tools which manage Docker containers wrapping the ORFS flow.

**The recommended approach:** Build an MCP TypeScript server exposing five core tools (`check_environment`, `generate_config`, `run_stage`, `get_report`, `get_log`) that wrap ORFS make targets. The server handles config.mk and constraint.sdc generation, Docker container lifecycle, and metric extraction from ORFS outputs. This approach separates concerns (tool invocation from orchestration), enables testing in isolation, and aligns with task2's explicit Docker-first requirement.

**Key risks:** (1) **MCP protocol fragility** — any stdout contamination kills the server; (2) **Complete parameter retraining** — sky130hd's layer/cell names, default clock periods, and process constraints are different from nangate45 at every point; (3) **Container lifecycle management** — orphaned containers and mount-path translation errors are high-probability integration bugs; (4) **Extended tool execution** — ORFS PnR can take 10+ minutes, exceeding MCP timeout defaults. Mitigation: strict logging discipline, comprehensive pitfall prevention checklist, defensive path mapping, and explicit timeout configuration.

---

## Key Findings

### Recommended Stack

The v1.1.5 stack introduces **three new technology layers** while keeping the existing compilation pipeline (Chisel 3.6.1 → sbt → FIRRTL → Verilator) unchanged.

**MCP Transport Layer:**
- **@modelcontextprotocol/sdk v1.29.0** (TypeScript) — official production-stable MCP server SDK. v2 is pre-alpha (Q1 2026 target missed). Provides McpServer, StdioServerTransport, Zod integration.
- **Zod v3.25.0** — schema validation for tool inputs. Required peer dependency of SDK. Pin to 3.x (SDK uses zod/v4 internally but backwards-compatible with 3.25+).
- **Node.js >=22.6.0** — system has v24.14.0 with native TypeScript type-stripping (no build step needed). StdioServerTransport uses node stdio pipes.

**ASIC Flow Layer:**
- **ORFS Makefile** (OpenROAD-flow-scripts) — installed locally at ~/OpenROAD-flow-scripts. Provides six staged make targets (synth, floorplan, place, cts, route, finish) with full sky130hd platform support. Replaces standalone Tcl scripts with upstream-maintained, battle-tested flow.
- **sky130hd PDK** — bundled in ORFS at platforms/sky130hd/. Open-source 130nm process with 5+1 metal layers, verified locally with all required files (liberty, LEF, GDS, RC extraction, PDN/tapcell Tcl).

**Verified Tool Versions (2026-04-01):**
- Yosys 0.53+26, OpenROAD 26Q1-951-g6975124cf2, KLayout installed (was missing in v1.1.2, now present)

**Key architectural decision:** stdio transport for MCP (not HTTP/SSE). Claude Code runs locally. Stdio is the standard for local MCP servers — no network, no authentication, simplest setup.

See STACK.md for detailed version compatibility, integration points, and alternatives considered.

---

### Expected Features

**Table Stakes (must have):**
- MCP server with `run_stage` tool — execute any of 6 ORFS make stages via docker exec
- MCP server with `get_report` tool — extract stage-specific metrics
- sky130hd config.mk auto-generation with ORFS-compatible parameters
- sky130hd constraint.sdc auto-generation with 10ns default clock (not 2ns)
- 6-stage orchestrating Skill calling MCP tools sequentially
- Per-stage metric extraction from ORFS outputs
- PPA summary report aggregating metrics (Performance, Power, Area, DRC)
- Docker container lifecycle with long-running container pattern
- .mcp.json configuration for Claude Code registration

**Differentiators (for higher marks):**
- Failure diagnosis by error type (timing vs congestion vs DRC)
- Parameter retry on failure (clock period increase, density reduction)
- Multi-run QoR comparison tables
- Additional MCP tools: `get_metrics`, `clean_stage`, `check_container`
- Layout image extraction from ORFS finish stage

**Anti-Features (NOT building):**
- Native ORFS execution (task2 requires Docker)
- Custom Tcl scripts (ORFS Makefile is upstream-maintained)
- Multi-PDK support (sky130hd only, deferred)

See FEATURES.md for detailed specifications and MVP prioritization.

---

### Architecture Approach

v1.1.5 introduces **three new components (MCP Server, config generator, ORFS runner)** while modifying four existing ones (pnr skill, initialize skill, detect-env.sh, env.json). All components upstream of PnR remain untouched.

**Core pattern: RPC-over-stdio.** The MCP Server is spawned as a child process by Claude Code, communicates via JSON-RPC 2.0 over stdin/stdout, and manages all Docker interactions. This replaces v1.1.2's direct bash script invocation.

**Why ORFS Makefile?** Task2 explicitly requires "ORFS 后端自动化流程框架, 通过 `make` 驱动完整后端流程." The ORFS Docker image has ORFS at `/OpenROAD-flow-scripts/flow/`. Plus, sky130hd's complex PDN config (VPWR/VGND global connections, met1/met4/met5 stripes, tapcell mapping) is embedded in ORFS platform scripts — duplicating it in standalone Tcl is fragile.

**MCP Server Structure:**
- `check_environment` tool — validates Docker, ORFS, sky130hd, tool versions
- `generate_config` tool — produces config.mk + constraint.sdc
- `run_stage` tool — executes ORFS make target via docker exec
- `get_report` tool — extracts metrics from ORFS outputs
- `get_log` tool — retrieves stage log for diagnosis

**Key sky130hd differences from nangate45:**
- 5 metal layers (met1-met5) vs 10 — routing constraint
- Cell names: `sky130_fd_sc_hd__*` format (long) vs `CELL_X1` (short)
- **Default CLOCK_PERIOD: 10.0ns (100MHz) not 2.0ns** — 130nm process, gates are 5-10x slower
- PLACE_DENSITY: 0.60 (higher, larger cells)
- PDN uses met1+met4/met5 (not met1/met4/met7)

See ARCHITECTURE.md for detailed component responsibilities, MCP tool specs, config generation logic, and build order.

---

### Critical Pitfalls

Research identified **19 pitfalls**. The top 5 critical:

1. **stdout Contamination (P1)** — Any `console.log()` corrupts the MCP stdio protocol. Tools disappear from Claude Code. **Prevention:** Use `console.error()` exclusively, add eslint rules.

2. **Layer/Cell Names Completely Different (P2+P3)** — metal2-metal10 → met1-met5, BUF_X1 → sky130_fd_sc_hd__buf_1. **Prevention:** Extract all naming from sky130hd platform config.mk, never hardcode.

3. **ORFS Output Paths Don't Match ChipAgent Convention (P4)** — ORFS writes to `results/sky130hd/<DESIGN>/base/`, ChipAgent expects `workspace/pnr/`. **Prevention:** Mount workspace to `/workspace`, implement path translation layer.

4. **MCP Tool Timeout (P6)** — ORFS route can take 10+ minutes. Claude Code's default timeout is 60s. **Prevention:** Set MCP_TIMEOUT=600000 in .mcp.json, design non-blocking pattern.

5. **Docker Container Lifecycle (P7)** — Orphaned containers, naming conflicts, state persistence. **Prevention:** Deterministic naming, ensureContainer() method, SIGTERM hook, health checks.

See PITFALLS.md for all 19 pitfalls with prevention strategies.

---

## Implications for Roadmap

### Phase 1: MCP Server Scaffold + Docker Detection
**Delivers:** MCP server, check_environment tool, .mcp.json, logging discipline, container lifecycle
**Addresses:** T8, T9
**Avoids:** P1, P6, P7, P12
**Research needed:** None

### Phase 2: sky130hd Config + Constraint Generation
**Delivers:** generate_config tool, sky130hd constants map, SDC generation with 10ns default
**Addresses:** T3, T4
**Avoids:** P2, P3, P5, P8, P9, P10, P14
**Research needed:** None (templates validated against ORFS gcd examples)

### Phase 3: ORFS Runner + Synthesis Stage
**Delivers:** run_stage tool, get_log tool, Docker volume mounts, path translation, timeout handling
**Addresses:** T1, T2, T10
**Avoids:** P4, P6, P13, P19
**Research needed:** None

### Phase 4: Metric Extraction + Full Flow
**Delivers:** Complete get_report tool, metrics parsing for all 6 stages, end-to-end test
**Addresses:** T2, T5, T6
**Avoids:** P4, P11, P16
**Research needed:** None (ORFS paths verified locally)

### Phase 5: Skill Rewrite + PPA Report
**Delivers:** /chip-agent:pnr Skill orchestrating all stages, PPA report formatting, initialize update
**Addresses:** T5, T6, T7, T10
**Avoids:** P16, IP1, IP2
**Research needed:** None

### Phase 6: Auto-Retry + Error Diagnosis (Stretch)
**Delivers:** Error classification, retry logic, QoR comparison, additional MCP tools
**Addresses:** D1-D7
**Avoids:** P8, P11, P14, P16
**Research needed:** None

### Phase Ordering Rationale

Dependency-ordered:
1. Phase 1 (MCP foundation) — all phases depend on this
2. Phase 2 (config generation) — needed before Phase 3 can run ORFS
3. Phase 3 (synth validation) — validate single stage before orchestrating six
4. Phase 4 (metrics) — needed for Phase 5 to format report
5. Phase 5 (Skill) — base flow for users
6. Phase 6 (retry) — optional stretch goal

### Research Flags

**Phases needing deeper research:** None identified. All critical questions addressed with HIGH-confidence sources.

**Phases with standard patterns (skip research-phase):**
- Phase 1: MCP SDK docs are excellent
- Phase 2: ORFS gcd example available
- Phase 3: Docker exec is straightforward
- Phase 4: Log parsing is standard
- Phase 5: Skill writing is established pattern
- Phase 6: Retry logic is straightforward

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | MCP SDK verified on npm, ORFS/sky130hd verified locally, Node.js type-stripping verified |
| Features | HIGH | MCP specs from official SDK, task2 requirements explicit, ORFS targets verified |
| Architecture | HIGH | ORFS platform files verified locally, Docker patterns standard, MCP stdio documented |
| Pitfalls | HIGH | Critical pitfalls documented in industry sources, moderate/minor pitfalls validated against ORFS/PDK docs |

**Overall: HIGH**

All research grounded in HIGH-confidence sources: official MCP SDK GitHub/npm, ORFS source code verified locally, sky130hd platform files verified locally, task2.md verified locally.

### Gaps to Address

1. **MCP Timeout Configuration** — Behavior inconsistent per GitHub #17662. **Handling:** Test in Phase 1 with long-running make.

2. **Docker Container Persistence** — GitHub #29058 documents containers surviving Claude Code crash. **Handling:** Test SIGTERM hook in Phase 1.

3. **Volume Mount Permissions** — File ownership mismatch possible. **Handling:** Test `docker run -u $(id -u):$(id -g)` in Phase 1.

4. **sky130hd Performance Baseline** — No benchmark data yet. **Handling:** Measure stage timings on medium module in Phase 3.

5. **Retry Loop Termination** — Could infinite-loop. **Handling:** Enforce max 3 attempts in Phase 6.

---

## Sources

### Primary (HIGH Confidence)

**MCP SDK:**
- @modelcontextprotocol/sdk npm page — v1.29.0 specs, peer dependencies
- MCP TypeScript SDK GitHub — server.md, import paths, stdio transport
- Claude Code MCP docs — .mcp.json format, plugin MCP server pattern

**ORFS (Verified Locally 2026-04-01):**
- ~/OpenROAD-flow-scripts/flow/Makefile — synth/floorplan/place/cts/route/finish targets
- ~/OpenROAD-flow-scripts/flow/platforms/sky130hd/ — config.mk, PDK constants, .tcl files
- ~/OpenROAD-flow-scripts/flow/designs/sky130hd/gcd/ — reference configs

**task2 Requirements:**
- /home/mingzhenjia/ChipAgent/task2.md — examined locally

### Secondary (MEDIUM Confidence)

**ORFS Documentation:**
- Flow Tutorial, Adding New Designs, Flow Variables, Docker Shell

**Pitfall Sources:**
- Nearform MCP Tips and Pitfalls
- GitHub issues #17662, #29058, and ORFS/OpenLane discussions

---

*Research completed: 2026-04-01*
*Ready for roadmap: yes*
