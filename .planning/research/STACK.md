# Stack Research

**Domain:** MCP Server + ORFS sky130hd Backend for ChipAgent Claude Code Plugin
**Researched:** 2026-04-01
**Confidence:** HIGH

## Scope

This document covers ONLY the new stack additions for v1.1.5. The existing validated stack (Chisel 3.6.1, Scala 2.13.10, sbt 1.10.7, Verilator, npm plugin packaging) is not re-researched. Focus: MCP server implementation, ORFS make-based backend, sky130hd PDK integration.

Previous v1.1.2 stack (standalone Tcl scripts, nangate45) is being REPLACED. This document supersedes the prior STACK.md.

---

## Recommended Stack

### Core Technologies (NEW for v1.1.5)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| @modelcontextprotocol/sdk | ^1.29.0 | MCP server SDK (TypeScript) | Official SDK, v1.x production-stable. v2 is pre-alpha (Q1 2026 target missed), not ready. Provides McpServer class, StdioServerTransport, Zod-based tool schemas. 37K+ dependent projects on npm. |
| zod | ^3.25.0 | Schema validation for MCP tool inputs | Required peer dependency of @modelcontextprotocol/sdk. SDK imports from `zod/v4` internally but is backwards-compatible with 3.25+. Pin to 3.x to avoid Zod 4 API surface changes. |
| TypeScript | ^5.8.0 | Type-safe MCP server source | Node 24.14.0 on this system has native type-stripping (default, no flag needed). TypeScript 5.8+ supports `erasableSyntaxOnly` for guaranteed Node compatibility. No tsc build step needed at runtime. |
| Node.js | >=22.6.0 (system: 24.14.0) | MCP server runtime | System has v24.14.0 with native TS type-stripping. StdioServerTransport uses node stdio pipes. MCP SDK requires Node >=18 for stable ESM. |
| ORFS Makefile | (installed: ~/OpenROAD-flow-scripts) | Make-based ASIC backend flow | Already installed on system. Provides synth/floorplan/place/cts/route/finish targets with full sky130hd platform support. Replaces standalone Tcl scripts with upstream-maintained flow. |
| sky130hd PDK | (bundled in ORFS platforms/) | 130nm open-source SkyWater PDK | Available at ~/OpenROAD-flow-scripts/flow/platforms/sky130hd/. Contains liberty, LEF, GDS, RC extraction rules, PDN config, fastroute, tapcell, setRC. Replaces nangate45. Required by task2. |

### Installed Tool Versions (Verified 2026-04-01)

| Tool | Version | Path | Status |
|------|---------|------|--------|
| Yosys | 0.53+26 | `/usr/local/bin/yosys` | Verified working |
| OpenROAD | 26Q1-951-g6975124cf2 | `/usr/bin/openroad` | Verified working |
| KLayout | installed | `/usr/bin/klayout` | Verified working (was missing in v1.1.2, now present) |
| Node.js | v24.14.0 | system | Verified, native TS stripping active |
| npm | 11.9.0 | system | Verified |
| tsx | 4.21.0 (via npx) | system | Available as fallback TS runner |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tsx | ^4.21.0 | TypeScript execution fallback | Only if running on Node < 22.6.0 (no native TS strip). System has Node 24.14.0 so tsx is safety net. Use `npx tsx` in .mcp.json command for maximum portability across Node versions. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Node native TS | Run .ts files without build step | Node 24+ strips types by default. `node mcp-server/index.ts` just works. |
| npx tsx | Portable TS runner for .mcp.json | Zero-config, esbuild-based. More reliable than raw node for ESM + .js extension resolution in SDK imports. |
| tsc --noEmit | CI/dev type checking only | Types are stripped at runtime but still need IDE/CI checking. Not needed for running the server. |

---

## MCP Server Architecture

### Transport: stdio (not HTTP)

Use stdio transport. Claude Code spawns the MCP server as a child process and communicates over stdin/stdout via JSON-RPC 2.0.

**Why stdio:**
1. Plugin is local-only (runs on user's machine alongside Claude Code)
2. No authentication needed (process isolation provides security)
3. Simplest setup -- no ports, no network, no TLS
4. Standard for Claude Code plugin MCP servers (per official docs)
5. SSE is deprecated in Claude Code as of early 2026

### Key Import Paths (v1.x -- verified)

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
```

Note: Import paths use `.js` extension even in TypeScript source. This is required for Node ESM resolution with the MCP SDK's package exports.

### Tool Registration Pattern

```typescript
server.tool(
  "orfs_synth",
  "Run Yosys synthesis via ORFS make target for sky130hd",
  {
    module_name: z.string().describe("Module name (PascalCase)"),
    verilog_path: z.string().describe("Path to compiled Verilog file"),
    clock_period_ns: z.number().optional().describe("Clock period in ns (default: 10)"),
  },
  async ({ module_name, verilog_path, clock_period_ns }) => {
    // Generate config.mk, SDC, run make synth, parse metrics, return
    return { content: [{ type: "text", text: JSON.stringify(result) }] };
  }
);
```

### Plugin Registration: .mcp.json

Create `.mcp.json` at plugin root (standard Claude Code pattern):

```json
{
  "mcpServers": {
    "chip-agent-orfs": {
      "command": "npx",
      "args": ["tsx", "mcp-server/index.ts"],
      "env": {}
    }
  }
}
```

The `cwd` defaults to the plugin root directory. ORFS path is detected at runtime from env.json (written by `/chip-agent:initialize`), not hardcoded in .mcp.json.

Plugin MCP servers connect automatically at session startup. No manual `claude mcp add` needed.

### MCP Server File Structure

```
ChipAgent/
  mcp-server/
    index.ts              # Entry: create McpServer, register all tools, connect stdio
    tools/
      orfs-synth.ts       # Tool: run ORFS make synth
      orfs-floorplan.ts   # Tool: run ORFS make floorplan
      orfs-place.ts       # Tool: run ORFS make place
      orfs-cts.ts         # Tool: run ORFS make cts
      orfs-route.ts       # Tool: run ORFS make route
      orfs-finish.ts      # Tool: run ORFS make finish (report + GDS)
    lib/
      orfs-runner.ts      # Shared: spawn make process, capture output, handle errors
      config-gen.ts       # Generate config.mk and SDC for a module
      metrics.ts          # Parse ORFS JSON metrics and .rpt report files
      paths.ts            # Path resolution: ORFS dir, sky130hd platform, workspace
  .mcp.json               # Plugin MCP server registration
  tsconfig.json           # TypeScript config (noEmit, erasableSyntaxOnly)
```

---

## ORFS Make Flow Details

### How ORFS Is Driven

ORFS is driven by: `make -C <FLOW_DIR> DESIGN_CONFIG=<path/to/config.mk> <target>`

The MCP server generates a per-module `config.mk` in the workspace, then invokes make with it. ORFS handles all the complex Tcl scripting, variable resolution, and tool invocation internally.

### Make Targets (6-Stage Pipeline)

Each MCP tool wraps one ORFS make target.

| MCP Tool | ORFS Target | What It Does | Depends On |
|----------|-------------|--------------|------------|
| `orfs_synth` | `make synth` | Yosys synthesis -> 1_synth.odb | config.mk + Verilog + SDC |
| `orfs_floorplan` | `make floorplan` | Floorplan + tapcell + PDN -> 2_floorplan.odb | synth |
| `orfs_place` | `make place` | Global + detailed placement -> 3_place.odb | floorplan |
| `orfs_cts` | `make cts` | Clock tree synthesis -> 4_cts.odb | place |
| `orfs_route` | `make route` | Global + detailed routing + fill -> 5_route.odb | cts |
| `orfs_finish` | `make finish` | Final report + GDS export -> 6_final.gds | route |

### Per-Module config.mk (Generated by MCP Server)

```makefile
export DESIGN_NAME    = ALU
export PLATFORM       = sky130hd
export VERILOG_FILES  = /home/user/ChipAgent/MyDesign/ALU/workspace/generated/ALU.v
export SDC_FILE       = /home/user/ChipAgent/MyDesign/ALU/workspace/pnr/constraint.sdc
export CORE_UTILIZATION = 40
```

Minimal variables required. The sky130hd `config.mk` in ORFS platform sets all PDK-specific defaults (liberty, LEF, GDS, fill cells, dont-use cells, routing layers, etc.). Only design-specific variables need to be in the per-module config.

### ORFS Output Directories

ORFS writes to these directories (relative to FLOW_HOME which is ~/OpenROAD-flow-scripts/flow/):

```
results/sky130hd/<DESIGN_NICKNAME>/base/
  1_synth.odb, 2_floorplan.odb, ..., 6_final.gds, 6_final.def, 6_final.v

logs/sky130hd/<DESIGN_NICKNAME>/base/
  1_synth.json, 2_1_floorplan.json, ..., 6_report.json  (structured JSON metrics)

reports/sky130hd/<DESIGN_NICKNAME>/base/
  6_finish.rpt  (timing/power/area combined report)
```

The MCP server reads from these directories after each make target completes, extracts metrics, and copies final artifacts to the module workspace.

### JSON Metrics Per Stage

Each ORFS stage writes a JSON metrics file via the `-metrics` flag. Example from route stage:

```json
{
  "detailedroute__route__drc_errors": 0,
  "detailedroute__route__wirelength": 4591,
  "detailedroute__route__vias": 3674
}
```

The `report_metrics` Tcl procedure (called at stages 1-6) writes to `.rpt` files containing: WNS, TNS, worst_slack (setup + hold), clock_min_period, power, design_area, ERC metrics (slew/cap/fanout violations), and critical path delay. These are the primary sources for the PPA summary report.

---

## sky130hd PDK Configuration

### File Locations (Verified on System)

| File | Path (relative to platforms/sky130hd/) | Purpose |
|------|----------------------------------------|---------|
| Liberty | `lib/sky130_fd_sc_hd__tt_025C_1v80.lib` | Timing/power (TT corner, 25C, 1.8V) |
| Tech LEF | `lef/sky130_fd_sc_hd.tlef` | Layer definitions |
| Cell LEF | `lef/sky130_fd_sc_hd_merged.lef` | Standard cell geometries |
| GDS | `gds/sky130_fd_sc_hd.gds` | Cell layouts for GDS merge |
| RCX rules | `rcx_patterns.rules` (symlink -> sky130hs/) | Parasitic extraction |
| PDN | `pdn.tcl` | VDD/VSS grid: met1 followpins, met4/met5 stripes |
| Tracks | `make_tracks.tcl` | li1 through met5 track definitions |
| FastRoute | `fastroute.tcl` | Layer adjustment 0.2, clock met3-met5, signal met1-met5 |
| Tapcell | `tapcell.tcl` | `sky130_fd_sc_hd__tapvpwrvgnd_1`, distance 14 |
| RC model | `setRC.tcl` | Per-layer capacitance and resistance (li1 through met5) |
| Fill cells | (in config.mk) | `sky130_fd_sc_hd__fill_1/2/4/8` |
| KLayout tech | `sky130hd.lyt` + `sky130hd.lyp` | GDS viewing/export technology file |

### Key sky130hd Platform Defaults (from config.mk)

| Variable | Value | Notes |
|----------|-------|-------|
| PROCESS | 130 (nm) | 3x larger than nangate45 |
| PLACE_SITE | `unithd` | Core placement site |
| PLACE_DENSITY | 0.60 | Default, higher than nangate45's 0.30 |
| IO_PLACER_H | `met3` | Horizontal pin layer |
| IO_PLACER_V | `met2` | Vertical pin layer |
| MIN_ROUTING_LAYER | `met1` | Signal routing floor |
| MAX_ROUTING_LAYER | `met5` | Signal routing ceiling (only 5 metals vs nangate45's 10) |
| MIN_CLK_ROUTING_LAYER | `met3` | Clock routing floor |
| TAP_CELL_NAME | `sky130_fd_sc_hd__tapvpwrvgnd_1` | Tap/well-tie cell |
| FILL_CELLS | `sky130_fd_sc_hd__fill_1/2/4/8` | Filler cells |
| PWR_NETS_VOLTAGES | `VDD 1.8` | 1.8V supply |
| GND_NETS_VOLTAGES | `VSS 0.0` | Ground |
| RCX_RULES | `rcx_patterns.rules` | Parasitic extraction rules |

### Critical Differences from nangate45 (What Changes)

| Aspect | nangate45 (v1.1.2) | sky130hd (v1.1.5) | Impact on ChipAgent |
|--------|---------------------|---------------------|---------------------|
| Process | 45nm | 130nm | Clock periods must be relaxed: 10-20ns default instead of 2ns |
| Site name | `FreePDK45_38x28_10R_NP_162NW_34O` | `unithd` | Handled by ORFS config.mk, no manual reference needed |
| Metal layers | 10 (metal1-metal10) | 5+li1 (met1-met5) | Fewer routing resources. ORFS config handles layer assignment |
| PDN grid | M1-M4-M7 | M1-M4-M5 | Handled by platform pdn.tcl sourced by ORFS |
| Liberty | `NangateOpenCellLibrary_typical.lib` | `sky130_fd_sc_hd__tt_025C_1v80.lib` | Handled by ORFS config.mk LIB_FILES variable |
| Tap cell | `TAPCELL_X1`, distance 120 | `sky130_fd_sc_hd__tapvpwrvgnd_1`, distance 14 | Handled by platform tapcell.tcl |
| Default density | 0.30 | 0.60 | sky130hd cells are larger, need higher density |
| Clock default | 2.0ns | 10-20ns recommended | **Must update SDC generation defaults** |
| DONT_USE | 4 cells | ~30+ lpflow/probe cells | Handled automatically by ORFS config.mk |
| Standalone scripts | Custom synth.tcl + pnr.tcl | ORFS make flow | **Scripts are replaced entirely by MCP tools calling make** |

**Key takeaway:** By switching from standalone Tcl to ORFS make, all PDK-specific configuration (site names, cell names, routing layers, PDN, tapcells, dont-use lists) is handled by the platform config.mk. The MCP server only needs to set DESIGN_NAME, PLATFORM, VERILOG_FILES, SDC_FILE, and optionally CORE_UTILIZATION.

---

## Installation

### New Dependencies (add to package.json)

```json
{
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.29.0",
    "zod": "^3.25.0"
  },
  "devDependencies": {
    "typescript": "^5.8.0"
  }
}
```

```bash
# Install new runtime dependencies
npm install @modelcontextprotocol/sdk zod

# Dev dependency for type checking (not needed at runtime)
npm install -D typescript
```

### package.json Updates

```json
{
  "name": "chip-agent",
  "version": "0.2.0",
  "type": "module",
  "files": [
    "bin/",
    ".claude-plugin/",
    ".mcp.json",
    "mcp-server/",
    "skills/",
    "agents/",
    "hooks/",
    "scripts/",
    "CLAUDE.md"
  ]
}
```

Changes from current:
- Add `"type": "module"` -- required for ESM imports used by MCP SDK
- Add `.mcp.json` to files list -- plugin MCP server registration
- Add `"mcp-server/"` to files list -- MCP server TypeScript source

### tsconfig.json (NEW file at project root)

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "erasableSyntaxOnly": true,
    "skipLibCheck": true
  },
  "include": ["mcp-server/**/*.ts"]
}
```

`erasableSyntaxOnly: true` ensures the TypeScript source is compatible with Node's native type stripping. This prohibits enums, namespaces, and parameter properties -- all features that require code generation rather than simple type erasure.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| @modelcontextprotocol/sdk v1.29 | @modelcontextprotocol/server (v2 package) | When v2 reaches stable release. Currently pre-alpha. v1 will receive bug fixes for 6+ months after v2 ships. |
| zod ^3.25 | zod ^4.x | When MCP SDK explicitly requires Zod 4. SDK currently uses zod/v4 internally but is backwards-compat with 3.25+. Stay on 3.x for stability. |
| stdio transport | HTTP (Streamable HTTP) | Only if server needs to run remotely or be shared across multiple clients. Not applicable for a local plugin. |
| npx tsx (in .mcp.json command) | node (direct execution) | Node 24 can run .ts natively, but npx tsx is more reliable for ESM + .js extension resolution in @modelcontextprotocol/sdk import paths. Use npx tsx for portability. |
| ORFS Makefile backend | Standalone Tcl scripts (v1.1.2) | Never. ORFS Makefile is upstream-maintained, handles all PDK config, provides structured JSON metrics, and gets bug fixes from the community. Standalone scripts duplicate effort. |
| sky130hd | nangate45 | Never for this milestone. nangate45 is simpler but sky130hd is required by task2. Multi-PDK support is out of scope (deferred). |
| Per-module config.mk | Shared config.mk | Must be per-module because DESIGN_NAME, VERILOG_FILES, SDC_FILE differ. ORFS expects these set per design invocation. |
| Copy results to workspace | Redirect ORFS WORK_HOME | WORK_HOME override adds complexity and risks breaking ORFS internal path assumptions. Let ORFS use its default directories, then copy final artifacts to module workspace. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| @modelcontextprotocol/server (v2 package) | Pre-alpha as of April 2026. API unstable, no production guarantees. | @modelcontextprotocol/sdk ^1.29.0 (v1.x stable) |
| SSE transport | Deprecated in Claude Code as of early 2026. Legacy only. | stdio for local plugin |
| ts-node | Requires TypeScript + SWC as peer deps, slower than tsx, more config. | npx tsx (zero-config, esbuild-based) or native Node TS stripping |
| zod 4.x | MCP SDK peer dep says >=3.25. Zod 4 has breaking API changes. No benefit to upgrading. | zod ^3.25.0 |
| Standalone Yosys/OpenROAD Tcl scripts | v1.1.2 approach. Duplicates ORFS upstream logic. Misses bug fixes, platform config updates, JSON metric reporting, proper KLayout integration. | ORFS make targets via MCP tools |
| nangate45 PDK | Task2 requires sky130hd. nangate45 standalone scripts are being replaced. | sky130hd via ORFS platform |
| ORFS WORK_HOME override | Setting WORK_HOME to workspace dir risks breaking ORFS internal relative path resolution. | Let ORFS write to defaults, copy artifacts to workspace after each stage |
| tsc compile step for runtime | Adds build complexity for a ~300-line MCP server. Node 24 strips types natively, npx tsx handles older Node. | npx tsx for runtime, tsc --noEmit for CI/dev type checking only |
| Manual PDK file references | sky130hd has complex DONT_USE_CELLS list, multiple mapping files, specific PDN config. Hardcoding these is fragile. | Let ORFS config.mk handle all PDK-specific settings |
| express/hono middleware packages | @modelcontextprotocol/express etc. are for HTTP servers. Not needed for stdio transport. | StdioServerTransport only |

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| @modelcontextprotocol/sdk@^1.29.0 | zod@>=3.25.0 | SDK uses zod/v4 internally but backwards-compat. Zod is a peer dependency. |
| @modelcontextprotocol/sdk@^1.29.0 | Node.js >=18 | SDK uses ESM, needs Node 18+ for stable ESM support. |
| TypeScript@^5.8.0 | Node.js 22.6+ (native TS) | `erasableSyntaxOnly` ensures compat with Node type stripping. |
| ORFS (installed) | OpenROAD 26Q1 | System has OpenROAD 26Q1-951-g6975124cf2. Makefile from same era. |
| ORFS (installed) | Yosys 0.53+ | System has Yosys 0.53+26. ORFS locates yosys via YOSYS_EXE or PATH. |
| ORFS (installed) | KLayout | System has KLayout installed. ORFS uses it for GDS merge via def2stream.py. |
| sky130hd PDK | ORFS flow | Bundled in ORFS at platforms/sky130hd/. All config.mk variables pre-set. |
| npm chip-agent package | "type": "module" | Required change for ESM imports in MCP server. Does NOT break existing bash scripts or skill markdown files. |

---

## Integration Points

### MCP Server <-> Existing Plugin

| Integration | How |
|-------------|-----|
| SKILL.md `/chip-agent:pnr` | Rewritten to call MCP tools (orfs_synth, orfs_floorplan, etc.) instead of shell scripts |
| spec.json | MCP tools read clock_period_ns from spec.json (same interface as v1.1.2) |
| Workspace dirs | MCP tools write to same MyDesign/<Mod>/workspace/pnr/ structure |
| /chip-agent:initialize | Updated to detect ORFS_FLOW_DIR and sky130hd (replacing nangate45 detection) |
| env.json | New fields: `orfs.flow_dir`, `pdk.sky130hd.path` (replacing `pdk.nangate45.path`) |

### MCP Server <-> ORFS

| Interaction | Direction | Mechanism |
|-------------|-----------|-----------|
| Design config | Server -> ORFS | Write config.mk to workspace, pass via DESIGN_CONFIG= |
| SDC constraints | Server -> ORFS | Write constraint.sdc, referenced by config.mk SDC_FILE |
| Make invocation | Server -> ORFS | `child_process.execFile("make", ["-C", flowDir, "DESIGN_CONFIG=...", target])` |
| Stage status | ORFS -> Server | Make exit code (0 = success, non-zero = failure) |
| Structured metrics | ORFS -> Server | JSON files in logs/sky130hd/<design>/base/*.json |
| Report files | ORFS -> Server | .rpt files in reports/sky130hd/<design>/base/ |
| Final artifacts | ORFS -> Server | results/sky130hd/<design>/base/6_final.{gds,def,v} |

### Artifact Mapping (ORFS output -> module workspace)

```
ORFS output:                                    Module workspace:
results/sky130hd/<Mod>/base/6_final.gds    -->  MyDesign/<Mod>/workspace/pnr/<Mod>.gds
results/sky130hd/<Mod>/base/6_final.def    -->  MyDesign/<Mod>/workspace/pnr/<Mod>.routed.def
results/sky130hd/<Mod>/base/6_final.v      -->  MyDesign/<Mod>/workspace/pnr/<Mod>.synth.v
reports/sky130hd/<Mod>/base/*              -->  MyDesign/<Mod>/workspace/pnr/reports/
logs/sky130hd/<Mod>/base/*.json            -->  MyDesign/<Mod>/workspace/pnr/metrics/ (aggregated)
```

### SDC Generation Changes for sky130hd

The default clock period must change from 2.0ns (nangate45) to a sky130-appropriate value:

| Module Type | nangate45 Default | sky130hd Default | Rationale |
|-------------|-------------------|------------------|-----------|
| Sequential | 10.0ns (100MHz) | 10.0ns (100MHz) | sky130hd typical gate delays are 0.5-2ns. 10ns gives 5-20x margin for small modules. ORFS riscv32i example uses 10.0ns. |
| Combinational | 10.0ns max_delay | 10.0ns max_delay | Matched to sequential default for consistency. |

Auto-fix retry: increase clock period by 50% per attempt (same strategy as v1.1.2, but starting from 10ns instead of 2ns).

---

## Environment Detection Updates

### New env.json Schema (replaces nangate45 fields)

```json
{
  "tools": {
    "yosys": { "version": "0.53+26", "path": "/usr/local/bin/yosys" },
    "openroad": { "version": "26Q1-951-g6975124cf2", "path": "/usr/bin/openroad" },
    "klayout": { "version": "...", "path": "/usr/bin/klayout" }
  },
  "orfs": {
    "flow_dir": "/home/mingzhenjia/OpenROAD-flow-scripts/flow",
    "version": "detected-from-git-or-env.sh"
  },
  "pdk": {
    "sky130hd": {
      "path": "/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/sky130hd",
      "liberty": "lib/sky130_fd_sc_hd__tt_025C_1v80.lib",
      "tech_lef": "lef/sky130_fd_sc_hd.tlef",
      "cell_lef": "lef/sky130_fd_sc_hd_merged.lef"
    }
  },
  "capabilities": {
    "can_compile": true,
    "can_lint": true,
    "can_simulate": true,
    "can_synthesize": true,
    "can_pnr": true,
    "can_gds": true
  },
  "docker": {
    "available": false,
    "orfs_image": null
  }
}
```

### ORFS Path Detection (resolution order)

1. `ORFS_FLOW_DIR` environment variable (if set)
2. `~/OpenROAD-flow-scripts/flow` (standard clone location)
3. `/opt/OpenROAD-flow-scripts/flow` (system install location)
4. Error: ORFS not found

### sky130hd Validation

Verify sky130hd is usable by checking the liberty file exists:
```bash
test -f "$ORFS_FLOW_DIR/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
```

---

## Sources

- [@modelcontextprotocol/sdk npm page](https://www.npmjs.com/package/@modelcontextprotocol/sdk) -- Version 1.29.0, peer deps, installation (HIGH confidence)
- [MCP TypeScript SDK GitHub](https://github.com/modelcontextprotocol/typescript-sdk) -- Server API, import paths, examples (HIGH confidence)
- [MCP SDK server.md docs](https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/server.md) -- McpServer class, tool registration, transport (HIGH confidence)
- [Claude Code MCP docs](https://code.claude.com/docs/en/mcp) -- stdio transport, plugin MCP servers, .mcp.json format (HIGH confidence)
- [MCP TypeScript SDK v2 docs](https://ts.sdk.modelcontextprotocol.io/v2/) -- v2 pre-alpha status confirmation (MEDIUM confidence)
- System verification: ORFS installed at ~/OpenROAD-flow-scripts with sky130hd platform, all files inspected (HIGH confidence)
- System verification: Node v24.14.0, native TS type-stripping active, tsx 4.21.0 available (HIGH confidence)
- System verification: OpenROAD 26Q1, Yosys 0.53+26, KLayout installed (HIGH confidence)
- ORFS Makefile (~/OpenROAD-flow-scripts/flow/Makefile) -- Make targets synth/floorplan/place/cts/route/finish, do- prefixed substeps (HIGH confidence, read line-by-line)
- ORFS variables.mk -- Variable resolution, output directories, tool paths (HIGH confidence, read from source)
- ORFS flow.sh -- Stage execution wrapper, JSON metrics via -metrics flag (HIGH confidence, read from source)
- ORFS report_metrics.tcl -- WNS/TNS/power/area/ERC metric extraction (HIGH confidence, read from source)
- sky130hd config.mk -- All platform defaults, DONT_USE, fill cells, routing layers (HIGH confidence, read from source)
- sky130hd pdn.tcl, setRC.tcl, tapcell.tcl, make_tracks.tcl, fastroute.tcl -- Platform scripts (HIGH confidence, read from source)
- ORFS designs/sky130hd/gcd/config.mk and riscv32i/config.mk -- Reference design configs (HIGH confidence)
- ORFS logs/nangate45/gcd/base/5_2_route.json -- JSON metrics format example (HIGH confidence, read from file)

---
*Stack research for: ChipAgent v1.1.5 -- sky130hd MCP Backend*
*Researched: 2026-04-01*
