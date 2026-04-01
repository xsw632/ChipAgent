# Phase 13: MCP Server + Environment Foundation - Research

**Researched:** 2026-04-01
**Domain:** MCP TypeScript Server, sky130hd PDK detection, ORFS environment
**Confidence:** HIGH

## Summary

This phase creates a TypeScript MCP server with stdio transport that Claude Code discovers via `.mcp.json`, implements a `check_environment` tool reporting ORFS/sky130hd/Docker status, rewrites `/chip-agent:initialize` for sky130hd detection (replacing nangate45), and removes legacy nangate45 scripts.

The MCP SDK (`@modelcontextprotocol/sdk`) provides a clean `McpServer` + `StdioServerTransport` pattern. Node.js 24.14.0 on this machine supports native TypeScript type stripping (`--experimental-strip-types`), so no build step is needed -- TypeScript files run directly. The sky130hd PDK is confirmed present at `~/OpenROAD-flow-scripts/flow/platforms/sky130hd/` with liberty, LEF, and GDS files.

**Primary recommendation:** Create `mcp-server/` directory with a single `index.ts` entry point using `@modelcontextprotocol/sdk`, register via project-scoped `.mcp.json`, and run with `node --experimental-strip-types`.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MCP-01 | MCP Server scaffold with stdio transport, TypeScript source, and .mcp.json plugin registration | MCP SDK server pattern documented below; `.mcp.json` format confirmed |
| MCP-02 | `check_environment` tool verifying ORFS path, sky130hd PDK presence, and Docker availability | Tool registration pattern with Zod schemas; sky130hd file paths confirmed on disk |
| ENV-01 | sky130hd PDK detection in /chip-agent:initialize replacing nangate45 detection | sky130hd PDK structure documented; detect-env.sh modification points identified |
| ENV-02 | Docker availability detection with backend_mode field (local/docker) in env.json | `docker --version` check; env.json schema extension documented |
| ENV-03 | ORFS installation detection and path resolution in env.json | ORFS candidate path chain documented; key files to check identified |
| CLN-01 | Remove nangate45-specific scripts (synth.tcl, pnr.tcl, validate-pdk.sh, def2gds.py) | All 4 files confirmed present at scripts/; safe to delete |
| CLN-02 | Update CLAUDE.md tech stack table and documentation for sky130hd + MCP architecture | Current CLAUDE.md structure understood; sections to update identified |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @modelcontextprotocol/sdk | 1.29.0 | MCP server framework | Official SDK; project decision locked |
| zod | 3.25.0 | Input schema validation | Required by MCP SDK for tool schemas |
| Node.js | 24.x | Runtime with native TS | Already installed; no build step needed |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| typescript | 5.x | Type checking only (not compilation) | `npx tsc --noEmit` for CI/dev checks |

**Installation:**
```bash
cd mcp-server && npm init -y && npm install @modelcontextprotocol/sdk@1.29.0 zod@3.25.0
```

## Architecture Patterns

### Recommended Project Structure
```
ChipAgent/
├── mcp-server/
│   ├── package.json          # MCP server deps
│   ├── tsconfig.json         # Type-checking only (noEmit)
│   ├── index.ts              # Entry: McpServer + StdioServerTransport
│   └── tools/
│       └── check-environment.ts  # check_environment tool implementation
├── .mcp.json                 # Project-scoped MCP registration
├── scripts/
│   ├── detect-env.sh         # MODIFIED: sky130hd instead of nangate45
│   ├── synth.tcl             # DELETED (CLN-01)
│   ├── pnr.tcl               # DELETED (CLN-01)
│   ├── validate-pdk.sh       # DELETED (CLN-01)
│   └── def2gds.py            # DELETED (CLN-01)
└── skills/
    └── initialize/SKILL.md   # MODIFIED: sky130hd + Docker + ORFS
```

### Pattern 1: MCP Server with stdio transport
**What:** TypeScript MCP server using `McpServer` class + `StdioServerTransport`
**When to use:** Always -- this is the only transport for Claude Code local plugins
**Example:**
```typescript
// Source: https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/server.md
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "chipagent-backend",
  version: "0.1.0",
});

server.registerTool(
  "check_environment",
  {
    title: "Check Environment",
    description: "Verify ORFS path, sky130hd PDK presence, and Docker availability",
    inputSchema: z.object({}),
  },
  async () => {
    // implementation
    return {
      content: [{ type: "text", text: JSON.stringify(result) }],
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
```

### Pattern 2: .mcp.json project registration
**What:** Project-scoped `.mcp.json` at repo root so Claude Code auto-discovers the server
**Example:**
```json
{
  "mcpServers": {
    "chipagent-backend": {
      "type": "stdio",
      "command": "node",
      "args": ["--experimental-strip-types", "mcp-server/index.ts"]
    }
  }
}
```

### Pattern 3: check_environment tool response schema
**What:** Structured JSON output from the environment check tool
**Example:**
```typescript
const result = {
  orfs: {
    installed: true,
    path: "/home/user/OpenROAD-flow-scripts",
    flow_path: "/home/user/OpenROAD-flow-scripts/flow",
  },
  sky130hd: {
    installed: true,
    path: "/home/user/OpenROAD-flow-scripts/flow/platforms/sky130hd",
    liberty: "lib/sky130_fd_sc_hd__tt_025C_1v80.lib",
    tech_lef: "lef/sky130_fd_sc_hd.tlef",
    cell_lef: "lef/sky130_fd_sc_hd_merged.lef",
    gds: "gds/sky130_fd_sc_hd.gds",
  },
  docker: {
    installed: false,
    version: null,
  },
  backend_mode: "local",  // "local" | "docker"
};
```

### Pattern 4: detect-env.sh sky130hd detection
**What:** Replace nangate45 PDK detection block with sky130hd equivalent
**Key file paths to check:**
- Liberty: `lib/sky130_fd_sc_hd__tt_025C_1v80.lib`
- Tech LEF: `lef/sky130_fd_sc_hd.tlef`
- Cell LEF: `lef/sky130_fd_sc_hd_merged.lef`
- GDS: `gds/sky130_fd_sc_hd.gds`

**Candidate directory chain (same as nangate45 but sky130hd):**
```bash
SKY130HD_CANDIDATES=(
  "${SKY130HD_DIR_OVERRIDE:-}"
  "${ORFS_DIR:-}/flow/platforms/sky130hd"
  "$HOME/OpenROAD-flow-scripts/flow/platforms/sky130hd"
  "/opt/OpenROAD-flow-scripts/flow/platforms/sky130hd"
)
```

### Anti-Patterns to Avoid
- **Do NOT use `emitSystemVerilog`** in any MCP tool -- Chisel API rules from CLAUDE.md still apply
- **Do NOT log to stdout** from MCP server -- stdio transport uses stdout for JSON-RPC; use stderr for debug logging
- **Do NOT hardcode PDK paths** -- use the candidate chain pattern from detect-env.sh

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| MCP protocol handling | Custom JSON-RPC parser | `@modelcontextprotocol/sdk` | Protocol versioning, transport abstraction, tool discovery |
| Input validation | Manual type checks | Zod schemas via MCP SDK | SDK integrates Zod natively for tool input schemas |
| TypeScript compilation | Webpack/esbuild build step | `node --experimental-strip-types` | Node 24 strips types natively; zero config |

## Common Pitfalls

### Pitfall 1: stdout pollution kills MCP stdio transport
**What goes wrong:** Any `console.log()` in MCP server code corrupts the JSON-RPC stream
**Why it happens:** stdio transport uses stdout exclusively for protocol messages
**How to avoid:** Use `console.error()` for all debug output; or use the SDK's built-in logging
**Warning signs:** "Failed to parse MCP message" errors in Claude Code

### Pitfall 2: Missing .js extension in TypeScript imports
**What goes wrong:** Node's ESM loader requires `.js` extensions even for `.ts` files when using type stripping
**Why it happens:** `--experimental-strip-types` strips types but doesn't rewrite import specifiers
**How to avoid:** Use `.js` extensions in all import paths (e.g., `import { x } from "./tools/check-environment.js"`)
**Warning signs:** `ERR_MODULE_NOT_FOUND` at runtime

### Pitfall 3: Forgetting to add ORFS detection alongside sky130hd
**What goes wrong:** sky130hd is detected but ORFS root path is not stored, breaking later phases that need `make -C $ORFS_DIR/flow`
**How to avoid:** Detect ORFS root directory separately from PDK; store both `orfs_path` and `sky130hd_path` in env.json

### Pitfall 4: Removing nangate45 scripts breaks existing pnr skill
**What goes wrong:** `/chip-agent:pnr` calls synth.sh/pnr.sh which reference synth.tcl/pnr.tcl
**How to avoid:** The pnr skill calls `synth.sh` and `pnr.sh` (bash wrappers), not the Tcl files directly. Check if synth.sh/pnr.sh import the Tcl scripts. If so, those bash wrappers need updating or removal too. Phase 15 will rewrite pnr skill -- for now, document that pnr is temporarily broken after CLN-01.

## Code Examples

### MCP Server entry point (index.ts)
```typescript
// mcp-server/index.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";

const server = new McpServer({
  name: "chipagent-backend",
  version: "0.1.0",
});

// ORFS candidate paths (same chain as detect-env.sh)
const ORFS_CANDIDATES = [
  process.env.ORFS_DIR,
  join(process.env.HOME ?? "", "OpenROAD-flow-scripts"),
  "/opt/OpenROAD-flow-scripts",
].filter(Boolean) as string[];

function findOrfs(): { path: string; flowPath: string } | null {
  for (const candidate of ORFS_CANDIDATES) {
    const flowPath = join(candidate, "flow");
    if (existsSync(join(flowPath, "Makefile"))) {
      return { path: candidate, flowPath };
    }
  }
  return null;
}

function findSky130hd(orfsFlowPath: string | null): { path: string; liberty: string } | null {
  const candidates = orfsFlowPath
    ? [join(orfsFlowPath, "platforms", "sky130hd")]
    : ORFS_CANDIDATES.map((c) => join(c, "flow", "platforms", "sky130hd"));
  for (const candidate of candidates) {
    if (existsSync(join(candidate, "lib", "sky130_fd_sc_hd__tt_025C_1v80.lib"))) {
      return {
        path: candidate,
        liberty: "lib/sky130_fd_sc_hd__tt_025C_1v80.lib",
      };
    }
  }
  return null;
}

function checkDocker(): { installed: boolean; version: string | null } {
  try {
    const version = execSync("docker --version 2>/dev/null", { encoding: "utf-8" }).trim();
    return { installed: true, version };
  } catch {
    return { installed: false, version: null };
  }
}

server.registerTool(
  "check_environment",
  {
    title: "Check Environment",
    description: "Verify ORFS installation, sky130hd PDK presence, and Docker availability",
    inputSchema: z.object({}),
  },
  async () => {
    const orfs = findOrfs();
    const sky130hd = findSky130hd(orfs?.flowPath ?? null);
    const docker = checkDocker();
    const result = {
      orfs: orfs ? { installed: true, ...orfs } : { installed: false, path: null, flowPath: null },
      sky130hd: sky130hd ? { installed: true, ...sky130hd } : { installed: false, path: null },
      docker,
      backend_mode: docker.installed ? "docker" : "local",
    };
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
```

### env.json schema (updated for sky130hd)
```json
{
  "detected_at": "2026-04-01T00:00:00Z",
  "tools": { "...existing tool entries..." },
  "pdk": {
    "sky130hd": {
      "installed": true,
      "path": "/home/user/OpenROAD-flow-scripts/flow/platforms/sky130hd",
      "liberty": "lib/sky130_fd_sc_hd__tt_025C_1v80.lib",
      "tech_lef": "lef/sky130_fd_sc_hd.tlef",
      "cell_lef": "lef/sky130_fd_sc_hd_merged.lef",
      "gds": "gds/sky130_fd_sc_hd.gds"
    }
  },
  "orfs": {
    "installed": true,
    "path": "/home/user/OpenROAD-flow-scripts",
    "flow_path": "/home/user/OpenROAD-flow-scripts/flow"
  },
  "docker": {
    "installed": false,
    "version": null
  },
  "backend_mode": "local",
  "capabilities": {
    "can_compile": true,
    "can_lint": true,
    "can_simulate": true,
    "can_synthesize": true,
    "can_pnr": true,
    "can_gds": true
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| nangate45 PDK | sky130hd PDK | v1.1.5 | Real silicon-targetable PDK |
| Standalone Tcl scripts (synth.tcl, pnr.tcl) | ORFS make flow via MCP | v1.1.5 | Industry-standard flow |
| Direct bash script invocation | MCP tool invocation | v1.1.5 | Claude Code native tool discovery |
| No Docker detection | Docker availability check | v1.1.5 | Pre-reserved for v1.2 Docker mode |

## Open Questions

1. **Should pnr skill be disabled after CLN-01?**
   - What we know: Removing synth.tcl/pnr.tcl will break the current pnr pipeline
   - What's unclear: Whether to leave synth.sh/pnr.sh as stubs or remove them too
   - Recommendation: Leave synth.sh/pnr.sh intact but have them exit with "migrating to ORFS" message. Phase 15 will rewrite the pnr skill.

2. **package.json placement for MCP server**
   - What we know: Root package.json is for the Claude Code plugin (npm install chip-agent)
   - Recommendation: Separate `mcp-server/package.json` for MCP dependencies. Keep root package.json unchanged.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Node.js built-in test runner + bash integration tests |
| Config file | none -- see Wave 0 |
| Quick run command | `node --experimental-strip-types --test mcp-server/test/*.ts` |
| Full suite command | `bash scripts/test-phase13.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MCP-01 | Server starts and responds to initialize | integration | `bash scripts/test-phase13.sh mcp-start` | -- Wave 0 |
| MCP-02 | check_environment returns structured JSON | integration | `bash scripts/test-phase13.sh check-env` | -- Wave 0 |
| ENV-01 | detect-env.sh finds sky130hd (not nangate45) | unit | `bash scripts/test-phase13.sh detect-sky130` | -- Wave 0 |
| ENV-02 | env.json contains backend_mode field | unit | `bash scripts/test-phase13.sh backend-mode` | -- Wave 0 |
| ENV-03 | env.json contains orfs path | unit | `bash scripts/test-phase13.sh orfs-path` | -- Wave 0 |
| CLN-01 | nangate45 scripts removed | smoke | `! test -f scripts/synth.tcl` | -- Wave 0 |
| CLN-02 | CLAUDE.md references sky130hd not nangate45 | smoke | `grep -q sky130hd CLAUDE.md && ! grep -q nangate45 CLAUDE.md` | -- Wave 0 |

### Sampling Rate
- **Per task commit:** `bash scripts/test-phase13.sh`
- **Per wave merge:** Full suite
- **Phase gate:** All tests green before verify

### Wave 0 Gaps
- [ ] `scripts/test-phase13.sh` -- integration test script
- [ ] `mcp-server/test/check-environment.test.ts` -- unit test for environment detection logic

## Sources

### Primary (HIGH confidence)
- [MCP TypeScript SDK server docs](https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/server.md) - Server setup, tool registration, stdio transport
- [Claude Code MCP docs](https://code.claude.com/docs/en/mcp) - .mcp.json format, project-scoped registration
- Local filesystem verification - sky130hd PDK at `~/OpenROAD-flow-scripts/flow/platforms/sky130hd/` confirmed

### Secondary (MEDIUM confidence)
- [@modelcontextprotocol/sdk on npm](https://www.npmjs.com/package/@modelcontextprotocol/sdk) - Package version confirmation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - MCP SDK version locked in project decisions; confirmed on npm
- Architecture: HIGH - stdio transport is the only option for Claude Code; pattern well-documented
- Pitfalls: HIGH - stdout corruption is well-known MCP issue; ESM extensions verified
- Environment: HIGH - sky130hd files confirmed on local disk

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (MCP SDK is stable)
