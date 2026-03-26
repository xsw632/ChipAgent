---
name: warningExp
description: Explain lint warnings for a generated hardware module
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - AskUserQuestion
---

# chip-agent:warningExp

Explain Verilator lint warnings and simulation issues for a generated hardware module.

## Usage

```
/chip-agent:warningExp
```

## Instructions

**Determine the plugin root directory** by finding the nearest ancestor directory of this skill file that contains `.claude-plugin/plugin.json`. Use that directory as the base for all relative paths below.

### Step 1 -- Discover available modules

List all subdirectories of `MyDesign/` (relative to plugin root) to find modules that have been generated. Each subdirectory name is a module name (PascalCase).

```bash
ls -d <plugin-root>/MyDesign/*/
```

If `MyDesign/` does not exist or is empty, tell the user:
```
No modules found. Run /chip-agent:workflow first to generate a module.
```
And stop.

### Step 2 -- Let user choose a module

Use `AskUserQuestion` to present the discovered modules as selectable options. Each option should be the module name (directory basename).

- Header: `"Module"`
- Question: `"Which module's warnings do you want to analyze?"`
- Options: One per discovered module directory, with description showing whether `lint-warnings.log` exists and its line count

### Step 3 -- Read warning sources

After the user selects a module `<ModuleName>`, read and analyze these files:

1. **Lint warnings:** `MyDesign/<ModuleName>/workspace/generated/lint-warnings.log`
2. **Simulation log:** `MyDesign/<ModuleName>/workspace/sim/logs/sim_result.log` (check for any FAIL lines)
3. **Generated Verilog:** `MyDesign/<ModuleName>/workspace/generated/<ModuleName>.v` (for context on warning locations)
4. **Chisel source:** `MyDesign/<ModuleName>/chisel-project/src/main/scala/chipagent/<ModuleName>.scala` (to trace warnings back to source)

If `lint-warnings.log` does not exist or is empty, and simulation has no FAILs, report:
```
No warnings or issues found for <ModuleName>.
```

### Step 4 -- Explain each warning

For each warning line in `lint-warnings.log`, provide:

1. **Warning type** — the Verilator warning category (e.g., `UNUSEDSIGNAL`, `WIDTHTRUNC`, `WIDTHEXPAND`, `UNOPTFLAT`)
2. **Location** — which generated Verilog file and line number
3. **Source** — trace back to the Chisel source that caused this warning (read the Verilog line, identify the signal, find it in the Scala source)
4. **Root cause explanation** — plain-language description of why this warning exists. Common patterns:

   | Warning Type | Typical Root Cause | Severity |
   |---|---|---|
   | `UNUSEDSIGNAL: 'clock'` | Chisel `Module` always emits `clock`/`reset` ports, but combinational modules don't use them | Safe to ignore |
   | `UNUSEDSIGNAL: 'reset'` | Same as above — combinational modules have no registers to reset | Safe to ignore |
   | `UNUSEDSIGNAL: bits of signal not used` | Arithmetic produces wider result than needed (e.g., 8-bit multiply → 16-bit, only lower 8 used) | Safe to ignore if truncation is intentional |
   | `WIDTHTRUNC` | Assigning a wider signal to a narrower port — Chisel auto-truncates | Check if data loss is intended |
   | `WIDTHEXPAND` | Assigning a narrower signal to a wider port — Chisel auto-extends | Usually safe |
   | `UNOPTFLAT` | Combinational loop detected by Verilator — may indicate a Chisel wiring issue | Needs investigation |
   | `CASEINCOMPLETE` | `switch`/`is` block doesn't cover all possible opcode values | Safe if default assignment exists |

5. **Recommendation** — whether the warning is:
   - **Safe to ignore** (Chisel framework artifact, intentional truncation)
   - **Worth reviewing** (potential data loss, unintended behavior)
   - **Needs fix** (combinational loops, missing assignments)

### Step 5 -- Check simulation results

If `sim_result.log` exists and contains any `FAIL` lines:
- List the failing tests
- Briefly explain what each test was checking (based on the test label in the log line)

### Step 6 -- Present report

Format the output as:

```
=== Warning Analysis: <ModuleName> ===

Lint Warnings: N total

  [1] <WARNING_TYPE> (line X of <ModuleName>.v)
      Signal: <signal_name>
      Source: <Chisel source explanation>
      Cause: <plain-language explanation>
      Verdict: Safe to ignore / Needs review / Needs fix

  [2] ...

Simulation: PASSED X/Y tests (or details of failures)

Summary: N warnings analyzed — M safe to ignore, K need review
```

## Input

No arguments required. The skill discovers modules automatically and prompts the user to choose.

## Output

A formatted warning analysis report explaining each Verilator lint warning and any simulation failures for the selected module.
