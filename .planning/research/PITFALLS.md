# Domain Pitfalls: v1.1.5 sky130hd MCP Backend

**Domain:** ChipAgent v1.1.5 -- MCP Server + ORFS make flow on sky130hd, replacing standalone nangate45 Tcl scripts
**Researched:** 2026-04-01
**Confidence:** HIGH (sky130hd platform files verified locally, ORFS Makefile/variables.mk analyzed, MCP SDK docs + issue trackers consulted, task2 requirements cross-referenced)
**Supersedes:** v1.1.2 PITFALLS.md (nangate45-specific). This document covers ONLY pitfalls related to the v1.1.5 additions. Many v1.1.2 pitfalls (Chisel io_ prefix, combinational clock detection, Verilog compatibility) remain valid and are not repeated here.

---

## Critical Pitfalls

Mistakes that cause flow aborts, silent wrong results, or require architectural rework.

### Pitfall 1: stdout Contamination Kills MCP Server Over stdio Transport

**What goes wrong:** Any `console.log()` call in the MCP server TypeScript code corrupts the JSON-RPC protocol over the stdio transport. The MCP client (Claude Code) receives malformed JSON mixed with debug output, causing silent connection drops or cryptic parse errors. The server appears to "connect" but tools never appear or silently fail.

**Why it happens:** The stdio MCP transport uses stdout exclusively for JSON-RPC messages and stdin for requests. This is the single most commonly reported mistake in MCP server development. Developers habitually use `console.log` for debugging, and even transitive dependencies (e.g., a logging library defaulting to stdout) can trigger this.

**Consequences:** Tools do not appear in Claude Code's tool list. Tool calls return no result. The server appears connected but non-functional. Debugging is difficult because the corruption is intermittent (only when log output coincides with a protocol message).

**Prevention:**
- Use `console.error()` exclusively for all diagnostic output in the MCP server
- Configure any logging library (e.g., winston, pino) to write to stderr, not stdout
- Add an eslint rule: `no-restricted-globals` or `no-console` with `allow: ["error", "warn"]` to catch `console.log` at lint time
- In the MCP server entry point, add a safety guard early: `process.stdout.write = () => { throw new Error("stdout reserved for MCP protocol"); }` during development to catch violations
- Test the server manually before Claude Code integration: `echo '{"jsonrpc":"2.0","method":"initialize","params":{"capabilities":{}},"id":1}' | node dist/index.js 2>/dev/null` -- stdout should contain only valid JSON-RPC

**Detection:** Claude Code shows "MCP server connected" but `tools/list` returns empty. Or tools appear but calls return "No result received." Debug log at `~/.claude/debug/latest` shows JSON parse errors.

**Phase:** Phase 1 (MCP Server scaffold). Must be enforced from the first line of code.

---

### Pitfall 2: sky130hd Layer Names Are Different From nangate45 -- Every Tcl Command Must Change

**What goes wrong:** The existing nangate45 PnR scripts use `metal1`..`metal10` layer names. sky130hd uses `li1`, `met1`..`met5`. Copying nangate45 Tcl patterns and only changing cell names will produce errors like `[ERROR ORD-0043] Layer metal2 not found` because sky130hd has no layer named `metal2` -- it uses `met2`.

**Why it happens:** nangate45 is a 45nm academic PDK with 10 metal layers named `metal1` through `metal10`. sky130hd is a real 130nm process with 5 metal layers (`met1`-`met5`) plus a local interconnect layer (`li1`). The naming conventions are completely different. Additionally, the maximum routing layer drops from `metal10` to `met5`, and the minimum clock routing layer changes from `metal4` to `met3`.

**Key naming differences (every one must be updated):**

| Parameter | nangate45 (old) | sky130hd (new) |
|-----------|-----------------|----------------|
| Layer name format | `metal1`..`metal10` | `li1`, `met1`..`met5` |
| IO placer horizontal | `metal5` | `met3` |
| IO placer vertical | `metal6` | `met2` |
| Min routing layer | `metal2` | `met1` |
| Max routing layer | `metal10` | `met5` |
| Min clock routing layer | `metal4` | `met3` |
| PDN stripe layers | `met1`, `metal4`, `metal7` | `met1`, `met4`, `met5` |
| Place site | `FreePDK45_38x28_10R_NP_162NW_34O` | `unithd` |

**Consequences:** OpenROAD aborts with layer-not-found errors. If a layer name is used in a non-critical context (e.g., congestion report), the flow may silently skip that step, producing incomplete reports.

**Prevention:**
- Do NOT adapt the nangate45 Tcl scripts by find-and-replace. Instead, generate config.mk for ORFS from sky130hd platform constants
- Extract all layer names, site names, and cell names from the sky130hd `config.mk` (verified at `/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/sky130hd/config.mk`)
- The MCP server should read sky130hd `config.mk` values and use them to populate config.mk for each design
- Create a PDK constants map that the MCP server loads at startup, not hardcoded strings scattered across tool implementations

**Detection:** OpenROAD errors containing "Layer X not found" or "Site X not found." Yosys errors about unknown cell names.

**Phase:** Phase 2 (sky130hd config generation). This is the most pervasive change -- every PnR parameter differs.

---

### Pitfall 3: sky130hd Cell Naming Convention Breaks Naive Pattern Matching

**What goes wrong:** nangate45 cells use short names like `NAND2_X1`, `BUF_X1`, `FILLCELL_X1`. sky130hd uses long hierarchical names like `sky130_fd_sc_hd__nand2_1`, `sky130_fd_sc_hd__buf_1`, `sky130_fd_sc_hd__fill_1`. Any script that matches cell names by pattern (grep for `FILLCELL_`, check for `BUF_X`, etc.) will break.

**Key cell name mappings:**

| Purpose | nangate45 | sky130hd |
|---------|-----------|----------|
| Tie-high | `LOGIC1_X1 Z` | `sky130_fd_sc_hd__conb_1 HI` |
| Tie-low | `LOGIC0_X1 Z` | `sky130_fd_sc_hd__conb_1 LO` |
| Buffer (ABC driver) | `BUF_X1` | `sky130_fd_sc_hd__buf_1` |
| Buffer (min) | `BUF_X1 A Z` | `sky130_fd_sc_hd__buf_4 A X` |
| Fill cells | `FILLCELL_X1 X2 X4 X8 X16 X32` | `sky130_fd_sc_hd__fill_1 fill_2 fill_4 fill_8` |
| Tap cell | `TAPCELL_X1` | `sky130_fd_sc_hd__tapvpwrvgnd_1` |
| Dont-use cells | `TAPCELL_X1 FILLCELL_X1 AOI211_X1 OAI211_X1` | ~30 probe + lpflow cells (see config.mk) |

**Additional differences:**
- sky130hd tie-high and tie-low come from the SAME cell (`sky130_fd_sc_hd__conb_1`) with different output pins (`HI` vs `LO`), whereas nangate45 uses separate cells
- sky130hd buffer pin names are `A`/`X`, nangate45 uses `A`/`Z`
- ABC load parameter changes from `3.898` (nangate45) to `5` (sky130hd)
- sky130hd has latch, clock-gate, and adder mapping files that nangate45 does not have

**Consequences:** Yosys synthesis fails on `hilomap` with wrong cell names. Filler insertion fails. Tap cell insertion fails. Post-synthesis report parsing breaks if looking for specific cell name patterns.

**Prevention:**
- The MCP server config.mk generator must use ALL cell names from sky130hd's platform `config.mk`
- Never hardcode cell names in the MCP server logic -- read them from config.mk or pass as ORFS Makefile variables
- The DONT_USE_CELLS list for sky130hd is ~30 entries (probe and lpflow cells) -- do not truncate it
- sky130hd has additional Yosys mapping files (`cells_latch_hd.v`, `cells_clkgate_hd.v`, `cells_adders_hd.v`) that must be passed via `LATCH_MAP_FILE`, `CLKGATE_MAP_FILE`, `ADDER_MAP_FILE` variables

**Detection:** Yosys errors about "cell not found." OpenROAD errors about "unknown master cell." Filler placement warnings.

**Phase:** Phase 2 (config.mk/SDC generation). Must be comprehensive from the start.

---

### Pitfall 4: ORFS Make Flow Output Paths Are Rigid and Different From ChipAgent's Convention

**What goes wrong:** ORFS `make` writes results to `results/sky130hd/<DESIGN_NAME>/base/`, logs to `logs/sky130hd/<DESIGN_NAME>/base/`, and reports to `reports/sky130hd/<DESIGN_NAME>/base/`. ChipAgent's existing convention is `MyDesign/<Module>/workspace/pnr/`. If the MCP server runs `make` inside Docker, the output lands in the container's ORFS directories, not in ChipAgent's workspace.

**Why it happens:** ORFS `variables.mk` defines: `RESULTS_DIR = $(WORK_HOME)/results/$(PLATFORM)/$(DESIGN_NICKNAME)/$(FLOW_VARIANT)`. These variables are baked into the Makefile and cannot be easily overridden without modifying the flow. The Docker container's filesystem is separate from the host, and the `WORK_HOME` default is `.` (the ORFS flow directory inside the container).

**Consequences:** MCP tool returns report content but ChipAgent's workspace has no PnR artifacts. The SKILL.md skill cannot find reports at `workspace/pnr/reports/` because they only exist inside the container at ORFS paths. If the container is removed, all results are lost.

**Prevention:**
- Mount the design workspace into the container: `-v $(pwd)/MyDesign/<Module>/workspace:/workspace`
- Set `WORK_HOME=/workspace/pnr` when invoking `make`, so ORFS writes results under the mounted volume at `/workspace/pnr/results/sky130hd/<DESIGN>/base/`
- After `make` completes, the MCP server's `get_report` tool should read from the ORFS output paths inside the container, NOT from ChipAgent's expected paths
- Create a path-mapping layer in the MCP server that translates between ORFS paths (inside container) and ChipAgent workspace paths (on host)
- Alternatively: after each make stage, copy/symlink results from ORFS directories to ChipAgent workspace paths. This is simpler than fighting ORFS's directory convention
- The `metadata.json` file ORFS generates at flow end contains all metric data -- use this for metric extraction rather than parsing individual report files

**Detection:** MCP `get_report` tool returns "file not found" for reports. Workspace `pnr/` directory is empty after flow completion. Reports exist only inside the container.

**Phase:** Phase 1 (MCP Server architecture) and Phase 3 (SKILL rewrite). Must design the path mapping before implementing any tools.

---

### Pitfall 5: sky130hd PDN Configuration Uses VPWR/VGND, Not VDD/VSS Directly

**What goes wrong:** The sky130hd `pdn.tcl` maps power nets through multiple pin patterns: `VDD` net connects to pins matching `^VDD$`, `^VDDPE$`, `^VDDCE$`, `VPWR`, and `VPB`. The `VSS` net connects to `^VSS$`, `^VSSE$`, `VGND`, and `VNB`. If a custom PDN configuration omits any of these patterns, cells will have unconnected power pins, causing DRC violations and potentially silent functional failures.

**Why it happens:** sky130hd standard cells use `VPWR`/`VGND` as power pin names internally, but the top-level nets are named `VDD`/`VSS`. The `add_global_connection` commands in `pdn.tcl` bridge this naming gap. nangate45 does not have this complexity -- its cells use `VDD`/`VSS` directly.

**Additionally:** sky130hd defines the PDN grid on `met1` (followpins, width 0.48, pitch 5.44), `met4` (stripes, width 1.6, pitch 27.14), and `met5` (stripes, width 1.6, pitch 27.2). This is different from nangate45's M1-M4-M7 strategy. The power pins `met5` is used, meaning met5 is partially consumed by PDN and less available for signal routing.

**Consequences:** PDN generation may succeed but leave cells unconnected (PSM-0094 warnings). DRC violations appear at routing. Power analysis reports show zero power for disconnected cells. In severe cases, the routed design has dead logic.

**Prevention:**
- Use the sky130hd platform `pdn.tcl` exactly as-is via ORFS make flow -- do NOT write a custom PDN script
- If standalone scripts are ever needed, copy `pdn.tcl` verbatim from the platform directory
- Never omit `global_connect` at the end of the global connection definitions
- The ORFS make flow handles this correctly when `PDN_TCL` points to the platform file
- For small designs, be aware that met4/met5 stripe pitch (~27um) means minimum die area is larger than nangate45's requirements

**Detection:** `[WARNING PSM-0094]` messages about instances not connected to power nets. DRC violations with "open" or "disconnected" errors. Power report shows 0.0 for some cells.

**Phase:** Phase 2 (config.mk generation). The PDN_TCL path must point to the correct platform file.

---

### Pitfall 6: MCP Tool Execution Timeout for Long-Running PnR Stages

**What goes wrong:** Claude Code's MCP tool execution has a default timeout of 60 seconds (from `DEFAULT_REQUEST_TIMEOUT_MSEC = 60000` in the MCP TypeScript SDK). PnR stages can take 2-10 minutes for medium designs on sky130hd (which is slower than nangate45 due to larger feature sizes producing more cells at equivalent logic complexity). The tool call times out, Claude reports "No result received from tool execution", and the flow appears to fail even though the Docker process continues running.

**Why it happens:** The MCP protocol was designed for quick tool calls (file reads, API calls). EDA tool execution can be very slow. Claude Code's `MCP_TOOL_TIMEOUT` environment variable is documented but has known bugs where it is not respected for long-running calls (GitHub issue #17662). Docker exec adds latency on top of the actual tool runtime.

**Consequences:** Claude receives no result and may retry the tool call, triggering duplicate PnR runs. Or Claude reports failure to the user when the flow is actually still running in the container. The container accumulates zombie processes if Docker exec calls are not properly managed.

**Prevention:**
- Design MCP tools to be non-blocking: `run_stage` starts the stage and returns immediately with a job ID; `get_stage_status` polls for completion; `get_report` reads results after completion
- Set `MCP_TIMEOUT` environment variable in `.mcp.json` to at least 600000 (10 minutes): `"env": { "MCP_TIMEOUT": "600000" }`
- Implement internal progress reporting: the MCP tool should stream status updates via the `notifications/progress` MCP protocol feature
- For the `make` flow specifically: run `make` in the background inside the container (`nohup make ... &`) and poll a sentinel file or log for completion markers
- Add explicit timeout handling in each tool with `Promise.race([toolExecution, timeoutPromise])` and return a structured "still running" response rather than letting the framework timeout
- Consider splitting the full PnR flow into individual `make` target calls (synth, floorplan, place, cts, route, finish) so each tool call completes within the timeout window

**Detection:** Claude Code shows "Tool ran without output or errors" or "No result received." The container's ORFS log files continue growing after the timeout. Multiple identical make processes running in the container.

**Phase:** Phase 1 (MCP Server architecture). The async execution pattern must be designed before implementing any stage tools.

---

### Pitfall 7: Docker Container Lifecycle Mismanagement

**What goes wrong:** The task2 spec calls for a long-running container (`docker run -d ... sleep infinity`) with `docker exec` for operations. If the MCP server spawns a new container per tool call, each call has ~5-10s overhead for container startup. If it reuses a container but does not handle cleanup, containers accumulate. If Claude Code crashes or the session ends, Docker containers keep running indefinitely (confirmed bug: GitHub issue #29058).

**Why it happens:** Docker containers spawned via `docker run` in `.mcp.json` config are managed by the Docker daemon, not by Claude Code. Killing the Claude Code process does not stop the container. The MCP server itself runs as a subprocess of Claude Code, but the Docker container it manages is a separate daemon process.

**Consequences:** Orphaned containers consume resources. Multiple parallel sessions may conflict on container names. Stale containers may hold locks on mounted volumes, preventing new runs. Container naming conflicts: `docker run --name orfs-agent ...` fails if a container with that name already exists from a previous session.

**Prevention:**
- Use a deterministic container name derived from the project path (e.g., `orfs-agent-<hash>`)
- Implement container lifecycle management in the MCP server: `ensureContainer()` checks if the named container exists and is running, creates it if not, restarts it if stopped
- Add a shutdown hook in the MCP server: `process.on('SIGTERM', () => { exec('docker stop orfs-agent'); })`
- Use `docker exec` on the long-running container for all operations -- never `docker run` for individual commands
- Add a `--rm` flag awareness: the long-running container should NOT use `--rm` (it needs to survive between tool calls), but any temporary containers should
- Implement a `cleanup` MCP tool that stops and removes the container on demand
- Set container health checks: `HEALTHCHECK CMD ls /OpenROAD-flow-scripts/flow/Makefile` to detect container corruption

**Detection:** `docker ps` shows multiple `orfs-agent` containers. `docker exec` fails with "No such container" or "Container is not running." New container creation fails with "name already in use."

**Phase:** Phase 1 (MCP Server architecture). Container lifecycle is a Day 1 design decision.

---

## Moderate Pitfalls

### Pitfall 8: sky130hd Timing Is Much Slower Than nangate45 -- Default Clock Period Must Change

**What goes wrong:** The v1.1.2 default clock period of 2.0ns (500MHz) is reasonable for nangate45 (45nm process). For sky130hd (130nm), this is extremely aggressive and will cause massive timing violations. The sky130hd GCD example uses 1.1ns, but even that has tight setup margins. For a Chisel-generated ALU at 130nm, 2.0ns will fail timing badly.

**Why it happens:** sky130hd standard cells are ~3-10x slower than nangate45 cells due to the larger feature size (130nm vs 45nm). A nangate45 `BUF_X1` has propagation delay ~20ps; a sky130hd `sky130_fd_sc_hd__buf_1` has delay ~150-300ps. The timing library values are fundamentally different.

**Consequences:** Massive WNS violations (potentially -5ns to -10ns). `repair_timing` inserts hundreds of buffers trying to fix unfixable paths. The design bloats in area. The auto-retry mechanism (50% clock period increase per retry) may need many iterations before reaching a feasible period.

**Prevention:**
- Change default clock period from 2.0ns to 10.0ns for sky130hd (100MHz). This is conservative enough for educational modules while still driving meaningful optimization
- The GCD example at 1.1ns is aggressive and assumes a well-optimized design; Chisel auto-generated modules are not optimized
- Allow override via spec.json `clock_period_ns` as before
- If auto-retry is retained, start with a larger initial period and use 100% increase per retry (not 50%) since the gap to closure is much larger
- Consider generating a `CLOCK_PERIOD` variable in config.mk and letting ORFS propagate it to SDC

**Detection:** WNS worse than -2ns on the first attempt. TNS with hundreds of nanoseconds of total violations. repair_timing cell count increase exceeding 3x the original.

**Phase:** Phase 2 (SDC/config.mk generation). Must update the default before any sky130hd run.

---

### Pitfall 9: ORFS Make Variables Priority Confusion (`?=` vs `=` vs command-line)

**What goes wrong:** ORFS uses a complex variable priority system: command-line > `config.mk` with `=` > environment > `config.mk` with `?=` > platform defaults > `defaults.py`. Setting `PLACE_DENSITY=0.60` in the design config.mk with `=` makes it immune to command-line override. Setting it with `?=` allows override. Misunderstanding this causes settings to silently not take effect.

**Why it happens:** ORFS's `variables.mk` includes the platform config.mk first, then runs `defaults.py` to fill unset variables, then the Makefile uses the result. The design config.mk is included by the top-level Makefile before `variables.mk` processes defaults. The actual value depends on which file defines it and whether `?=` or `=` was used.

**Consequences:** User sets `PLACE_DENSITY` in their config.mk but the platform default overrides it (or vice versa). Clock period in SDC does not match what the user intended. Synthesis optimization targets are wrong.

**Prevention:**
- The MCP server should generate design-specific config.mk using `export VAR = value` (not `?=`) for all design parameters to ensure they take priority
- Only use `?=` for parameters where the platform default is acceptable
- For required parameters (DESIGN_NAME, PLATFORM, VERILOG_FILES, SDC_FILE), always use `=`
- After generating config.mk, validate by running `make -n DESIGN_CONFIG=... vars` (ORFS has a debug target) to confirm resolved values
- Keep config.mk minimal: only override what differs from the platform default

**Detection:** Unexpected parameter values in synthesis or PnR logs. Flow uses wrong clock period. Placement density does not match config.mk setting.

**Phase:** Phase 2 (config.mk generation). Must understand the priority rules before writing the generator.

---

### Pitfall 10: sky130hd `rcx_patterns.rules` Is a Symlink to `sky130hs`

**What goes wrong:** The sky130hd `rcx_patterns.rules` file is a symlink: `sky130hd/rcx_patterns.rules -> ../sky130hs/rcx_patterns.rules`. If the Docker volume mount does not preserve symlinks or only mounts the sky130hd directory, parasitic extraction fails because the symlink target is outside the mount.

**Why it happens:** The sky130hd and sky130hs PDKs share RC extraction rules. ORFS uses a symlink to avoid duplication. Inside the Docker image, this works because the entire `platforms/` directory is present. But if ChipAgent copies or mounts individual PDK directories, the symlink breaks.

**Consequences:** `extract_parasitics -ext_model_file` fails with "file not found." Timing reports use estimated (not extracted) parasitics, which can be 2-3x inaccurate. If the error is caught, the flow aborts at extraction.

**Prevention:**
- Inside Docker (the primary mode): no action needed -- the full ORFS image has both directories and the symlink works
- If ever running locally: mount or reference the parent `platforms/` directory, not just `sky130hd/`
- The MCP server should verify the symlink resolves correctly: `docker exec orfs-agent test -f /OpenROAD-flow-scripts/flow/platforms/sky130hd/rcx_patterns.rules`
- Add a pre-flight check tool in the MCP server that validates all required PDK files exist

**Detection:** OpenROAD error: "Cannot open extraction model file." Or warnings about using estimated parasitics when extracted should be available.

**Phase:** Phase 2 (environment validation). Include in the pre-flight check tool.

---

### Pitfall 11: sky130hd Has Only 5 Metal Layers -- Routing Congestion Is Much Worse

**What goes wrong:** nangate45 has 10 metal layers for routing. sky130hd has only 5 metal layers (plus li1 which is impractical for routing due to high resistance). With met5 partially consumed by PDN stripes, effectively only met1-met4 are available for signal routing. Designs that routed easily on nangate45 may have severe routing congestion on sky130hd, causing DRC violations and routing failures.

**Why it happens:** 130nm is an older process with fewer metal layers. The sky130hd PDN uses met4 and met5 for power stripes, further reducing routing resources. The local interconnect layer (li1) has high resistance (~72 mohm/um vs ~0.89 mohm/um for met1) and is unsuitable for anything beyond very short connections.

**Consequences:** Global routing overflow errors. Detailed routing DRC violations. Antenna violations (only one antenna diode size available in sky130hd). Routing may succeed but with many detours, increasing wire delay and worsening timing.

**Prevention:**
- Reduce CORE_UTILIZATION for sky130hd designs: use 30-40% instead of nangate45's 55%
- The sky130hd GCD example uses `CORE_UTILIZATION = 40` -- follow this as baseline
- For small Chisel modules, use explicit minimum die area that provides ample routing space (at least 100x100um for designs under 200 cells)
- The PLACE_DENSITY default for sky130hd is already 0.60 (higher than nangate45's 0.30) -- this is correct for the denser sky130hd cell library, do NOT change it unless routing fails
- Monitor congestion reports from global routing; if overflow > 0, reduce utilization

**Detection:** Global routing log shows "overflow" messages. DRC violations after detailed routing. Routing completes but met5 is heavily congested.

**Phase:** Phase 2 (config.mk generation) and Phase 3 (SKILL auto-retry logic).

---

### Pitfall 12: MCP Server Must Be Built Before Claude Code Can Connect

**What goes wrong:** Claude Code expects to spawn the MCP server as a subprocess using the command specified in `.mcp.json`. If the command points to `node dist/index.js` but the TypeScript has not been compiled (no `dist/` directory), the server fails to start. Claude Code shows "MCP server connection failed" with a 30-second timeout.

**Why it happens:** TypeScript MCP servers require a build step (`tsc` or equivalent) to produce JavaScript. Developers write the TypeScript, update `.mcp.json` to point to the output, but forget to run `npm run build`. During development, this happens repeatedly after every code change.

**Consequences:** Claude Code cannot discover any MCP tools. The 30-second connection timeout blocks the entire session. Error messages are generic and do not indicate that the issue is a missing build artifact.

**Prevention:**
- Use `tsx` as the runtime during development: point `.mcp.json` to `npx tsx src/index.ts` instead of `node dist/index.js`
- For production/submission, use `node dist/index.js` with a pre-built `dist/` directory
- Add a `prepare` script in `package.json` that runs the build: `"prepare": "tsc"`
- Add a health check in the SKILL that verifies the MCP server is reachable before attempting tool calls
- Include build step in the install instructions and CLAUDE.md
- Consider using `"command": "npx"` with `"args": ["tsx", "<path>/src/index.ts"]` in `.mcp.json` to avoid the build step entirely

**Detection:** `~/.claude/debug/latest` shows "Connection to MCP server timed out after 30000ms." The `dist/` directory does not exist or is stale.

**Phase:** Phase 1 (MCP Server scaffold). Development workflow must be established early.

---

### Pitfall 13: Design-Specific config.mk Path Resolution Inside Docker

**What goes wrong:** ORFS `make DESIGN_CONFIG=...` expects the config.mk path to be valid inside the container. The MCP server generates config.mk on the host (in ChipAgent workspace) and passes the path via `docker exec make DESIGN_CONFIG=/workspace/config.mk`. But if the volume mount maps to a different container path, or if config.mk references `VERILOG_FILES` with host-side absolute paths, `make` fails with "file not found."

**Why it happens:** Path translation between host and container is a perennial Docker pitfall. The host path `/home/user/ChipAgent/MyDesign/ALU/workspace/generated/ALU.v` must become `/workspace/generated/ALU.v` (or wherever the volume is mounted) inside the container. config.mk must use container-internal paths for `VERILOG_FILES` and `SDC_FILE`.

**Consequences:** Yosys cannot read the Verilog source. SDC file not found. Make reports cryptic errors about missing prerequisites. The design directory is the wrong location.

**Prevention:**
- Define a clear mount convention: always mount `MyDesign/<Module>/workspace` to `/workspace` inside the container
- Generate config.mk using container-internal paths (e.g., `VERILOG_FILES = /workspace/generated/ALU.v`), never host paths
- The MCP server must maintain a path translation map: `hostPath <-> containerPath`
- Use environment variable `DESIGN_HOME` in config.mk with a container-relative path
- Validate the mount before running: `docker exec orfs-agent test -f /workspace/generated/<Module>.v`
- Consider mounting the ORFS flow directory read-only to prevent accidental modification: `-v /path/to/orfs/flow:/OpenROAD-flow-scripts/flow:ro` -- but only the platform files; the flow working directory needs to be writable

**Detection:** Make errors about "No rule to make target" for Verilog files. Yosys errors about "cannot open file." Paths in error messages contain host-side absolute paths instead of container paths.

**Phase:** Phase 1 (MCP Server architecture) and Phase 2 (config.mk generator). The mount convention must be established before any tool implementation.

---

### Pitfall 14: sky130hd PDN Minimum Die Area Is Larger Than nangate45

**What goes wrong:** The existing v1.1.2 minimum die area for small modules is 70x70um (based on nangate45's metal4 stripe pitch of 56um). sky130hd's met4 stripe pitch is 27.14um and met5 pitch is 27.2um, but the stripes are wider (1.6um vs nangate45's finer stripes) and the cell height is different. A 70x70um die may work geometrically but the reduced metal layers mean more routing pressure. More importantly, the sky130hd cell site `unithd` has different dimensions than nangate45's site, so the explicit die area must be a multiple of the site pitch.

**Why it happens:** Each PDK has different cell heights, site widths, and PDN pitch requirements. The minimum die area is not just about fitting one PDN pitch -- it must also be a valid multiple of the placement site dimensions and have enough routing resources for the design.

**Consequences:** `initialize_floorplan` fails or produces a degenerate layout. PDN generation errors (PDN-0185 "Insufficient width to add straps"). Placement fails due to insufficient legal sites.

**Prevention:**
- For ORFS make flow: set `CORE_UTILIZATION = 30` for modules under 100 cells, which lets ORFS auto-size the die
- Let ORFS handle the floorplan sizing through its default logic rather than specifying explicit die areas
- If explicit die area is needed, ensure dimensions are multiples of the `unithd` site pitch (0.46um x 2.72um from the LEF)
- Monitor for PDN-0185 errors and increase die size if they occur
- The GCD example does not set explicit die area -- it uses `CORE_UTILIZATION = 40` and lets ORFS calculate

**Detection:** PDN errors PDN-0185, PDN-0085. Placement errors about insufficient sites. Floorplan warnings about aspect ratio.

**Phase:** Phase 2 (config.mk generation). Let ORFS auto-size rather than computing explicit areas.

---

## Minor Pitfalls

### Pitfall 15: `.mcp.json` Must Use Absolute Paths, Not `~` or Relative Paths

**What goes wrong:** Claude Code's `.mcp.json` parser does not expand `~` (home directory) or resolve relative paths for the server command. Writing `"command": "node"` with `"args": ["~/ChipAgent/mcp-server/dist/index.js"]` fails because the shell expansion does not occur. Similarly, `"./mcp-server/dist/index.js"` resolves relative to an undefined working directory.

**Prevention:**
- Always use absolute paths in `.mcp.json`: `/home/mingzhenjia/ChipAgent/mcp-server/dist/index.js`
- Or use `npx` which handles path resolution: `"command": "npx", "args": ["tsx", "/absolute/path/to/src/index.ts"]`
- Test the exact command from the terminal first: `node /absolute/path/to/dist/index.js` should start the server on stdio

**Detection:** "MCP server connection failed" errors in Claude Code. `~/.claude/debug/latest` shows "ENOENT: no such file or directory."

**Phase:** Phase 1 (MCP Server configuration). Quick to fix but frustrating to debug.

---

### Pitfall 16: ORFS `make clean` Is Required Between Config Changes

**What goes wrong:** ORFS caches intermediate results (`.odb` files, netlists, etc.) keyed by stage number. Changing `CLOCK_PERIOD` or `PLACE_DENSITY` in config.mk without cleaning causes the flow to skip stages that use the old parameter values, because the Makefile considers the cached output up-to-date.

**Prevention:**
- The MCP server's `run_stage` tool should always run `make clean_<stage> DESIGN_CONFIG=...` before `make <stage> DESIGN_CONFIG=...` when parameters change
- For the auto-retry mechanism (timing violation recovery), always clean before re-running: `make clean_synth clean_floorplan clean_place clean_cts clean_route clean_finish`
- Or use `make clean_all DESIGN_CONFIG=...` before a full re-run
- Track whether config.mk has changed since the last run and auto-clean if so

**Detection:** Flow completes instantly (cached) but reports show old values. Clock period in timing report does not match config.mk.

**Phase:** Phase 3 (SKILL auto-retry logic). Must clean between retry iterations.

---

### Pitfall 17: MCP Server TypeScript Module Configuration

**What goes wrong:** The MCP TypeScript SDK requires specific `tsconfig.json` settings. Using CommonJS modules with `require()` instead of ES modules with `import` causes runtime errors. Missing `"type": "module"` in `package.json` causes Node.js to interpret `.js` files as CommonJS even when compiled from ES module TypeScript.

**Prevention:**
- `tsconfig.json`: target `ES2022`, module `NodeNext`, moduleResolution `NodeNext`, `strict: true`, `esModuleInterop: true`
- `package.json`: `"type": "module"`
- Use `import` syntax exclusively, not `require()`
- The `@modelcontextprotocol/sdk` package is ESM-only as of recent versions

**Detection:** Runtime error: "require is not defined in ES module scope" or "Cannot use import statement outside a module."

**Phase:** Phase 1 (MCP Server scaffold). Get the module configuration right from the start.

---

### Pitfall 18: sky130hd `MATCH_CELL_FOOTPRINT = 1` Restricts Cell Swapping

**What goes wrong:** sky130hd's config.mk sets `MATCH_CELL_FOOTPRINT = 1`, which restricts `repair_timing` and `repair_design` to only swap cells with matching physical footprints. This is more restrictive than nangate45 and may prevent timing closure in cases where a larger-footprint buffer would fix the path.

**Prevention:**
- Accept this as a constraint of the sky130hd PDK -- do not override it
- If timing closure fails, relax the clock period rather than disabling footprint matching
- This constraint exists because sky130hd cells of different drive strengths may have different heights, and mixing them causes placement legalization failures

**Detection:** `repair_timing` warns about "no matching footprint" for replacement cells. Timing violations persist despite repair attempts.

**Phase:** Phase 3 (SKILL auto-retry). Awareness only -- no override recommended.

---

### Pitfall 19: Docker Volume Permissions Mismatch

**What goes wrong:** Files created inside the Docker container are owned by root (or the container's user). When ChipAgent tries to read these files on the host, it may lack permissions. Conversely, files written by the host user may not be writable inside the container.

**Prevention:**
- Run the container with the host user's UID/GID: `docker run -u $(id -u):$(id -g) ...`
- Or add `--user` to `docker exec` calls
- The ORFS `docker_shell` script uses this pattern: `-u $(id -u ${USER}):$(id -g ${USER})`
- Alternatively, use `chmod -R 777` on the workspace mount (acceptable for educational use, not production)

**Detection:** "Permission denied" when reading reports from workspace. "Permission denied" when writing config.mk into the container mount.

**Phase:** Phase 1 (Docker container setup). Must be set correctly in the container launch command.

---

## Integration Pitfalls (Unique to Adding These Features to the Existing System)

### Integration Pitfall 1: Existing nangate45 Scripts Conflict With New sky130hd Flow

**What goes wrong:** The existing `scripts/synth.sh`, `scripts/pnr.sh`, `scripts/synth.tcl`, and `scripts/pnr.tcl` are nangate45-specific (hardcoded cell names, layer names, PDK paths). If these are not removed or gated, a user running the old `/chip-agent:pnr` might accidentally use the nangate45 scripts instead of the new MCP-based flow, producing results with the wrong PDK.

**Prevention:**
- The v1.1.5 milestone replaces the PnR flow entirely -- remove or rename the old scripts to `scripts/pnr-nangate45.sh.bak` so they cannot be accidentally invoked
- Update `skills/pnr/SKILL.md` to use MCP tools exclusively
- Update CLAUDE.md to reflect that PnR now requires the MCP server and Docker
- Add a check in the new SKILL: if MCP server is not available, provide a clear error instead of falling back to old scripts

**Phase:** Phase 3 (SKILL rewrite). Must be a clean replacement, not a parallel system.

---

### Integration Pitfall 2: `/chip-agent:initialize` Must Detect Docker AND MCP Server

**What goes wrong:** The existing `initialize` skill detects local tools (yosys, openroad, verilator, etc.). For v1.1.5, it must also detect: Docker availability, `openroad/orfs` image pulled, MCP server built and configured in `.mcp.json`. If initialize reports "can_pnr: true" based on local OpenROAD detection but the MCP server is not configured, the PnR skill will fail.

**Prevention:**
- Extend `.chipagent/env.json` with new fields: `docker.available`, `docker.orfs_image`, `mcp.chip_pnr_server`
- The `can_pnr` capability flag should require: Docker available AND orfs image pulled AND MCP server configured
- Pre-reserved in v1.1.2: the initialize skill already has Docker detection as a planned extension point
- Add a `validate-mcp.sh` or equivalent check that verifies the MCP server starts and responds to `tools/list`

**Phase:** Phase 4 (initialize update). Must happen after MCP server is built.

---

### Integration Pitfall 3: MCP Server Is a Separate npm Package -- Build/Install Must Be Orchestrated

**What goes wrong:** The task2 submission structure requires `mcp-server/` as a separate directory with its own `package.json`, `src/`, and `README.md`. This is a separate Node.js package from the main ChipAgent plugin. If the MCP server's dependencies are not installed (`npm install` in `mcp-server/`) or it is not built (`npm run build`), the `.mcp.json` command fails.

**Prevention:**
- Add a `postinstall` script in the root `package.json` that runs `cd mcp-server && npm install && npm run build`
- Or use npm workspaces to manage both packages
- Document the two-step install in CLAUDE.md: `npm install` (root) then `cd mcp-server && npm install && npm run build`
- The MCP server should have a self-test: `npm test` in `mcp-server/` should verify the server starts and tools are registered

**Phase:** Phase 1 (MCP Server scaffold). The package structure must be designed to minimize install friction.

---

## Phase-Specific Warning Summary

| Phase | Topic | Pitfalls | Aggregate Severity |
|-------|-------|----------|-------------------|
| Phase 1 | MCP Server Scaffold + Docker | P1 (stdout), P4 (path mapping), P6 (timeout), P7 (container lifecycle), P12 (build), P13 (Docker paths), P15 (.mcp.json paths), P17 (TS modules), P19 (permissions), IP3 (package install) | CRITICAL -- architectural decisions here affect everything |
| Phase 2 | sky130hd Config + SDC | P2 (layer names), P3 (cell names), P5 (PDN/VPWR), P8 (clock period), P9 (make variables), P10 (rcx symlink), P11 (routing congestion), P14 (min die area), P18 (footprint match) | CRITICAL -- every nangate45 parameter changes |
| Phase 3 | SKILL Rewrite + Auto-retry | P4 (path mapping), P6 (timeout), P16 (make clean), IP1 (old scripts), IP2 (initialize) | HIGH -- flow orchestration must handle Docker/MCP correctly |
| Phase 4 | Initialize + Polish | IP2 (Docker+MCP detection), IP3 (install) | MODERATE -- extending existing patterns |

---

## Comparison: What Changes From v1.1.2 to v1.1.5

| Aspect | v1.1.2 (nangate45, standalone) | v1.1.5 (sky130hd, MCP+ORFS) | Migration Risk |
|--------|-------------------------------|------------------------------|----------------|
| Tool invocation | Shell scripts call yosys/openroad directly | MCP tools call docker exec which runs make | HIGH -- entirely different execution model |
| PDK | nangate45 (10 metal layers, simple cell names) | sky130hd (5+1 metal layers, long cell names) | HIGH -- every parameter changes |
| Flow engine | Standalone Tcl scripts | ORFS Makefile targets | HIGH -- different directory structure, variable system |
| Error handling | Shell exit codes + log parsing | MCP tool responses + container log extraction | HIGH -- new failure modes (timeout, Docker, MCP protocol) |
| Dependencies | yosys + openroad on PATH | Docker + orfs image + Node.js + MCP server | MEDIUM -- more moving parts |
| SDC generation | Custom bash script | Still custom, but clock period defaults change | LOW -- same logic, different values |
| Report parsing | grep/sed on log files | ORFS metadata.json + report files in container | MEDIUM -- different file paths and formats |

---

## Sources

- **sky130hd platform files (verified locally 2026-04-01):**
  - `config.mk`: `/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/sky130hd/config.mk` -- all cell names, layer names, PDK constants
  - `pdn.tcl`: VPWR/VGND global connections, met1/met4/met5 PDN grid
  - `fastroute.tcl`: references `$::env(MIN_ROUTING_LAYER)` through `$::env(MAX_ROUTING_LAYER)`
  - `tapcell.tcl`: references `$::env(TAP_CELL_NAME)` = `sky130_fd_sc_hd__tapvpwrvgnd_1`
  - `setRC.tcl`: li1/met1-met5 layer RC values, via resistances
  - `make_tracks.tcl`: li1/met1-met5 track pitches
  - `rcx_patterns.rules`: symlink to `../sky130hs/rcx_patterns.rules`
- **sky130hd GCD example (verified locally 2026-04-01):** `designs/sky130hd/gcd/config.mk` + `constraint.sdc`
- **ORFS variables.mk (verified locally 2026-04-01):** RESULTS_DIR, LOG_DIR, REPORTS_DIR path conventions
- **MCP SDK documentation:**
  - [Build an MCP Server](https://modelcontextprotocol.io/docs/develop/build-server) -- stdio transport, tool registration
  - [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk) -- server.md, transport docs
  - [Nearform MCP Tips and Pitfalls](https://nearform.com/digital-community/implementing-model-context-protocol-mcp-tips-tricks-and-pitfalls/)
- **Claude Code MCP integration:**
  - [Claude Code MCP docs](https://code.claude.com/docs/en/mcp) -- .mcp.json configuration
  - [Docker MCP Toolkit](https://docs.docker.com/ai/mcp-catalog-and-toolkit/toolkit/)
- **MCP timeout issues:**
  - [Docker MCP Tools Timeout (GitHub #4202)](https://github.com/anthropics/claude-code/issues/4202)
  - [MCP_TOOL_TIMEOUT not respected (GitHub #17662)](https://github.com/anthropics/claude-code/issues/17662)
  - [Docker containers not stopped (GitHub #29058)](https://github.com/anthropics/claude-code/issues/29058)
  - [Make MCP Tool Execution Timeout Configurable (GitHub #22542)](https://github.com/anthropics/claude-code/issues/22542)
- **sky130hd timing and PDN issues:**
  - [PDN-0185 insufficient width (OpenROAD Discussion #7891)](https://github.com/The-OpenROAD-Project/OpenROAD/discussions/7891)
  - [VPWR/VGND macro connections (OpenLane #2019)](https://github.com/The-OpenROAD-Project/OpenLane/issues/2019)
  - [PDN generation failure (OpenLane #596)](https://github.com/The-OpenROAD-Project/OpenLane/issues/596)
  - [Timing signoff SS corner (OpenLane #784)](https://github.com/The-OpenROAD-Project/OpenLane/issues/784)
  - [Antenna repair issues (OpenROAD #2207)](https://github.com/The-OpenROAD-Project/OpenROAD/issues/2207)
- **ORFS flow documentation:**
  - [Flow Variables](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html)
  - [Adding New Designs](https://openroad-flow-scripts.readthedocs.io/en/latest/user/AddingNewDesign.html)
  - [Docker Shell](https://openroad-flow-scripts.readthedocs.io/en/latest/user/DockerShell.html)
- **SkyWater PDK:**
  - [Layers Reference](https://skywater-pdk.readthedocs.io/en/main/rules/layers.html)
  - [Standard Cell Libraries](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/foundry-provided.html)
- **Existing ChipAgent codebase (verified locally 2026-04-01):** synth.sh, pnr.sh, synth.tcl, pnr.tcl, generate_sdc.sh, SKILL.md -- all nangate45-specific, all must be replaced

---
*Domain pitfalls for: ChipAgent v1.1.5 -- sky130hd MCP Backend*
*Researched: 2026-04-01*
*Complements v1.1.2 PITFALLS.md (which covers Chisel-specific and general ASIC flow pitfalls that remain valid)*
