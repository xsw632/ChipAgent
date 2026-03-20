---
name: generate
description: Turn a natural language hardware description into simulation-verified Verilog. Orchestrates the full pipeline: parse, generate, compile, lint, testbench, simulate, report.
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

Turn a natural language hardware description into simulation-verified Verilog.

Given a plain-English description of a digital hardware module, this command orchestrates a multi-stage pipeline that produces lint-clean, simulation-verified SystemVerilog output.

## Usage

```
/chip-agent:generate <hardware description>
```

**Example:**

```
/chip-agent:generate An 8-bit ALU that supports ADD, SUB, AND, OR, XOR, and SLT operations with a zero flag output
```

## Instructions

**Determine the plugin root directory** by finding the nearest ancestor directory of this skill file that contains `.claude-plugin/plugin.json`. Use that directory as the base for all relative paths below.

## Pipeline

### Step 1 -- Parse Requirements

Read the requirement-parser agent definition at `agents/requirement-parser.md` (relative to plugin root) and follow its rules to extract a structured JSON spec from the user's hardware description (`$ARGUMENTS`).

The agent returns a JSON object. For simple designs: `moduleName`, `type: "simple"`, `ports`, `operations`, `flags`, and `constraints`. For complex designs: `moduleName`, `type: "complex"`, `modules[]`, and `topModule`.

**Validation:** Verify the JSON is valid -- `moduleName` is PascalCase, all ports have direction/type/width, operations have opcodes. For complex specs, verify that `topModule.submodules` matches the names in `modules[]`. If the JSON is malformed, retry the parser once.

**Create workspace directory** after parsing succeeds:
```
mkdir -p workspace/<ModuleName>/generated workspace/<ModuleName>/sim/logs
```

**Write spec to disk** using the Write tool:
```
workspace/<ModuleName>/spec.json
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

Read the chisel-generator agent definition at `agents/chisel-generator.md` (relative to plugin root) and follow its rules with the JSON spec to produce Chisel source files. There is no `/chip-agent:chisel-generate` sub-skill -- this step calls the agent directly (inline).

**For simple specs (type: "simple"):**

The agent writes two files:
1. The module Scala file: `chisel-project/src/main/scala/chipagent/<ModuleName>.scala`
2. An updated `Generate.scala` with the new module in the match statement

**For complex specs (type: "complex"):**

The agent writes N+1 files:
1. One Scala file per sub-module: `chisel-project/src/main/scala/chipagent/<SubModuleName>.scala` for each entry in `modules[]`
2. The top-level module: `chisel-project/src/main/scala/chipagent/<TopModuleName>.scala` that instantiates and wires all sub-modules
3. An updated `Generate.scala` with the top module name (the top module pulls in sub-modules automatically)

### Step 3 -- Compile

Run the compilation script EXPLICITLY with the workspace path:

```
<plugin-root>/scripts/compile.sh workspace/<ModuleName>
```

Do NOT rely on the PostToolUse hook for compilation. The orchestrator calls compile.sh directly.

If compilation fails:
1. Read the error output from the build log
2. Follow the chisel-generator agent rules (`agents/chisel-generator.md`) to fix the issues in the generated Scala files
3. Re-run `<plugin-root>/scripts/compile.sh workspace/<ModuleName>` after fixing
4. Maximum 3 fix attempts. After 3 failures, stop and report the errors to the user:
   ```
   COMPILE AUTO-FIX FAILED after 3 attempts.
   Remaining errors:
   <paste compile error output>
   ```

### Step 4 -- Lint

Run Verilator lint on the generated Verilog with the workspace path:

```
<plugin-root>/scripts/lint.sh workspace/<ModuleName>
```

If lint passes (exit 0), continue to Step 5.

If lint fails (non-zero exit):
1. Read the error output carefully -- these are Verilog-level errors caused by Chisel source issues
2. Identify the Chisel source issue that caused the Verilog lint error
3. Follow the chisel-generator agent rules (`agents/chisel-generator.md`) to fix the Chisel source (NOT the generated Verilog -- never edit generated files)
4. Re-run `<plugin-root>/scripts/compile.sh workspace/<ModuleName>` after fixing
5. Re-run `<plugin-root>/scripts/lint.sh workspace/<ModuleName>` after compile succeeds
6. Repeat up to 3 total lint attempts

If lint still fails after 3 attempts, STOP the pipeline and report:
```
LINT AUTO-FIX FAILED after 3 attempts.
Remaining errors:
<paste lint error output>
```

After lint passes, check `workspace/<ModuleName>/generated/lint-warnings.log`. If non-empty, note the warnings:
```
Lint passed with N warnings (suppressed/non-blocking):
<paste warning summary>
```

### Step 5 -- Generate Testbench

After lint passes (Step 4), generate a C++ testbench for the module.

1. Determine the testbench path: `workspace/<ModuleName>/sim/tb_<ModuleName>.cpp`
2. If the testbench already exists at that path, skip generation and proceed to Step 6
3. If the testbench does not exist, read the testbench-generator agent definition at `agents/testbench-generator.md` (relative to plugin root) and follow its rules with the spec from `workspace/<ModuleName>/spec.json`
4. Write the testbench to `workspace/<ModuleName>/sim/tb_<ModuleName>.cpp` (workspace path, not flat sim/)

Ensure the directory exists first:
```
mkdir -p workspace/<ModuleName>/sim
```

The agent produces a C++ testbench following UVM-inspired architecture with standardized PASS/FAIL output format. For simple/combinational modules, it generates a `TestCase` struct with test vectors and a single `eval()` loop. For CPU modules with `spec.verification.tier == "reference-model"`, it generates a reference-model testbench using `cpu_test_template.h` with instruction encoding helpers and per-instruction comparison.

### Step 6 -- Simulate

Run the simulation script with the workspace path:

```
<plugin-root>/scripts/simulate.sh workspace/<ModuleName>
```

If simulation fails (non-zero exit):
1. Read `workspace/<ModuleName>/sim/logs/sim_result.log` for failure details
2. Attempt to fix the testbench (NOT the Verilog -- never edit generated files) by regenerating `workspace/<ModuleName>/sim/tb_<ModuleName>.cpp` with corrected test vectors
3. Re-run `<plugin-root>/scripts/simulate.sh workspace/<ModuleName>` after fixing
4. Maximum 3 simulation fix attempts. After 3 failures, STOP the pipeline and report:
   ```
   SIM AUTO-FIX FAILED after 3 attempts.
   Remaining failures:
   <paste sim_result.log content>
   ```

On success, proceed to Step 7.

### Step 7 -- Report

Format the simulation results into a verification report:

1. Read `workspace/<ModuleName>/sim/logs/sim_result.log`
2. Count PASS/FAIL lines
3. If lint warnings exist (from `workspace/<ModuleName>/generated/lint-warnings.log`), include them
4. Present formatted output:
   ```
   === Verification Report: <ModuleName> ===
   Verilog: workspace/<ModuleName>/generated/<ModuleName>.v
   Testbench: workspace/<ModuleName>/sim/tb_<ModuleName>.cpp

   Simulation: PASSED X/Y tests
   [per-test results from sim_result.log]

   Lint: PASSED (N warnings suppressed)
   [warning details if any]
   ```

## Pipeline Stages

| # | Stage              | Description                                      |
|---|--------------------|--------------------------------------------------|
| 1   | Parse Requirements | Extract module name, ports, operations from NL    |
| 1.5 | Confirm Spec       | Present parsed spec for user approval             |
| 2   | Generate Chisel    | Produce Chisel source from structured spec        |
| 3   | Compile to Verilog | sbt compiles Chisel to SystemVerilog via firtool  |
| 4   | Lint               | Verilator lint-only check on generated Verilog    |
| 5   | Generate Testbench | Create C++ testbench for Verilator simulation     |
| 6   | Simulate           | Run Verilator simulation and collect results      |
| 7   | Report             | Format test results into verification report      |

## Input

$ARGUMENTS

A natural language description of a digital hardware module. The description should include:

- Module name or purpose
- Input and output ports with bit widths
- Functional behavior (operations, logic, state machines)
- Any constraints or special requirements

## Output

Upon pipeline completion, the following artifacts are produced:

- `workspace/<ModuleName>/spec.json` -- structured JSON specification
- `workspace/<ModuleName>/generated/<ModuleName>.v` -- synthesizable Verilog
- `workspace/<ModuleName>/generated/<ModuleName>.sv` -- SystemVerilog variant (when firtool is available)
- `workspace/<ModuleName>/generated/lint-warnings.log` -- any remaining Verilator warnings with explanations
- `workspace/<ModuleName>/sim/tb_<ModuleName>.cpp` -- C++ Verilator testbench
- `workspace/<ModuleName>/sim/logs/sim_result.log` -- simulation test report
