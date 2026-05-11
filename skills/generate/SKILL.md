---
name: generate
description: Turn a natural language hardware description into Chisel source files. Parses requirements, confirms spec, and generates Scala code (no compile/lint/sim).
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# chip-agent:generate

Turn a natural language hardware description into Chisel source files.

Given a plain-English description of a digital hardware module, this command parses the requirements, confirms the spec, and generates Chisel Scala source code. It does NOT compile, lint, or simulate -- use `/chip-agent:workflow` for the full pipeline.

## Usage

```
/chip-agent:generate <hardware description>
```

**Example:**

```
/chip-agent:generate An 8-bit ALU that supports ADD, SUB, AND, OR, XOR, and SLT operations with a zero flag output
```

## Instructions

**Determine the project root directory** by finding the nearest ancestor directory of this skill file that contains `.claude`. Use that directory as the base for all relative paths below.

## Pipeline

### Step 0 -- Initialize Project Folder

After the module name is determined from the spec (Step 1), run the project-init subagent to set up the per-module project structure inside the `MyDesign/` container.

**Bash commands to execute:**

```bash
PROJECT_ROOT="<project-root>"   # e.g. /home/aa/snap/ChipAgent-main
CONTAINER="MyDesign"          # all projects live inside this folder
MODULE="<ModuleName>"         # e.g. ALU8
PROJECT_DIR="$PROJECT_ROOT/$CONTAINER/$MODULE"
WORKSPACE_DIR="$PROJECT_DIR/workspace"

# Create MyDesign container if it doesn't exist
mkdir -p "$PROJECT_ROOT/$CONTAINER"
# Create project folder and workspace
mkdir -p "$WORKSPACE_DIR/generated" "$WORKSPACE_DIR/sim/logs"
# Symlink chisel-project (three levels up from MyDesign/<Module>/)
rm -f "$PROJECT_DIR/chisel-project"
ln -s "../../chisel-project" "$PROJECT_DIR/chisel-project"

echo "Project initialized: $PROJECT_DIR"
```

**Project folder structure:**
```
<project-root>/
├── chisel-project/              ← shared, all module source lives here
├── MyDesign/                   ← project container
│   ├── ALU8/
│   │   ├── chisel-project/   ← symlink → ../../chisel-project
│   │   └── workspace/
│   │       ├── generated/
│   │       ├── sim/
│   │       └── spec.json
│   ├── ALU4/
│   │   ├── chisel-project/   ← symlink → ../../chisel-project
│   │   └── workspace/
│   └── PriorityEncoder4/
│       ├── chisel-project/
│       └── workspace/
```

If the project folder already exists inside `MyDesign/`, skip creation and continue.

### Step 1 -- Parse Requirements

Read the requirement-parser agent definition at `agents/requirement-parser.md` (relative to project root) and follow its rules to extract a structured JSON spec from the user's hardware description (`$ARGUMENTS`).

The agent returns a JSON object. For simple designs: `moduleName`, `type: "simple"`, `ports`, `operations`, `flags`, and `constraints`. For complex designs: `moduleName`, `type: "complex"`, `modules[]`, and `topModule`.

**Validation:** Verify the JSON is valid -- `moduleName` is PascalCase, all ports have direction/type/width, operations have opcodes. For complex specs, verify that `topModule.submodules` matches the names in `modules[]`. If the JSON is malformed, retry the parser once.

**Step 0 MUST run first** to create the project folder before writing spec.json.

**Write spec to disk** using the Write tool:
```
MyDesign/<ModuleName>/workspace/spec.json
```

The requirement-parser agent returns JSON to conversation only -- it does NOT write files. This step MUST capture the JSON and write it to disk so that all downstream steps can read it.

### Step 1.5 -- Confirm Spec with User

Before generating code, present the parsed spec to the user for approval.

**Format the spec preview:**
- Show the module name and description
- For **simple** specs: list all ports (name, direction, type, width) and operations
- For **complex** specs: list each sub-module with its ports, then show the top-level wiring summary
- Use a readable table or bulleted format, not raw JSON

**Ask for confirmation** using `AskUserQuestion` with these options:
1. **"Approve and generate"** -- proceed to Step 2 as-is
2. **"Modify ports or operations"** -- user provides feedback; re-run the requirement-parser agent with the original description plus the user's feedback appended, then re-present the updated spec (loop back to Step 1.5)
3. **"Simplify design"** -- for complex specs, user wants fewer modules; re-run parser with a simplification hint
4. **"Start over"** -- user wants to re-describe; ask for new input and go back to Step 1

Only proceed to Step 2 after the user selects "Approve and generate".

### Step 2 -- Generate Chisel

Read the chisel-generator agent definition at `agents/chisel-generator.md` (relative to project root) and follow its rules with the JSON spec to produce Chisel source files. There is no `/chip-agent:chisel-generate` sub-skill -- this step calls the agent directly (inline).

**For simple specs (type: "simple"):**

The agent writes two files:
1. The module Scala file: `MyDesign/<ModuleName>/chisel-project/src/main/scala/chipagent/<ModuleName>.scala`
2. An updated `Generate.scala` with the new module in the match statement

**For complex specs (type: "complex"):**

The agent writes N+1 files:
1. One Scala file per sub-module: `MyDesign/<ModuleName>/chisel-project/src/main/scala/chipagent/<SubModuleName>.scala` for each entry in `modules[]`
2. The top-level module: `MyDesign/<ModuleName>/chisel-project/src/main/scala/chipagent/<TopModuleName>.scala` that instantiates and wires all sub-modules
3. An updated `Generate.scala` with the top module name (the top module pulls in sub-modules automatically)

## Pipeline Stages

| # | Stage              | Description                                      |
|---|--------------------|--------------------------------------------------|
| 0  | Initialize Project | Create per-module folder with symlink + workspace |
| 1  | Parse Requirements | Extract module name, ports, operations from NL    |
| 1.5| Confirm Spec       | Present parsed spec for user approval             |
| 2  | Generate Chisel    | Produce Chisel source from structured spec        |

## Input

$ARGUMENTS

A natural language description of a digital hardware module. The description should include:

- Module name or purpose
- Input and output ports with bit widths
- Functional behavior (operations, logic, state machines)
- Any constraints or special requirements

## Output

Upon completion, the following artifacts are produced in `MyDesign/<ModuleName>/`:

- `workspace/spec.json` -- structured JSON specification
- `chisel-project/src/main/scala/chipagent/<ModuleName>.scala` -- Chisel source file(s)
- `chisel-project/src/main/scala/chipagent/Generate.scala` -- updated with new module entry
