---
name: requirement-parser
description: Parse natural language hardware descriptions into structured JSON specifications, writing the result to workspace/<ModuleName>/spec.json.
disable-model-invocation: true
allowed-tools:
  - Read
  - Write
  - Bash
  - Grep
  - Glob
---

# chip-agent:requirement-parser

Parse a natural language hardware description into a structured JSON specification file.

## Usage

```
/chip-agent:requirement-parser <hardware description>
```

## Instructions

1. **Extract the hardware description** from `$ARGUMENTS`. If `$ARGUMENTS` is empty or blank, ask the user: "Please describe the hardware module you want to create. For example: 'A 32-bit ALU supporting ADD, SUB, AND, OR, XOR, and SLT operations with a zero flag output.'"

2. **Determine the project root directory** by finding the nearest ancestor directory of this skill file that contains `.claude`. Use that directory as the base for all relative paths below.

3. **Read the requirement-parser agent definition** at `agents/requirement-parser.md` (relative to the project root). This agent contains the full parsing rules, schema definitions, and examples for both simple and complex hardware designs.

4. **Follow the agent's instructions** to parse `$ARGUMENTS` into a structured JSON specification. The agent returns ONLY the raw JSON -- no markdown fences, no explanation. Apply all parsing rules from the agent definition including:
   - Design complexity detection (simple vs complex)
   - PascalCase module names, camelCase port names
   - Correct port types (UInt, SInt, Bool) and widths
   - Operation expressions in Chisel syntax with `io.<portName>` prefix
   - SLT using signed comparison via `.asSInt`

5. **Validate the JSON output** before writing to disk:
   - `moduleName` is present and PascalCase (first character uppercase, alphanumeric only)
   - `type` is `"simple"` or `"complex"`
   - All ports have `direction` (input/output), `type` (UInt/SInt/Bool), and `width` (integer)
   - For simple specs: `ports` array is non-empty with at least one input and one output
   - For complex specs: every name in `topModule.submodules` matches a name in `modules[]`
   - If validation fails, fix the JSON before proceeding

6. **Create the workspace directory structure** using Bash:
   ```
   mkdir -p workspace/<moduleName>/generated workspace/<moduleName>/sim/logs
   ```

7. **Write the JSON spec to disk** using the Write tool. Write to:
   ```
   workspace/<moduleName>/spec.json
   ```
   This step is CRITICAL. The requirement-parser agent returns JSON to conversation output only -- it does NOT write files itself. This skill MUST capture the JSON and write it to disk so that downstream skills (testbench, compile, etc.) can read it.

8. **Present a summary** to the user:
   - Module name and description
   - Type: simple or complex
   - Port count: N inputs, M outputs
   - Operation count (if any)
   - Flag count (if any)
   - File location: `workspace/<moduleName>/spec.json`
   - Next step: "Run `/chip-agent:testbench <ModuleName>` to generate a testbench, or `/chip-agent:compile <ModuleName>` to compile to Verilog."

## Input

`$ARGUMENTS` -- A natural language description of a hardware module (e.g., "A 32-bit ALU with ADD, SUB, AND, OR operations").

## Output

`workspace/<ModuleName>/spec.json` containing the structured JSON specification. The workspace directory tree is also created with `generated/` and `sim/logs/` subdirectories.
