---
name: load_workspace
description: "Detect local environment and configure MCP server for PnR. Fixes broken paths, detects backend mode (local/docker), and writes workspace configuration."
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# chip-agent:load_workspace

Detect local environment and configure the ChipAgent MCP server so that `/chip-agent:pnr` can run successfully. This command handles three cases:
- **Docker backend**: ORFS runs inside `openroad/orfs:latest` Docker container
- **Local backend**: ORFS is installed on the local filesystem
- **First run**: `.chipagent/env.json` does not exist yet

## Usage

```
/chip-agent:load_workspace
```

## Instructions

### Step 1 -- Find Plugin Root

Find the nearest ancestor directory containing `.claude-plugin/plugin.json`. Use that as `PLUGIN_ROOT`.

### Step 2 -- Read or Detect Environment

Read `PLUGIN_ROOT/.chipagent/env.json`.

**If the file does not exist or `backend_mode` is missing:**
Run `<PLUGIN_ROOT>/scripts/detect-env.sh` via Bash and read the output to confirm backend_mode.

**If the file exists and has `backend_mode`:**
Skip detection — use existing values.

### Step 3 -- Determine Workspace Root

The workspace root is the same as `PLUGIN_ROOT` for this project:
`/home/aa/snap/chipagent/chip/ChipAgent`

### Step 4 -- Verify or Fix `.mcp.json` MCP Server Path

Read `PLUGIN_ROOT/.mcp.json`.

Check if the `args[1]` path (MCP server entry point) points to a file that **actually exists on disk**.

**If the path does NOT exist** (e.g., `/home/mingzhenjia/...`):
Replace it with `<PLUGIN_ROOT>/mcp-server/index.ts`.
Write the updated JSON back to `PLUGIN_ROOT/.mcp.json`.

**If the path already exists**:
Do not modify `.mcp.json`.

After fixing, display:
```
MCP server path updated.
Restart Claude Code for changes to take effect:
  1. Exit this session (Ctrl+C or /exit)
  2. Start a new Claude Code session
  3. Run: claude mcp list
  4. Verify chipagent-backend shows as connected (not "Failed to connect")
```

### Step 5 -- Write or Update `~/.chipagent/workspace.json`

Read `PLUGIN_ROOT/.chipagent/env.json` for `backend_mode`.

**For `backend_mode = docker`:**
Write `~/.chipagent/workspace.json` with these fields:
```json
{
  "workspace_dir": "<PLUGIN_ROOT>",
  "mcp_server_path": "<PLUGIN_ROOT>/mcp-server/index.ts",
  "backend_mode": "docker",
  "docker_image": "openroad/orfs:latest",
  "docker_volumes": ["<PLUGIN_ROOT>:/workspace"],
  "docker_workdir": "/OpenROAD-flow-scripts/flow",
  "orfs_flow_path": "/OpenROAD-flow-scripts/flow",
  "docker_results_dir": "<PLUGIN_ROOT>"
}
```

**For `backend_mode = local`:**
Write `~/.chipagent/workspace.json` with:
```json
{
  "workspace_dir": "<PLUGIN_ROOT>",
  "mcp_server_path": "<PLUGIN_ROOT>/mcp-server/index.ts",
  "backend_mode": "local",
  "docker_volumes": [],
  "docker_workdir": "",
  "orfs_flow_path": "<from env.json orfs.flow_path>"
}
```

Use `echo $HOME` via Bash to resolve `~` to the absolute home directory path, then write the file with the Write tool to `<home>/.chipagent/workspace.json`.

### Step 6 -- Summary

Present a summary:
```
=== chip-agent:load_workspace ===
Backend mode: <backend_mode>
ORFS: <docker image or orfs_flow_path>
Workspace: <workspace_dir>
MCP server: <mcp_server_path>
workspace.json: <home>/.chipagent/workspace.json
MCP tools updated: check_environment, run_stage, get_report, clean_design
```

## What the MCP Tools Do After This Command

| Tool | Docker Mode Behavior | Local Mode Behavior |
|------|---------------------|---------------------|
| `check_environment` | Reports ORFS/sky130hd as installed from container paths | Uses filesystem detection (existing logic) |
| `run_stage` | Spawns `docker run -v ... openroad/orfs:latest make <stage>` | Spawns `make <stage>` directly |
| `get_report` | Reads reports from `<workspace>/OpenROAD-flow-scripts/flow/reports/...` | Reads from `<orfs_flow_path>/reports/...` |
| `clean_design` | Spawns `docker run ... make clean_all` | Spawns `make clean_all` directly |

## Docker Volume Mounts

In Docker mode, the workspace is mounted at `/workspace` inside the container.
ORFS results directories (`results/`, `reports/`, `logs/`) are mounted from:
`<workspace_dir>/OpenROAD-flow-scripts/flow/` → `/OpenROAD-flow-scripts/flow/` (container)

This ensures ORFS outputs are accessible on the host after the container exits.
