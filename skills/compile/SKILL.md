---
name: compile
description: Compile a named Chisel module to Verilog using sbt, outputting to the module's workspace directory.
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
---

# chip-agent:compile

Compile a Chisel module to Verilog, placing output in the module's workspace directory.

## Usage

```
/chip-agent:compile <ModuleName>
```

## Instructions

1. **Extract module name** from `$ARGUMENTS`. If empty or blank, ask the user: "Which module should I compile? Please provide a PascalCase module name (e.g., ALU, Counter, TrivialModule)."

2. **Validate module name.** The name must be PascalCase: first character uppercase, no spaces, no hyphens, only alphanumeric characters. If invalid, inform the user and ask for a corrected name.

3. **Determine the project root directory** by finding the nearest ancestor directory of this skill file that contains `.claude`. Use that directory as the base for all paths below.

4. **Run compilation.** Execute the compile script with the workspace path:
   ```
   <project-root>/scripts/compile.sh workspace/<ModuleName>
   ```

5. **On success:** List the generated files in `workspace/<ModuleName>/generated/` so the user can see what was produced. Mention that they can now run `/chip-agent:lint <ModuleName>` to check the output.

6. **On failure:** Show the build error output. Suggest checking the Chisel source at `chisel-project/src/main/scala/chipagent/<ModuleName>.scala` for issues.

## Input

$ARGUMENTS -- A PascalCase module name (e.g., `ALU`, `Counter`, `TrivialModule`).

## Output

Generated Verilog files in `workspace/<ModuleName>/generated/` (`.v` and `.sv` files).
