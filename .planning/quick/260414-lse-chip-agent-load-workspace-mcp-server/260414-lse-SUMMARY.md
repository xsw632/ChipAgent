# Quick Task: chip-agent:load_workspace Implementation

**Quick ID:** 260414-lse
**Date:** 2026-04-14
**Files changed:** 8 files

## Changes Made

### 1. `.mcp.json` — Fixed broken MCP server path
- Old (broken): `/home/mingzhenjia/.claude/plugins/chip-agent/mcp-server/index.ts` (path does not exist)
- New (correct): `/home/aa/snap/chipagent/chip/ChipAgent/mcp-server/index.ts` (exists)

### 2. `mcp-server/tools/check-environment.ts` — Docker mode support
- Added `readWorkspaceConfig()` helper: reads `~/.chipagent/workspace.json`
- Added `homedir` import from `node:os`
- In `registerCheckEnvironment()`: if `workspaceConfig.backend_mode === "docker"`:
  - Sets `orfs.installed = true` with container paths
  - Sets `sky130hd.installed = true` with container paths
  - Sets `backend_mode = "docker"`

### 3. `mcp-server/tools/run-stage.ts` — Docker execution + results mount
- Added `readWorkspaceConfig()`, `hostPath()`, `containerPath()`, `ensureDir()` helpers
- In Docker mode:
  - Mounts workspace at `/workspace` and ORFS flow directory at its container path
  - Pre-creates host-side `reports/`, `logs/`, `results/` directories so ORFS can write into them
  - Spawns: `docker run --rm -v <workspace>:/workspace -v <results>:<docker_workdir> -w <docker_workdir> openroad/orfs:latest make <stage> DESIGN_CONFIG=/workspace/...`
  - Uses `hostLogPath` pointing to mounted results directory
- In local mode: unchanged existing `spawn("make", ...)` behavior

### 4. `mcp-server/tools/get-report.ts` — Docker results reading
- Added `readWorkspaceConfig()` helper
- In Docker mode: reads reports from `<docker_results_dir>/OpenROAD-flow-scripts/flow/reports/...`
- In local mode: unchanged existing behavior

### 5. `mcp-server/tools/clean-design.ts` — Docker clean support
- Added `readWorkspaceConfig()` helper
- In Docker mode: spawns `docker run --rm -v <workspace>:/workspace ... make clean_all`
- In local mode: unchanged existing behavior

### 6. `~/.chipagent/workspace.json` — Written
```json
{
  "workspace_dir": "/home/aa/snap/chipagent/chip/ChipAgent",
  "mcp_server_path": "/home/aa/snap/chipagent/chip/ChipAgent/mcp-server/index.ts",
  "backend_mode": "docker",
  "docker_image": "openroad/orfs:latest",
  "docker_volumes": ["/home/aa/snap/chipagent/chip/ChipAgent:/workspace"],
  "docker_workdir": "/OpenROAD-flow-scripts/flow",
  "orfs_flow_path": "/OpenROAD-flow-scripts/flow",
  "docker_results_dir": "/home/aa/snap/chipagent/chip/ChipAgent"
}
```

### 7. `skills/load_workspace/SKILL.md` — New skill created
- `/chip-agent:load_workspace` command definition
- Reads or runs `detect-env.sh`
- Fixes `.mcp.json` path if incorrect
- Writes `~/.chipagent/workspace.json`
- Documents MCP tool behavior in Docker vs local mode

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Mount workspace + ORFS results separately | ORFS expects to write to its own directory structure; mounting the whole workspace at `/workspace` lets ORFS read Verilog/config files while the results dir mount ensures host-readable output |
| Pre-create results directories | ORFS won't create parent directories on the host mount; `ensureDir()` creates them before docker run |
| MCP tools read workspace.json on every call | Stateless design — no in-memory state; each tool independently reads config |

## Verification

```
✓ .mcp.json path corrected
✓ MCP server file exists at new path
✓ workspace.json written with backend_mode=docker
✓ check-environment.ts: homedir import + workspace.json read
✓ run-stage.ts: docker volumes + ensureDir
✓ get-report.ts: docker_results_dir path
✓ clean-design.ts: docker spawn
✓ skills/load_workspace/SKILL.md created
```

## Next Steps

1. Restart Claude Code (exit + restart) for `.mcp.json` changes to take effect
2. Run `claude mcp list` to verify `chipagent-backend` shows as connected
3. Run `/chip-agent:load_workspace` to confirm workspace configuration
4. Run `/chip-agent:pnr ALU8` to test the full Docker PnR flow
