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

1. **Extract module name** from `$ARGUMENTS`. If empty or blank, ask the user: "Which module should I simulate? Please provide a PascalCase module name (e.g., ALU, Counter, TrivialModule)."

2. **Check prerequisites.** Two conditions must be met:
   - `workspace/<ModuleName>/generated/` must exist and contain at least one `.v` file. If not, tell the user: "No generated Verilog found. Please run `/chip-agent:compile <ModuleName>` first."
   - `workspace/<ModuleName>/sim/tb_<ModuleName>.cpp` must exist. If not, tell the user: "No testbench found. Please run `/chip-agent:testbench <ModuleName>` first to generate one."

3. **Determine the plugin root directory** by finding the nearest ancestor directory of this skill file that contains `.claude-plugin/plugin.json`. Use that directory as the base for all paths below.

4. **Run simulation.** Execute the simulate script with the workspace path:
   ```
   <plugin-root>/scripts/simulate.sh workspace/<ModuleName>
   ```

5. **On success (exit 0):** Read `workspace/<ModuleName>/sim/logs/sim_result.log` and present the results in a formatted summary: total tests, pass count, fail count, and per-test breakdown.

6. **On failure (non-zero exit):** Read `workspace/<ModuleName>/sim/logs/sim_result.log` for failure details. Suggest checking the testbench at `workspace/<ModuleName>/sim/tb_<ModuleName>.cpp` or the Chisel source at `chisel-project/src/main/scala/chipagent/<ModuleName>.scala`.

## Input

$ARGUMENTS -- A PascalCase module name (e.g., `ALU`, `Counter`, `TrivialModule`).

## Output

Simulation results from `workspace/<ModuleName>/sim/logs/sim_result.log`, formatted as a pass/fail summary with per-test breakdown.
