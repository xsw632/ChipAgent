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

## Pipeline Stages

| # | Stage              | Status       | Description                                      |
|---|--------------------|--------------|--------------------------------------------------|
| 1 | Parse Requirements | Planned      | Extract module name, ports, operations from NL    |
| 2 | Generate Chisel    | Planned      | Produce Chisel source from structured spec        |
| 3 | Compile to Verilog | **Active**   | sbt compiles Chisel to SystemVerilog via firtool  |
| 4 | Lint               | Planned      | Verilator lint-only check on generated Verilog    |
| 5 | Generate Testbench | Planned      | Create C++ testbench for Verilator simulation     |
| 6 | Simulate           | Planned      | Run Verilator simulation and collect results      |
| 7 | Report             | Planned      | Format test results into verification report      |

**Phase 1 status:** Only the compilation stage (stage 3) is functional. The remaining stages are placeholders that will be implemented in subsequent phases.

## Input

A natural language description of a digital hardware module. The description should include:

- Module name or purpose
- Input and output ports with bit widths
- Functional behavior (operations, logic, state machines)
- Any constraints or special requirements

## Output

Upon pipeline completion, the following artifacts are produced:

- `generated/<ModuleName>.sv` -- synthesizable SystemVerilog
- `sim/logs/sim_result.log` -- simulation test report (future phases)
