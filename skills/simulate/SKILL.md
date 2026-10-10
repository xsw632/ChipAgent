---
name: simulate
description: Run Verilator simulation for a named module using its workspace testbench and generated Verilog.
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
---

# chip-agent:simulate

Run a Verilator simulation for a named module, executing its C++ testbench against the generated Verilog.

## Usage

```
/chip-agent:simulate <ModuleName>
```

## Instructions

1. **Extract module name** from `$ARGUMENTS`. If empty or blank, ask the user: "Which module should I simulate? Please provide a PascalCase module name (e.g., ALU, Counter, ALU8)."

2. **Check prerequisites.** Two conditions must be met:
   - `MyDesign/<ModuleName>/workspace/generated/` must exist and contain at least one `.v` file. If not, tell the user: "No generated Verilog found. Please run `/chip-agent:compile <ModuleName>` first."
   - `MyDesign/<ModuleName>/workspace/sim/tb_<ModuleName>.cpp` must exist. If not, tell the user: "No testbench found. Please run `/chip-agent:testbench <ModuleName>` first to generate one."

3. **Determine the project root directory** from the user's current working project (the directory containing `scripts/` and `chisel-project/`; `MyDesign/` is created on first use), not from the skill's installation location. Use that directory as the base for all paths below.

4. **Run simulation.** Execute the simulate script with the workspace path:
   ```
   <project-root>/scripts/simulate.sh <ModuleName>
   ```

5. **On success (exit 0):** Read `MyDesign/<ModuleName>/workspace/sim/logs/sim_result.log` and present the results in a formatted summary: total tests, pass count, fail count, and per-test breakdown.

6. **On failure (non-zero exit):** Read `MyDesign/<ModuleName>/workspace/sim/logs/sim_result.log` for failure details. Suggest checking the testbench at `MyDesign/<ModuleName>/workspace/sim/tb_<ModuleName>.cpp` or the Chisel source at `chisel-project/src/main/scala/chipagent/<ModuleName>.scala`.

## Input

$ARGUMENTS -- A PascalCase module name (e.g., `ALU`, `Counter`, `ALU8`).

## Output

Simulation results from `MyDesign/<ModuleName>/workspace/sim/logs/sim_result.log`, formatted as a pass/fail summary with per-test breakdown.
