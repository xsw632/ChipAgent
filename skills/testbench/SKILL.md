---
name: testbench
description: Generate a C++ Verilator testbench from a module's spec.json, reading the spec from the workspace directory.
disable-model-invocation: true
allowed-tools:
  - Read
  - Write
  - Bash
  - Grep
  - Glob
---

# chip-agent:testbench

Generate a C++ Verilator testbench for a hardware module using its spec.json specification.

## Usage

```
/chip-agent:testbench <ModuleName>
```

## Instructions

1. **Extract the module name** from `$ARGUMENTS`. If `$ARGUMENTS` is empty or blank, ask the user: "Which module should I generate a testbench for? Please provide a PascalCase module name (e.g., ALU, Counter, SimpleRISCV)."

2. **Validate the module name.** The name must be PascalCase: first character uppercase, no spaces, no hyphens, only alphanumeric characters. If invalid, inform the user and ask for a corrected name.

3. **Determine the project root directory** by finding the nearest ancestor directory of this skill file that contains `.claude`. Use that directory as the base for all relative paths below.

4. **Read the spec from workspace.** Use the Read tool to load:
   ```
   workspace/<ModuleName>/spec.json
   ```
   If the file does not exist, STOP and tell the user: "No spec.json found for <ModuleName>. Run `/chip-agent:requirement-parser` first to create a specification."

   This step reads spec.json from disk, NOT from conversation context. This ensures the testbench skill works correctly even in a fresh session where no prior conversation about the module exists.

5. **Read the testbench-generator agent definition** at `agents/testbench-generator.md` (relative to the project root). This agent contains the full testbench generation rules, templates, and conventions for both simple and complex (CPU reference model) designs.

6. **Follow the agent's instructions** using the spec JSON content to generate a C++ testbench. Apply all rules from the agent definition including:
   - Correct testbench mode selection (simple vs reference-model)
   - UVM-inspired architecture (TestCase struct, driver, monitor, scoreboard, reporter)
   - Verilator port naming with `io_` prefix
   - Test vector generation with boundary and edge cases
   - Standardized output format: `[TEST N] ... PASS/FAIL` and `RESULT: PASSED/FAILED X/Y tests`

7. **Write the testbench to the workspace path.** IMPORTANT: Override the agent's default output path. Write to:
   ```
   workspace/<ModuleName>/sim/tb_<ModuleName>.cpp
   ```
   NOT to the agent's flat-mode default of `sim/tb_<ModuleName>.cpp`. Ensure the directory exists first:
   ```
   mkdir -p workspace/<ModuleName>/sim
   ```

8. **Confirm to the user:**
   - Testbench path: `workspace/<ModuleName>/sim/tb_<ModuleName>.cpp`
   - Test vector count: N test cases covering M operations
   - Next step: "Run `/chip-agent:simulate <ModuleName>` to compile and execute the testbench."

## Input

`$ARGUMENTS` -- A PascalCase module name (e.g., `ALU`, `Counter`, `SimpleRISCV`). The module must have a `workspace/<ModuleName>/spec.json` file created by `/chip-agent:requirement-parser`.

## Output

`workspace/<ModuleName>/sim/tb_<ModuleName>.cpp` containing a complete C++ Verilator testbench ready for simulation.
