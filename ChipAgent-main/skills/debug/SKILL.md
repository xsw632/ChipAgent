---
name: debug
description: Analyze simulation failures by cross-referencing workspace artifacts and producing a structured debug report with fix suggestions.
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
---

# chip-agent:debug

Analyze simulation failures for a hardware module by cross-referencing its workspace artifacts.

## Usage

```
/chip-agent:debug <ModuleName>
```

## Instructions

1. **Extract the module name** from `$ARGUMENTS`. If empty or blank, ask the user: "Which module should I debug? Please provide a PascalCase module name (e.g., ALU, Counter, SimpleRISCV)."

2. **Validate the module name.** Must be PascalCase (starts with uppercase letter, contains only alphanumeric characters). If invalid, ask the user to provide a valid PascalCase name.

3. **Determine the plugin root directory** by finding the nearest ancestor directory of this skill file that contains `.claude-plugin/plugin.json`. Store as `PLUGIN_ROOT`.

4. **Check required artifacts exist:**
   - `MyDesign/<ModuleName>/workspace/spec.json` -- if missing, STOP: "No spec found. Run `/chip-agent:requirement-parser` first."
   - `MyDesign/<ModuleName>/chisel-project/src/main/scala/chipagent/<ModuleName>.scala` -- if missing, STOP: "No Chisel source found for `<ModuleName>`."
   - `MyDesign/<ModuleName>/workspace/sim/logs/sim_result.log` -- if missing, STOP: "No simulation results. Run `/chip-agent:simulate <ModuleName>` first."
   - `MyDesign/<ModuleName>/workspace/sim/logs/<ModuleName>.vcd` -- if missing, note that VCD is unavailable. Analysis will proceed in log-only mode.

5. **Read the debug-analyzer agent definition** at `agents/debug-analyzer.md` (relative to plugin root).

6. **Follow the agent's analysis instructions** to:
   - Parse sim_result.log for failed tests
   - Cross-reference failures with spec.json operations
   - Extract VCD signal values at failure timestamps (if VCD available) using `scripts/parse_vcd.py`
   - Map failures to Chisel source code blocks
   - Generate fix suggestions

7. **Write the debug report** to `MyDesign/<ModuleName>/workspace/debug/debug_report.md` following the agent's report structure. Create the directory first with `mkdir -p MyDesign/<ModuleName>/workspace/debug`.

8. **Display a summary** in conversation:
   - Total tests, passed, failed
   - List of failed test names
   - Report location: `MyDesign/<ModuleName>/workspace/debug/debug_report.md`
   - Next steps: "Review the fix suggestions in the debug report. To apply fixes, edit the Chisel source and re-run `/chip-agent:simulate <ModuleName>`."

## Input

`$ARGUMENTS` -- PascalCase module name.

## Output

- `MyDesign/<ModuleName>/workspace/debug/debug_report.md` -- structured failure analysis with signal traces, root cause analysis, and fix suggestions
- Conversation summary with key findings and next steps
