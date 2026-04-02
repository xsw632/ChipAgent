---
phase: 13-mcp-server-environment-foundation
plan: 01
subsystem: infra
tags: [mcp, typescript, stdio, environment-detection, sky130hd, orfs, docker]

requires: []
provides:
  - "MCP server with stdio transport registered via .mcp.json"
  - "check_environment tool reporting ORFS/sky130hd/Docker status"
  - "MCP tool registration pattern (registerXxx function)"
affects: [14-mcp-synthesis-pnr-tools, 15-mcp-report-gds-tools]

tech-stack:
  added: ["@modelcontextprotocol/sdk 1.29.0", "zod 4.3.6", "node --experimental-strip-types"]
  patterns: ["MCP tool as exported register function", "stdio transport with .mcp.json discovery"]

key-files:
  created: ["mcp-server/index.ts", "mcp-server/tools/check-environment.ts", "mcp-server/package.json", ".mcp.json"]
  modified: []

key-decisions:
  - "Used zod ^4.0 instead of 3.25.0 due to zod 3.25 missing dist artifacts"
  - "Used .ts import extensions (not .js) for node --experimental-strip-types compatibility"

patterns-established:
  - "MCP tool pattern: export registerXxx(server) function per tool file"
  - "Environment detection: cascading path search with filesystem verification"

requirements-completed: [MCP-01, MCP-02]

duration: 4min
completed: 2026-04-02
---

# Phase 13 Plan 01: MCP Server + Environment Foundation Summary

**TypeScript MCP server with stdio transport, .mcp.json auto-discovery, and check_environment tool detecting ORFS/sky130hd/Docker**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-02T02:43:22Z
- **Completed:** 2026-04-02T02:47:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- MCP server starts via stdio and responds to JSON-RPC initialize handshake
- Claude Code discovers chipagent-backend through .mcp.json registration
- check_environment tool returns structured JSON with orfs, sky130hd, docker, and backend_mode fields
- Environment correctly detects local ORFS installation and sky130hd PDK

## Task Commits

Each task was committed atomically:

1. **Task 1+2: MCP server scaffold + check_environment tool** - `f7833ea` (feat)

**Plan metadata:** pending

## Files Created/Modified
- `mcp-server/index.ts` - MCP server entry point with McpServer + StdioServerTransport
- `mcp-server/tools/check-environment.ts` - check_environment tool with ORFS/sky130hd/Docker detection
- `mcp-server/package.json` - Dependencies: @modelcontextprotocol/sdk, zod
- `mcp-server/tsconfig.json` - Type-checking config (noEmit, NodeNext module)
- `.mcp.json` - Project-scoped MCP server registration for Claude Code

## Decisions Made
- Used zod ^4.0 (resolved to 4.3.6) instead of planned 3.25.0 because zod 3.25 ships without dist/ artifacts, causing ESM import failures
- Used .ts import extensions in index.ts instead of .js because Node v24 --experimental-strip-types resolves .ts directly

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Zod 3.25.0 missing dist artifacts**
- **Found during:** Task 1 (MCP server scaffold)
- **Issue:** zod 3.25.0 ships only src/ directory, no dist/esm/ -- ESM imports fail at runtime
- **Fix:** Changed dependency to "^3.25 || ^4.0" matching MCP SDK peer dep, resolves to zod 4.3.6
- **Files modified:** mcp-server/package.json
- **Verification:** Server starts and responds to initialize
- **Committed in:** f7833ea

**2. [Rule 3 - Blocking] .js import extension incompatible with --experimental-strip-types**
- **Found during:** Task 1 (MCP server scaffold)
- **Issue:** Plan specified .js extension for local TS imports, but Node v24 strip-types doesn't rewrite extensions
- **Fix:** Changed to .ts extension in import statement
- **Files modified:** mcp-server/index.ts
- **Verification:** Server starts without ERR_MODULE_NOT_FOUND
- **Committed in:** f7833ea

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes necessary for runtime correctness. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- MCP server foundation ready for Phase 14 synthesis/PnR tool registration
- Tool registration pattern established: export registerXxx function, import in index.ts
- Environment detection confirms ORFS + sky130hd available locally

---
*Phase: 13-mcp-server-environment-foundation*
*Completed: 2026-04-02*
