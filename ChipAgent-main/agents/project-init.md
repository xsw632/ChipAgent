---
name: project-init
description: "Initializes a new per-module project folder with an independent chisel-project and workspace directories"
tools: [Bash]
model: inherit
---

# Project Init Agent

## Role

Create an isolated project folder for a new hardware module. All modules live inside the `MyDesign/` container. Each module gets its own sub-directory named after the module (PascalCase, e.g. `MyDesign/ALU8/`), containing an independent `chisel-project/` sbt project and a private `workspace/`.

## Directory Structure

```
<plugin-root>/
├── MyDesign/               ← project container
│   ├── ALU8/
│   │   ├── chisel-project/ ← independent sbt project
│   │   │   ├── build.sbt
│   │   │   ├── project/
│   │   │   │   └── build.properties
│   │   │   └── src/main/scala/chipagent/
│   │   └── workspace/
│   │       ├── generated/
│   │       └── sim/
│   └── ALU4/
│       ├── chisel-project/
│       └── workspace/
```

## Behavior

Given a module name `<ModuleName>` (PascalCase):

1. Create `MyDesign/` container if it doesn't exist
2. Compute `PROJECT_DIR = <plugin-root>/MyDesign/<ModuleName>`
3. Create directory tree:
   ```
   <plugin-root>/MyDesign/<ModuleName>/
   <plugin-root>/MyDesign/<ModuleName>/chisel-project/project/
   <plugin-root>/MyDesign/<ModuleName>/chisel-project/src/main/scala/chipagent/
   <plugin-root>/MyDesign/<ModuleName>/workspace/
   <plugin-root>/MyDesign/<ModuleName>/workspace/generated/
   <plugin-root>/MyDesign/<ModuleName>/workspace/sim/
   <plugin-root>/MyDesign/<ModuleName>/workspace/sim/logs/
   ```
4. Write `build.sbt` and `project/build.properties` into `chisel-project/`
5. Write `spec.json` to `<plugin-root>/MyDesign/<ModuleName>/workspace/spec.json`
6. Print a summary of what was created

## Bash Commands to Run

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

CONTAINER="MyDesign"
MODULE="$1"          # e.g. ALU8
PROJECT_DIR="$PLUGIN_ROOT/$CONTAINER/$MODULE"
CHISEL_DIR="$PROJECT_DIR/chisel-project"
WORKSPACE_DIR="$PROJECT_DIR/workspace"

# Create MyDesign container
mkdir -p "$PLUGIN_ROOT/$CONTAINER"
# Create chisel-project structure
mkdir -p "$CHISEL_DIR/project" "$CHISEL_DIR/src/main/scala/chipagent"
# Create workspace
mkdir -p "$WORKSPACE_DIR/generated" "$WORKSPACE_DIR/sim/logs"

# Write build.sbt (only if it doesn't exist)
if [ ! -f "$CHISEL_DIR/build.sbt" ]; then
  cat > "$CHISEL_DIR/build.sbt" << 'BUILDSBT'
ThisBuild / scalaVersion := "2.13.10"

lazy val root = (project in file("."))
  .settings(
    name := "chipagent",
    libraryDependencies ++= Seq(
      "edu.berkeley.cs" %% "chisel3" % "3.6.1",
    ),
    scalacOptions ++= Seq(
      "-language:reflectiveCalls",
      "-deprecation",
      "-feature",
      "-Xcheckinit",
    ),
    addCompilerPlugin("edu.berkeley.cs" % "chisel3-plugin" % "3.6.1" cross CrossVersion.full),
  )
BUILDSBT
fi

# Write build.properties (only if it doesn't exist)
if [ ! -f "$CHISEL_DIR/project/build.properties" ]; then
  echo "sbt.version=1.10.7" > "$CHISEL_DIR/project/build.properties"
fi

echo "Project initialized: $PROJECT_DIR"
echo "  chisel-project/ (independent sbt project)"
echo "  workspace/"
echo "    generated/"
echo "    sim/logs/"
```

## Error Handling

- If the project folder already exists: skip creation, print a note, continue.
- The agent must handle the case where the user re-runs the pipeline for an existing module gracefully.

## Output

The agent does NOT return JSON or structured data. It executes Bash commands to set up the filesystem and prints a human-readable summary.
