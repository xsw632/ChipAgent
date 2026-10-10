---
name: lint
description: Run Verilator lint checks on generated Verilog for a named module in its workspace directory.
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
---

# chip-agent:lint

Run Verilator lint-only checks on the generated Verilog for a named module.

## Usage

```
/chip-agent:lint <ModuleName>
```

## Instructions

1. **Extract module name** from `$ARGUMENTS`. If empty or blank, ask the user: "Which module should I lint? Please provide a PascalCase module name (e.g., ALU, Counter, ALU8)."

2. **Check prerequisites.** Verify that `MyDesign/<ModuleName>/workspace/generated/` exists and contains at least one `.v` file. If not, tell the user: "No generated Verilog found. Please run `/chip-agent:compile <ModuleName>` first."

3. **Determine the project root directory** from the user's current working project (the directory containing `scripts/` and `chisel-project/`; `MyDesign/` is created on first use), not from the skill's installation location. Use that directory as the base for all paths below.

4. **Run lint.** Execute the lint script with the workspace path:
   ```
   <project-root>/scripts/lint.sh <ModuleName>
   ```

5. **On success (exit 0):** Report that lint passed. Check if `MyDesign/<ModuleName>/workspace/generated/lint-warnings.log` exists and is non-empty. If so, list the suppressed warnings. Mention that the user can now run `/chip-agent:simulate <ModuleName>`.

6. **On failure (non-zero exit):** Show the Verilator lint errors. Suggest fixing the Chisel source at `chisel-project/src/main/scala/chipagent/<ModuleName>.scala` -- do not edit the generated Verilog directly.

## Input

$ARGUMENTS -- A PascalCase module name (e.g., `ALU`, `Counter`, `ALU8`).

## Output

Lint pass/fail report. If warnings were suppressed, they are listed from `MyDesign/<ModuleName>/workspace/generated/lint-warnings.log`.
