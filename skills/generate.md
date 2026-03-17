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

## Pipeline

### Step 1 -- Parse Requirements

Use the requirement-parser agent to extract a structured JSON spec from the user's description.

The agent returns a JSON object with `moduleName`, `ports`, `operations`, `flags`, and `constraints`.

**Validation:** Verify the JSON is valid -- `moduleName` is PascalCase, all ports have direction/type/width, operations have opcodes. If the JSON is malformed, retry the parser once.

### Step 2 -- Generate Chisel

Use the chisel-generator agent with the JSON spec to produce Chisel source files.

The agent writes two files:
1. The module Scala file: `chisel-project/src/main/scala/chipagent/<ModuleName>.scala`
2. An updated `Generate.scala` with the new module in the match statement

### Step 3 -- Compile

The PostToolUse hook on Scala file writes automatically triggers `scripts/compile.sh`.

If compilation fails:
1. Read the error output from the build log
2. Have the chisel-generator agent fix the issues in the generated Scala files
3. Maximum 3 fix attempts. After 3 failures, stop and report the errors to the user.

### Step 4 -- Lint

Run Verilator lint on the generated Verilog:

1. Run `scripts/lint.sh`
2. If lint passes (exit 0), continue to Step 5 (Verify)
3. If lint fails (non-zero exit):
   a. Read the error output carefully -- these are Verilog-level errors caused by Chisel source issues
   b. Identify the Chisel source issue that caused the Verilog lint error
   c. Use the chisel-generator agent to fix the Chisel source (NOT the generated Verilog -- never edit generated files)
   d. The PostToolUse hook will auto-trigger compile.sh when the Scala file is written
   e. After compile succeeds, run `scripts/lint.sh` again
   f. Repeat up to 3 total lint attempts
4. If lint still fails after 3 attempts, STOP the pipeline and report:
   ```
   LINT AUTO-FIX FAILED after 3 attempts.
   Remaining errors:
   <paste lint error output>
   ```
5. After lint passes, check `generated/lint-warnings.log`. If non-empty, note the warnings in the output:
   ```
   Lint passed with N warnings (suppressed/non-blocking):
   <paste warning summary>
   ```

### Step 5 -- Generate Testbench

After lint passes (Step 4), generate a C++ testbench for the module:

1. Determine the testbench path: `sim/tb_<ModuleName>.cpp`
2. If the testbench already exists (e.g., the ALU reference testbench at `sim/tb_ALU.cpp`), skip generation and proceed to Step 6
3. If the testbench does not exist, generate one following the pattern in `sim/tb_ALU.cpp`:
   - Include `"V<ModuleName>.h"` and `"verilated.h"`
   - Define a `TestCase` struct with fields matching the module ports
   - Create test vectors from the parsed module spec (using the operations and expected behaviors)
   - Follow the exact output format: `[TEST N] OP: a=X b=Y | expect=Z got=W | PASS/FAIL`
   - Include `RESULT: PASSED/FAILED X/Y tests` as the final line
4. Write the testbench file to `sim/tb_<ModuleName>.cpp`

### Step 6 -- Simulate

Run `scripts/simulate.sh <ModuleName>` to compile and execute the testbench:

1. Run the script and capture output
2. If simulation fails (non-zero exit), read `sim/logs/sim_result.log` for failure details
3. On failure, attempt to fix the testbench (NOT the Verilog -- never edit generated files) by regenerating `sim/tb_<ModuleName>.cpp` with corrected test vectors
4. Maximum 3 simulation fix attempts. After 3 failures, STOP the pipeline and report:
   ```
   SIM AUTO-FIX FAILED after 3 attempts.
   Remaining failures:
   <paste sim_result.log content>
   ```
5. On success, proceed to Step 7

### Step 7 -- Report

Format the simulation results into a verification report:

1. Read `sim/logs/sim_result.log`
2. Count PASS/FAIL lines
3. If lint warnings exist (from `generated/lint-warnings.log`), include them
4. Present formatted output:
   ```
   === Verification Report: <ModuleName> ===
   Verilog: generated/<ModuleName>.v
   Testbench: sim/tb_<ModuleName>.cpp

   Simulation: PASSED X/Y tests
   [per-test results from sim_result.log]

   Lint: PASSED (N warnings suppressed)
   [warning details if any]
   ```

## Pipeline Stages

| # | Stage              | Status       | Description                                      |
|---|--------------------|--------------|--------------------------------------------------|
| 1 | Parse Requirements | **Active**   | Extract module name, ports, operations from NL    |
| 2 | Generate Chisel    | **Active**   | Produce Chisel source from structured spec        |
| 3 | Compile to Verilog | **Active**   | sbt compiles Chisel to SystemVerilog via firtool  |
| 4 | Lint               | **Active**   | Verilator lint-only check on generated Verilog    |
| 5 | Generate Testbench | **Active**   | Create C++ testbench for Verilator simulation     |
| 6 | Simulate           | **Active**   | Run Verilator simulation and collect results      |
| 7 | Report             | **Active**   | Format test results into verification report      |

## Input

$ARGUMENTS

A natural language description of a digital hardware module. The description should include:

- Module name or purpose
- Input and output ports with bit widths
- Functional behavior (operations, logic, state machines)
- Any constraints or special requirements

## Output

Upon pipeline completion, the following artifacts are produced:

- `generated/<ModuleName>.v` -- synthesizable Verilog
- `generated/<ModuleName>.sv` -- SystemVerilog variant (when firtool is available)
- `generated/lint-warnings.log` -- any remaining Verilator warnings with explanations
- `sim/logs/sim_result.log` -- simulation test report
