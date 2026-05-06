---
name: project-init
description: "Initializes a new per-module project folder with workspace directories"
tools: [Bash]
model: inherit
---

# Project Init Agent

Create an isolated project folder for a new hardware module inside `MyDesign/`.

## Bash Commands to Run

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
MODULE="$1"
WORKSPACE_DIR="$PLUGIN_ROOT/MyDesign/$MODULE/workspace"

mkdir -p "$WORKSPACE_DIR/generated" "$WORKSPACE_DIR/sim/logs"
echo "Project initialized: $WORKSPACE_DIR"
```

## Note

- The `chisel-project/` directory is auto-initialized by `compile.sh` on first run.
- No manual symlink creation needed.
- If the project folder already exists, skip creation and continue.

## Output

Prints a human-readable summary of what was created.