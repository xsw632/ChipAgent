---
name: chipyard
description: "Unified Chipyard flow: automatically routes to local or Docker workflow based on backend_mode setting."
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# chip-agent:chipyard

**Unified entry point.** Routes to the appropriate workflow based on `.chipagent/env.json` configuration.

## Mode Detection

```bash
PROJECT_ROOT="<project-root>"
BACKEND_MODE=$(grep -o '"backend_mode": *"[^"]*"' "$PROJECT_ROOT/.chipagent/env.json" | cut -d'"' -f4)
```

If `backend_mode` is missing or empty:

1. **Run `/chip-agent:initialize`** to detect installed tools and determine best backend mode
   - This skill scans for local installations (Chipyard, ORFS, Java, sbt)
   - It also checks if Docker is available
   - Based on findings, it writes the optimal `backend_mode` to `.chipagent/env.json`

2. **Re-read backend_mode** after initialization completes:
   ```bash
   BACKEND_MODE=$(grep -o '"backend_mode": *"[^"]*"' "$PROJECT_ROOT/.chipagent/env.json" | cut -d'"' -f4)
   ```

3. **Continue with routing** using the newly detected backend_mode

If still empty after initialization, default to `local`.

## Routing

| backend_mode | Skill to read | Description |
|-------------|---------------|-------------|
| `local` | `skills/chipyard-local/SKILL.md` | Local Chipyard installation via MCP tools |
| `docker` | `skills/chipyard-docker/SKILL.md` | Docker containers (`ictmrc/chipyard-image:1.9.1-ubuntu-22.04`) |

**Execution:** In the source repository, read the skill path above. In an installed project, read the sibling command `<name>.md` from the same command directory as this file, then follow its pipeline.

## Configuration

Use either local or Docker MCP servers:
- Local: `mcp__chipagent-backend__*` tools → run Chipyard locally
- Docker: `mcp__chipagent-backend-docker__*` tools → run Chipyard in Docker containers

Then invoke this skill again.
