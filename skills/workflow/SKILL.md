---
name: workflow
description: "Full auto-toolchain: parse, generate Chisel, compile, lint, testbench, simulate, report."
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# chip-agent:workflow

Full auto-toolchain pipeline: turn a natural language hardware description into simulation-verified Verilog.

Given a plain-English description of a digital hardware module, this command orchestrates a multi-stage pipeline that produces lint-clean, simulation-verified Verilog output.

Create the checklist and go on.
```
□ Initialize Project structure
□ Parse Requirements
□ Confirm Spec
□ Generate Chisel code
□ Compile to Verilog
□ Lint verification
□ Generate testbench
□ Run simulation
□ Generate verification report
```

## Usage

```
/chip-agent:workflow <hardware description>
```

**Example:**

```
/chip-agent:workflow An 8-bit ALU that supports ADD, SUB, AND, OR, XOR, and SLT operations with a zero flag output
```

## Instructions

**Determine the project root directory** by finding the nearest ancestor directory '.claude'. Use that directory as the base for all relative paths below.

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
# Symlink chisel-project (two levels up from MyDesign/<Module>/)
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

If the project folder already exists, skip creation and continue.

### Step 1 -- Parse Requirements

Read the requirement-parser agent definition at `agents/requirement-parser.md` (relative to project root) and follow its rules to extract a structured JSON spec from the user's hardware description (`$ARGUMENTS`).Run the agentto return the json spec.

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

Read the chisel-generator agent definition at `agents/chisel-generator.md` (relative to project root) and follow its rules with the JSON spec to produce Chisel source files. Run the agent to generate the Chisel source code.

**For simple specs (type: "simple"):**

The agent writes two files:
1. The module Scala file: `MyDesign/<ModuleName>/chisel-project/src/main/scala/chipagent/<ModuleName>.scala`
2. An updated `Generate.scala` with the new module in the match statement

**For complex specs (type: "complex"):**

The agent writes N+1 files:
1. One Scala file per sub-module: `MyDesign/<ModuleName>/chisel-project/src/main/scala/chipagent/<SubModuleName>.scala` for each entry in `modules[]`
2. The top-level module: `MyDesign/<ModuleName>/chisel-project/src/main/scala/chipagent/<TopModuleName>.scala` that instantiates and wires all sub-modules
3. An updated `Generate.scala` with the top module name (the top module pulls in sub-modules automatically)

### Step 3 -- Compile

Read and correct the Generate.scala in chisel-project first to generate your own module,then run the compilation script EXPLICITLY with the module name:

```
<project-root>/scripts/compile.sh <ModuleName>
```

The compile script resolves paths as:
- `PROJECT_DIR = <project-root>/MyDesign/<ModuleName>/chisel-project`
- `OUTPUT_DIR  = <project-root>/MyDesign/<ModuleName>/workspace/generated`

Do NOT rely on the PostToolUse hook for compilation. The orchestrator calls compile.sh directly.

If compilation fails:
1. Read the error output from the build log
2. Follow the chisel-generator agent rules (`agents/chisel-generator.md`) to fix the issues in the generated Scala files
3. Re-run `<project-root>/scripts/compile.sh <ModuleName>` after fixing
4. Maximum 3 fix attempts. After 3 failures, stop and report the errors to the user:
   ```
   COMPILE AUTO-FIX FAILED after 3 attempts.
   Remaining errors:
   <paste compile error output>
   ```

### Step 4 -- Lint

Run Verilator lint on the generated Verilog with the module name:

```
<project-root>/scripts/lint.sh <ModuleName>
```

If lint passes (exit 0), continue to Step 5.

If lint fails (non-zero exit):
1. Read the error output carefully -- these are Verilog-level errors caused by Chisel source issues
2. Identify the Chisel source issue that caused the Verilog lint error
3. Follow the chisel-generator agent rules (`agents/chisel-generator.md`) to fix the Chisel source (NOT the generated Verilog -- never edit generated files)
3. Re-run `<project-root>/scripts/compile.sh <ModuleName>` after fixing
5. Re-run `<project-root>/scripts/lint.sh <ModuleName>` after compile succeeds
6. Repeat up to 3 total lint attempts

If lint still fails after 3 attempts, STOP the pipeline and report:
```
LINT AUTO-FIX FAILED after 3 attempts.
Remaining errors:
<paste lint error output>
```

After lint passes, check `MyDesign/<ModuleName>/workspace/generated/lint-warnings.log`. If non-empty, note the warnings:
```
Lint passed with N warnings (suppressed/non-blocking):
<paste warning summary>
```

### Step 5 -- Generate Testbench

Read the testbench-generator agent definition at `agents/testbench-generator.md` (relative to project root). Run the agent to generate the testbench.

### Step 6 -- Simulate

Run the simulation script with the module name:

```
<project-root>/scripts/simulate.sh <ModuleName>
```

If simulation fails (non-zero exit):
1. Read `MyDesign/<ModuleName>/workspace/sim/logs/sim_result.log` for failure details
2. Attempt to fix the testbench (NOT the Verilog -- never edit generated files) by regenerating `MyDesign/<ModuleName>/workspace/sim/tb_<ModuleName>.cpp` with corrected test vectors
2. Re-run `<project-root>/scripts/simulate.sh <ModuleName>` after fixing
4. Maximum 3 simulation fix attempts. After 3 failures, STOP the pipeline and report:
   ```
   SIM AUTO-FIX FAILED after 3 attempts.
   Remaining failures:
   <paste sim_result.log content>
   ```

On success, proceed to Step 7.

### Step 7 -- Report

Format the simulation results into a verification report:

1. Read `MyDesign/<ModuleName>/workspace/sim/logs/sim_result.log`
2. Count PASS/FAIL lines
3. If lint warnings exist (from `MyDesign/<ModuleName>/workspace/generated/lint-warnings.log`), include them
4. Present formatted output:
   ```
   === Verification Report: <ModuleName> ===
   Verilog: MyDesign/<ModuleName>/workspace/generated/<ModuleName>.v
   Testbench: MyDesign/<ModuleName>/workspace/sim/tb_<ModuleName>.cpp

   Simulation: PASSED X/Y tests
   [per-test results from sim_result.log]

   Lint: PASSED (N warnings suppressed)
   [warning details if any]
   ```

## Pipeline Stages

| # | Stage               | Description                                      |
|---|---------------------|--------------------------------------------------|
| 0  | Initialize Project  | Create per-module folder with symlink + workspace |
| 1  | Parse Requirements  | Extract module name, ports, operations from NL    |
| 1.5| Confirm Spec        | Present parsed spec for user approval             |
| 2  | Generate Chisel     | Produce Chisel source from structured spec        |
| 3  | Compile to Verilog  | sbt compiles Chisel to SystemVerilog via firtool  |
| 4  | Lint                | Verilator lint-only check on generated Verilog    |
| 5  | Generate Testbench  | Create C++ testbench for Verilator simulation     |
| 6  | Simulate            | Run Verilator simulation and collect results      |
| 7  | Report              | Format test results into verification report      |

## Input

$ARGUMENTS

A natural language description of a digital hardware module. The description should include:

- Module name or purpose
- Input and output ports with bit widths
- Functional behavior (operations, logic, state machines)
- Any constraints or special requirements

## Output

Upon pipeline completion, the following artifacts are produced in `MyDesign/<ModuleName>/`:

- `workspace/spec.json` -- structured JSON specification
- `workspace/generated/<ModuleName>.v` -- synthesizable Verilog
- `workspace/generated/<ModuleName>.sv` -- SystemVerilog variant (when firtool is available)
- `workspace/generated/lint-warnings.log` -- any remaining Verilator warnings with explanations
- `workspace/sim/tb_<ModuleName>.cpp` -- C++ Verilator testbench
- `workspace/sim/logs/sim_result.log` -- simulation test report
