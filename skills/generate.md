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

### Step 4 -- Verify

Confirm that the `generated/` directory contains the expected `.v` or `.sv` file for the module. Report success with the path to the generated Verilog file.

## Pipeline Stages

| # | Stage              | Status       | Description                                      |
|---|--------------------|--------------|--------------------------------------------------|
| 1 | Parse Requirements | **Active**   | Extract module name, ports, operations from NL    |
| 2 | Generate Chisel    | **Active**   | Produce Chisel source from structured spec        |
| 3 | Compile to Verilog | **Active**   | sbt compiles Chisel to SystemVerilog via firtool  |
| 4 | Lint               | Planned      | Verilator lint-only check on generated Verilog    |
| 5 | Generate Testbench | Planned      | Create C++ testbench for Verilator simulation     |
| 6 | Simulate           | Planned      | Run Verilator simulation and collect results      |
| 7 | Report             | Planned      | Format test results into verification report      |

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
- `sim/logs/sim_result.log` -- simulation test report (future phases)
