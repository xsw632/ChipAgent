---
name: project-init
description: "Initializes a new per-module project folder with symlinks and workspace directories"
tools: [Bash]
model: inherit
---

# Project Init Agent

## Role

Create an isolated project folder for a new hardware module. All modules live inside the `MyDesign/` container. Each module gets its own sub-directory named after the module (PascalCase, e.g. `MyDesign/ALU8/`), containing a symlink to `../../chisel-project` and a private `workspace/`.

## Directory Structure

```
<plugin-root>/
├── chisel-project/          ← shared, all modules' Scala source live here
├── MyDesign/               ← project container
│   ├── ALU8/
│   │   ├── chisel-project/ ← symlink → ../../chisel-project
│   │   └── workspace/
│   │       ├── generated/
│   │       └── sim/
│   └── ALU4/
│       ├── chisel-project/ ← symlink → ../../chisel-project
│       └── workspace/
```

## Behavior

Given a module name `<ModuleName>` (PascalCase):

1. Create `MyDesign/` container if it doesn't exist
2. Compute `PROJECT_DIR = <plugin-root>/MyDesign/<ModuleName>`
3. Create directory tree:
   ```
   <plugin-root>/MyDesign/<ModuleName>/
   <plugin-root>/MyDesign/<ModuleName>/workspace/
   <plugin-root>/MyDesign/<ModuleName>/workspace/generated/
   <plugin-root>/MyDesign/<ModuleName>/workspace/sim/
   <plugin-root>/MyDesign/<ModuleName>/workspace/sim/logs/
   ```
4. Create symlink `<plugin-root>/MyDesign/<ModuleName>/chisel-project` → `../../chisel-project`
5. Write `spec.json` to `<plugin-root>/MyDesign/<ModuleName>/workspace/spec.json`
6. Print a summary of what was created

## Bash Commands to Run

```bash
# Determine plugin root
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

CONTAINER="MyDesign"
MODULE="$1"          # e.g. ALU8
PROJECT_DIR="$PLUGIN_ROOT/$CONTAINER/$MODULE"
WORKSPACE_DIR="$PROJECT_DIR/workspace"

# Create MyDesign container
mkdir -p "$PLUGIN_ROOT/$CONTAINER"
# Create project folder and workspace
mkdir -p "$WORKSPACE_DIR/generated" "$WORKSPACE_DIR/sim/logs"
# Create symlink (three levels up: MyDesign/<Module>/chisel-project -> ../../chisel-project)
rm -f "$PROJECT_DIR/chisel-project"
ln -s "../../chisel-project" "$PROJECT_DIR/chisel-project"

echo "Project initialized: $PROJECT_DIR"
echo "  chisel-project/ -> ../../chisel-project (symlink)"
echo "  workspace/"
echo "    generated/"
echo "    sim/logs/"
```

## Error Handling

- If the project folder already exists: skip creation, print a note, continue.
- If symlink creation fails (e.g., on Windows without admin): fall back to copying the directory.
- The agent must handle the case where the user re-runs the pipeline for an existing module gracefully.

## Output

The agent does NOT return JSON or structured data. It executes Bash commands to set up the filesystem and prints a human-readable summary.
