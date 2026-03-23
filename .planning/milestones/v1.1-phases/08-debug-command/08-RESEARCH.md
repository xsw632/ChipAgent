# Phase 8: Debug Command - Research

**Researched:** 2026-03-20
**Domain:** Simulation failure analysis with VCD waveform integration, Claude Code skill/agent architecture
**Confidence:** HIGH

## Summary

Phase 8 implements `/chip-agent:debug <Module>`, an agent-backed skill that reads four workspace artifacts (spec.json, Chisel source, sim_result.log, VCD waveform), cross-references them to identify which test vectors failed, maps failures to spec operations and Chisel logic, extracts signal values from VCD at failure timestamps, and produces a structured debug report with targeted Chisel fix suggestions. The phase also modifies the simulation pipeline to enable VCD trace generation by adding `--trace` to `simulate.sh` and VCD tracing hooks to the testbench-generator agent's C++ templates.

The technical domain spans three areas: (1) Verilator VCD tracing API in C++, (2) VCD file parsing in Python, and (3) structured failure analysis mapping sim results back through spec and source. All three are well-understood with high-confidence sources. The waveform_mcp project (referenced by user) provides useful architectural inspiration for the VCD parser but will NOT be used as a dependency -- a lightweight Python script is the decided approach.

**Primary recommendation:** Implement in two waves: first enable VCD tracing in the simulation pipeline (simulate.sh + testbench-generator modifications), then build the debug skill/agent/parser on top of the VCD-enabled infrastructure.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Write a lightweight Python VCD parser in `scripts/parse_vcd.py` -- inspired by waveform_mcp's approach but minimal and self-contained (no external MCP dependency)
- Per-failure signal drill-down: for each failed test, query specific signals (inputs, outputs, control) at the failure timestamp
- VCD traces always generated: `simulate.sh` passes `--trace` to Verilator by default
- VCD file stored at `workspace/<Module>/sim/logs/<Module>.vcd`
- Phase 8 modifies `simulate.sh` to add `--trace` flag and updates testbench-generator agent to include VCD tracing hooks (`verilated_vcd_c.h`, `tfp->open/dump/close`)
- Debug writes a structured report to `workspace/<Module>/debug/debug_report.md` AND displays summary in conversation
- Report sections: Summary (pass/fail counts), Failed Tests (per-test: inputs, expected vs actual, signal trace), Root Cause Analysis (mapped to spec + Chisel logic), Fix Suggestions (specific code changes)
- Structured sections format, not narrative
- Diagnose + suggest specific Chisel code fixes -- does NOT auto-apply (user reviews and decides)
- Fix suggestions target Chisel source as primary; if testbench expected values appear wrong, flag it but still point to Chisel
- Full traceability chain: each failed test maps to (1) the spec operation it tests, (2) the Chisel switch/is block implementing it, (3) the signal values at failure time from VCD
- Core 4 artifacts: spec.json, Chisel source (`chipagent/<Module>.scala`), sim_result.log, VCD waveform
- Graceful degradation: missing VCD = fall back to log-only analysis; missing sim_result.log = suggest "run simulate first"; missing spec.json or Chisel source = hard error

### Claude's Discretion
- Python VCD parser internal architecture (classes, functions, data structures)
- Exact debug report markdown formatting
- How to parse and match sim_result.log test lines to spec.json operations
- Skill YAML frontmatter and tool permissions

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SKILL-07 | `/chip-agent:debug` analyzes simulation failures by cross-referencing spec.json, Chisel source, and sim_result.log to suggest targeted fixes | Full research coverage: VCD parsing approach, artifact cross-referencing strategy, skill/agent architecture patterns, testbench VCD hook integration, debug report structure |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Python 3.10+ | 3.10.18 (detected) | VCD parser script | Already available on system; pure Python, no pip deps needed |
| Verilator | 5.008+ | VCD trace generation via `--trace` | Already in project stack; native VCD support |
| verilated_vcd_c.h | (bundled w/ Verilator) | C++ VCD tracing API in testbenches | Official Verilator tracing header |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| json (Python stdlib) | built-in | Parse spec.json, output signal data as JSON | Always -- VCD parser output format |
| re (Python stdlib) | built-in | Parse sim_result.log lines | Always -- regex matching for test result lines |
| argparse (Python stdlib) | built-in | CLI for parse_vcd.py | Always -- structured CLI interface |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom Python VCD parser | vcdvcd (pip package) | vcdvcd is more full-featured but adds pip dependency; custom is simpler and self-contained per user decision |
| Custom Python VCD parser | waveform_mcp (MCP server) | Too heavy -- full MCP server with FSDB support, Chinese-language comments, excessive token overhead; user explicitly rejected |
| Python | Node.js/Bash | Python excels at text parsing and JSON output; Bash is fragile for structured data; Node adds npm dependency |

**Installation:**
No installation needed. Python 3.10+ is already available. All VCD parsing uses pure Python stdlib modules (json, re, sys, argparse).

## Architecture Patterns

### Recommended Project Structure
```
ChipAgent/
  skills/
    debug/
      SKILL.md                    # /chip-agent:debug slash command (agent-backed)
  agents/
    debug-analyzer.md             # Agent that reads 4 artifacts, cross-references, produces report
  scripts/
    parse_vcd.py                  # Lightweight Python VCD parser (called by agent via Bash)
    simulate.sh                   # MODIFIED: add --trace flag to verilator command
  agents/
    testbench-generator.md        # MODIFIED: add VCD tracing hooks to C++ templates
```

### Pattern 1: Agent-Backed Skill (Established Project Pattern)
**What:** A skill YAML with `disable-model-invocation: true` that delegates to an agent markdown file for complex reasoning
**When to use:** When the skill needs LLM reasoning (not just script execution)
**Example (from existing testbench skill):**
```yaml
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
```

The skill reads workspace artifacts, invokes `scripts/parse_vcd.py` via Bash for signal extraction, then follows `agents/debug-analyzer.md` rules for analysis and report generation.

### Pattern 2: Script-as-Tool (Established Project Pattern)
**What:** A Python/Bash script invoked by an agent via the Bash tool, producing JSON on stdout
**When to use:** When deterministic data extraction is needed before LLM reasoning
**Example pattern:**
```bash
# Agent calls:
python3 <plugin-root>/scripts/parse_vcd.py \
  --vcd workspace/<Module>/sim/logs/<Module>.vcd \
  --signals io_result io_inputA io_inputB io_op \
  --time 5
```
Output: JSON with signal values at the specified timestamp.

### Pattern 3: Graceful Degradation (Decided in CONTEXT.md)
**What:** Check for each artifact; degrade analysis depth rather than failing entirely
**When to use:** When some artifacts are optional (VCD) vs required (spec.json, Chisel source)
**Flow:**
1. Check spec.json -- HARD ERROR if missing ("No spec found. Run requirement-parser first.")
2. Check Chisel source -- HARD ERROR if missing ("No Chisel source found.")
3. Check sim_result.log -- SOFT ERROR ("No simulation results. Run `/chip-agent:simulate` first.")
4. Check VCD file -- DEGRADE ("VCD not found; performing log-only analysis without signal traces.")

### Anti-Patterns to Avoid
- **DO NOT auto-apply fixes:** Debug command diagnoses and suggests; user decides whether to apply. The generate pipeline already has auto-fix loops (3 attempts); debug is explicitly a diagnostic tool.
- **DO NOT parse generated Verilog:** Always trace back to Chisel source. Verilog is an intermediate artifact.
- **DO NOT install pip packages:** The VCD parser must use only Python stdlib. The user explicitly decided against external dependencies.
- **DO NOT use waveform_mcp as a dependency:** Inspired by its approach, but implement a minimal self-contained parser.
- **DO NOT load entire VCD into memory for large files:** Use targeted extraction -- only read signals and timestamps relevant to failed tests.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| VCD file format parsing | Full VCD viewer/navigator | Targeted signal extraction at specific timestamps | Only need values at failure times, not full waveform browsing |
| sim_result.log parsing | Custom log parser framework | Simple regex on known format `[TEST N] <op>: ... PASS/FAIL` | Format is controlled by our testbench generator; exact pattern is stable |
| spec.json to test mapping | Fuzzy matching system | Direct opcode/name match between spec.operations[].name and test op_name | The testbench generator uses spec operation names directly in test output |
| Chisel source analysis | AST parser for Scala | Text search for `is(<opcode>.U)` blocks in switch statement | Chisel modules follow predictable patterns from the chisel-generator agent |

**Key insight:** The debug command benefits enormously from the fact that ALL artifacts in the pipeline are generated by known agents with known output formats. The sim_result.log format, spec.json schema, and Chisel source structure are all predictable -- no need for general-purpose parsers.

## Common Pitfalls

### Pitfall 1: VCD Timestamp Mismatch with Test Numbers
**What goes wrong:** VCD timestamps are in simulation time units (ns/ps); test numbers in sim_result.log are sequential integers. The parser must map test N to the correct VCD timestamp.
**Why it happens:** Combinational modules evaluate instantly (no clock), so each test might be at a different sim_time. Sequential modules use clock cycles.
**How to avoid:** The testbench generator must include `sim_time` tracking and dump VCD at each test evaluation. Each test case maps to a known sim_time value. For combinational modules: test N is at sim_time N (or N*2 if including setup). The `parse_vcd.py` script accepts a timestamp parameter, and the debug agent calculates the correct timestamp from the test number.
**Warning signs:** VCD signal values don't match expected test inputs -- indicates timestamp mapping is wrong.

### Pitfall 2: Verilator --trace Requires C++ Testbench Changes
**What goes wrong:** Adding `--trace` to the verilator command line is necessary but NOT sufficient. The C++ testbench must also include VCD tracing API calls.
**Why it happens:** Verilator's `--trace` flag generates trace infrastructure in the model, but the testbench must explicitly create a `VerilatedVcdC` object, call `trace()`, `open()`, `dump()`, and `close()`.
**How to avoid:** Both `simulate.sh` AND `agents/testbench-generator.md` must be updated. The testbench template must include the full VCD API sequence (see Code Examples section).
**Warning signs:** `--trace` added to verilator but no `.vcd` file appears after simulation.

### Pitfall 3: VCD File Path in Testbench Must Match Expected Location
**What goes wrong:** The VCD file is written by the testbench (via `tfp->open("path.vcd")`), but the debug agent expects it at `workspace/<Module>/sim/logs/<Module>.vcd`.
**Why it happens:** The testbench runs from `obj_dir/` inside the workspace, so relative paths resolve differently.
**How to avoid:** Use an absolute path or a path relative to the simulation binary's working directory. The `simulate.sh` script already `cd`s or sets paths correctly. The testbench should write the VCD file to a path that lands in `sim/logs/`. Since the binary runs from `obj_dir/`, use `../logs/<Module>.vcd` as the path, OR pass the VCD path as a command-line argument.
**Warning signs:** VCD file appears in `obj_dir/` instead of `sim/logs/`.

### Pitfall 4: Forgetting tfp->close() Causes Truncated VCD
**What goes wrong:** If `tfp->close()` is not called before `dut->final()`, the VCD file may be truncated or corrupted.
**Why it happens:** VCD writing is buffered; close flushes the buffer.
**How to avoid:** Always call `tfp->close()` before cleanup. The testbench template must include this in the cleanup section.
**Warning signs:** VCD file exists but is incomplete -- missing later test timestamps.

### Pitfall 5: Signal Names in VCD Use Verilator's Internal Hierarchy
**What goes wrong:** Signal paths in VCD files use Verilator's hierarchical naming (e.g., `TOP.V<Module>.io_result`), not the flat Chisel port names.
**Why it happens:** Verilator wraps the DUT in a `TOP` scope and prefixes with the module class name.
**How to avoid:** The VCD parser must handle hierarchical signal names. Search for signals by suffix (e.g., `io_result`) rather than exact path match. The parser should strip the hierarchy prefix when presenting results.
**Warning signs:** Parser fails to find signals or returns empty results despite valid VCD file.

### Pitfall 6: Missing Verilated::traceEverOn(true)
**What goes wrong:** VCD file is created but empty (header only, no signal data).
**Why it happens:** `Verilated::traceEverOn(true)` must be called before creating the VCD trace object. Without it, tracing infrastructure is not initialized.
**How to avoid:** Add `Verilated::traceEverOn(true)` as the first statement in `main()` before any trace setup.
**Warning signs:** VCD file has header section but no value change section.

## Code Examples

Verified patterns from official sources and project conventions:

### Verilator Command Line with --trace
```bash
# Source: Verilator 5.046 documentation (https://veripool.org/guide/latest/exe_verilator.html)
# In simulate.sh, add --trace to the verilator invocation:
verilator --cc "$GENERATED_DIR/$MODULE.v" \
  --exe "$SIM_DIR/tb_$MODULE.cpp" \
  --trace \
  --Mdir "$OBJ_DIR" \
  -CFLAGS "-std=c++17 -I$PLUGIN_ROOT/sim" \
  "${WAIVER_ARGS[@]}"
```
Note: `--trace` is the short form of `--trace-vcd`. Verilator's generated Makefile automatically includes `verilated_vcd_c.cpp` when `--trace` is used.

### C++ Testbench VCD Tracing Hooks (Simple/Combinational Mode)
```cpp
// Source: Verilator documentation + itsembedded.com guide
// Added to testbench-generator.md simple mode template

#include "V<ModuleName>.h"
#include "verilated.h"
#include "verilated_vcd_c.h"    // NEW: VCD tracing header
#include <cstdio>

// ... TestCase struct unchanged ...

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    V<ModuleName>* dut = new V<ModuleName>{ctx};

    // NEW: VCD tracing setup
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("<VCD_PATH>");    // e.g., "../logs/<ModuleName>.vcd"

    vluint64_t sim_time = 0;

    dut->clock = 0;
    dut->reset = 0;

    // ... TestCase array unchanged ...

    for (int i = 0; i < total; i++) {
        // Driver: assign inputs
        dut->io_<inputPort> = tests[i].<input_field>;
        dut->eval();

        // NEW: dump VCD at this test's timestamp
        tfp->dump(sim_time);
        sim_time++;

        // Monitor + Scoreboard + Reporter unchanged
        // ...
    }

    // NEW: close VCD before cleanup
    tfp->close();

    // ... existing cleanup ...
    dut->final();
    delete dut;
    delete ctx;
    delete tfp;

    return (pass == total) ? 0 : 1;
}
```

### C++ Testbench VCD Tracing Hooks (Reference Model/Sequential Mode)
```cpp
// For CPU/sequential modules, dump on each clock toggle:

void tick(V<TopModuleName>* dut, VerilatedVcdC* tfp, vluint64_t& sim_time) {
    dut->clock = 1;
    dut->eval();
    tfp->dump(sim_time);    // dump on rising edge
    sim_time++;

    dut->clock = 0;
    dut->eval();
    tfp->dump(sim_time);    // dump on falling edge
    sim_time++;
}
```

### Python VCD Parser -- Recommended Architecture
```python
#!/usr/bin/env python3
"""
Lightweight VCD parser for ChipAgent debug command.
Extracts signal values at specific timestamps from Verilator-generated VCD files.

Inspired by waveform_mcp (https://github.com/gokeshenzhen/waveform_mcp)
but minimal and self-contained -- no external dependencies.

Usage:
    python3 parse_vcd.py --vcd <path.vcd> --signals sig1 sig2 ... --time <timestamp>
    python3 parse_vcd.py --vcd <path.vcd> --signals sig1 sig2 ... --time <t1> <t2> ...
    python3 parse_vcd.py --vcd <path.vcd> --list-signals

Output: JSON to stdout
"""
import json
import re
import sys
import argparse

class VCDParser:
    """Pure Python VCD parser for targeted signal extraction."""

    def __init__(self, vcd_path: str):
        self.vcd_path = vcd_path
        self._signals = {}       # symbol -> {path, width}
        self._path_to_sym = {}   # full_path -> symbol
        self._transitions = {}   # symbol -> [(time, value), ...]
        self._timescale = "1ns"
        self._parse()

    def _parse(self):
        """Parse VCD file: extract header, signals, and value changes."""
        # Parse header for signal definitions, then value changes
        # Use scope stack to build hierarchical signal names
        # Store transitions as sorted (time, value) pairs per signal
        pass  # Implementation details at Claude's discretion

    def get_value_at_time(self, signal_path: str, timestamp: int) -> str:
        """Return signal value at given timestamp (most recent change <= timestamp)."""
        pass

    def get_signals_at_time(self, signal_paths: list, timestamp: int) -> dict:
        """Return multiple signal values at a given timestamp."""
        pass

    def list_signals(self) -> list:
        """Return all signal paths in the VCD file."""
        pass

    def search_signals(self, keyword: str) -> list:
        """Search for signals matching a keyword (suffix match)."""
        pass

def main():
    parser = argparse.ArgumentParser(description="ChipAgent VCD Parser")
    parser.add_argument("--vcd", required=True, help="Path to VCD file")
    parser.add_argument("--signals", nargs="*", help="Signal names to query")
    parser.add_argument("--time", nargs="*", type=int, help="Timestamps to query")
    parser.add_argument("--list-signals", action="store_true", help="List all signals")
    args = parser.parse_args()

    vcd = VCDParser(args.vcd)

    if args.list_signals:
        print(json.dumps({"signals": vcd.list_signals()}, indent=2))
    elif args.signals and args.time:
        results = {}
        for t in args.time:
            results[str(t)] = vcd.get_signals_at_time(args.signals, t)
        print(json.dumps(results, indent=2))
    else:
        parser.print_help()
        sys.exit(1)

if __name__ == "__main__":
    main()
```

### sim_result.log Parsing Pattern
```python
# Source: Project's own testbench-generator.md output conventions
# The format is stable and controlled by our testbench generator:
#   [TEST N] <op_name>: <inputs> | expect=X got=Y | PASS|FAIL
#   RESULT: PASSED|FAILED X/Y tests

import re

TEST_RE = re.compile(
    r'\[TEST (\d+)\]\s+(\w+):\s*(.*?)\s*\|\s*expect=(\S+)\s+got=(\S+)\s*\|\s*(PASS|FAIL)'
)
RESULT_RE = re.compile(
    r'RESULT:\s+(PASSED|FAILED)\s+(\d+)/(\d+)\s+tests'
)

def parse_sim_log(log_path: str) -> dict:
    """Parse sim_result.log into structured test results."""
    with open(log_path) as f:
        lines = f.readlines()

    tests = []
    summary = None
    for line in lines:
        m = TEST_RE.match(line.strip())
        if m:
            tests.append({
                "test_num": int(m.group(1)),
                "op_name": m.group(2),
                "inputs": m.group(3).strip(),
                "expected": m.group(4),
                "got": m.group(5),
                "status": m.group(6),
            })
        m2 = RESULT_RE.match(line.strip())
        if m2:
            summary = {
                "status": m2.group(1),
                "passed": int(m2.group(2)),
                "total": int(m2.group(3)),
            }
    return {"tests": tests, "summary": summary}
```

### Mapping Failed Tests to Spec Operations
```python
# Source: Project's requirement-parser.md schema
# spec.json operations have "opcode", "name", "expression"
# sim_result.log test lines have "op_name" matching spec operation "name"

def map_failure_to_spec(failed_test: dict, spec: dict) -> dict:
    """Map a failed test back to its spec.json operation."""
    for op in spec.get("operations", []):
        if op["name"] == failed_test["op_name"]:
            return {
                "test_num": failed_test["test_num"],
                "op_name": failed_test["op_name"],
                "opcode": op["opcode"],
                "expression": op["expression"],
                "inputs": failed_test["inputs"],
                "expected": failed_test["expected"],
                "got": failed_test["got"],
            }
    return failed_test  # No matching op found (e.g., edge case test)
```

### Debug Report Structure (Markdown)
```markdown
# Debug Report: <ModuleName>

**Generated:** <timestamp>
**Simulation Result:** FAILED X/Y tests

## Summary

| Metric | Value |
|--------|-------|
| Total Tests | Y |
| Passed | X |
| Failed | Y-X |
| Failure Rate | Z% |

## Failed Tests

### Test N: <OP_NAME>

**Inputs:** a=V1 b=V2 op=V3
**Expected:** X
**Got:** Y

**Signal Trace (VCD @ sim_time=T):**
| Signal | Value |
|--------|-------|
| io_inputA | 0x... |
| io_inputB | 0x... |
| io_op | N |
| io_result | 0x... |

**Spec Reference:** Operation "<OP_NAME>" (opcode N)
  Expression: `<chisel expression from spec.json>`

**Chisel Source:** `chisel-project/src/main/scala/chipagent/<Module>.scala`
  Relevant block: `is(<opcode>.U) { io.result := <expression> }`

### [repeat for each failed test]

## Root Cause Analysis

[Agent-generated analysis mapping common failure patterns across failed tests]

## Fix Suggestions

### Suggestion 1: [Description]
**File:** `chisel-project/src/main/scala/chipagent/<Module>.scala`
**Location:** [line/block reference]
**Current:** `<current code>`
**Suggested:** `<corrected code>`
**Rationale:** [why this fix addresses the failure]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `--trace` flag | `--trace-vcd` flag | Verilator 5.x | `--trace` still works (deprecated alias); using `--trace` is fine for compatibility |
| Manual VCD parsing | waveform_mcp MCP server | 2024-2025 | Full MCP integration is overkill for this project; lightweight parser is better fit |
| Log-only debug | VCD + log cross-reference | This phase | Enables signal-level root cause analysis instead of just expected-vs-actual |

**Deprecated/outdated:**
- `Verilated::commandArgs()` -- replaced by `ctx->commandArgs()` with VerilatedContext pattern. Our testbenches already use the correct pattern.
- `--trace` flag -- technically deprecated in favor of `--trace-vcd`, but `--trace` still works and is more concise. Use `--trace` for brevity.

## Detailed Technical Findings

### VCD File Format (HIGH confidence)
VCD (Value Change Dump) is an ASCII format defined by IEEE 1364-1995. Structure:
1. **Header:** `$date`, `$version`, `$timescale` sections
2. **Variable definitions:** Hierarchical `$scope`/`$upscope` blocks with `$var` declarations mapping signals to short identifier codes
3. **Value changes:** Lines starting with `#<timestamp>` followed by value changes in format `<value><identifier>` (scalar) or `b<binary> <identifier>` (vector)

Verilator-generated VCD files use `$timescale 1ns $end` by default and scope `module TOP`. Signal identifiers are typically 1-2 character ASCII symbols.

Source: [Wikipedia - Value change dump](https://en.wikipedia.org/wiki/Value_change_dump), [ZipCPU VCD guide](https://zipcpu.com/blog/2017/07/31/vcd.html)

### Verilator --trace Integration (HIGH confidence)
Adding `--trace` to the verilator command:
1. Generates additional `*__Trace*.cpp` files in obj_dir
2. The generated Makefile automatically includes `verilated_vcd_c.cpp` -- no manual CFLAGS/LDFLAGS changes needed
3. C++ testbench must include `verilated_vcd_c.h` and make API calls (see Code Examples)
4. No runtime performance impact when trace is compiled in but `tfp->open()` is not called

Source: [Verilator 5.046 documentation](https://veripool.org/guide/latest/exe_verilator.html), [It's Embedded guide](https://itsembedded.com/dhd/verilator_2/)

### waveform_mcp Analysis (HIGH confidence)
Reviewed the [waveform_mcp repository](https://github.com/gokeshenzhen/waveform_mcp). Key takeaways:
- **VCD parser architecture:** Pure Python class with `_signals` dict (symbol -> metadata), `_path_to_sym` dict (path -> symbol), `_transitions` dict (symbol -> time/value pairs), and timescale conversion
- **Key methods:** `get_value_at_time()`, `get_transitions()`, `get_signals_around_time()`, `search_signals()`
- **Analyzer pattern:** Parse log first for error timestamps, then query waveform at those timestamps. Provides both windowed snapshot and full transition history per failure.
- **Design insight:** Pre-fetch all signal transitions once up to the last failure timestamp, then reuse cached data across all errors
- **NOT suitable as dependency:** Full MCP server with FSDB support, Chinese-language code, PyYAML dependency, complex analyzer. Our needs are a strict subset (VCD only, specific timestamp queries, JSON output).

### Python VCD Parser Design (MEDIUM confidence -- architecture at Claude's discretion)
Recommended approach based on waveform_mcp patterns and VCD format:
1. **Single-pass parsing:** Read VCD file once, build signal table and transition lists
2. **Timestamp lookup:** Binary search on sorted transition list for `get_value_at_time()`
3. **Signal search:** Suffix matching on hierarchical names (e.g., search for `io_result` matches `TOP.VALU.io_result`)
4. **CLI interface:** argparse with `--vcd`, `--signals`, `--time`, `--list-signals` flags
5. **Output format:** JSON to stdout for easy consumption by the debug agent via Bash tool
6. **Memory:** For ChipAgent's use case (small modules, <100 tests), loading full VCD is fine. No streaming needed.

### Testbench Modification Scope (HIGH confidence)
The testbench-generator agent (`agents/testbench-generator.md`) needs these additions:
1. **Include:** Add `#include "verilated_vcd_c.h"` to both simple and reference-model templates
2. **Initialization:** Add `Verilated::traceEverOn(true)`, VcdC creation, `trace()`, and `open()` calls
3. **sim_time tracking:** Add `vluint64_t sim_time = 0` and increment after each `eval()`/`dump()`
4. **Dump calls:** `tfp->dump(sim_time)` after each `eval()` in the test loop
5. **Cleanup:** `tfp->close()` before `dut->final()`, `delete tfp` after
6. **VCD path:** Use relative path `../logs/<ModuleName>.vcd` from obj_dir, which resolves to `sim/logs/<Module>.vcd` in workspace

### simulate.sh Modification Scope (HIGH confidence)
The changes to `scripts/simulate.sh` are minimal:
1. Add `--trace` flag to the `verilator --cc` command (line 56 in current file)
2. No other changes needed -- the generated Makefile handles trace source compilation automatically
3. The VCD file path is controlled by the testbench code, not simulate.sh

### Skill/Agent Architecture (HIGH confidence)
Based on established project patterns:
- **Skill:** `skills/debug/SKILL.md` with `disable-model-invocation: true` and `allowed-tools: [Bash, Read, Write, Grep, Glob]`
- **Agent:** `agents/debug-analyzer.md` with `model: inherit` and `tools: [Read, Write, Bash, Grep, Glob]`
- **Flow:** Skill extracts module name -> validates artifacts exist -> reads spec.json + Chisel source + sim_result.log -> calls parse_vcd.py for signal data -> follows agent rules to analyze and produce report

## Open Questions

1. **VCD path relative to simulation binary**
   - What we know: The simulation binary runs from `$OBJ_DIR` which is `workspace/<Module>/sim/obj_dir/`. The VCD file should land at `workspace/<Module>/sim/logs/<Module>.vcd`.
   - What's unclear: Whether Verilator's binary inherits the CWD from `simulate.sh` or whether the Makefile changes CWD during `make -C`.
   - Recommendation: The testbench code should use a path relative to where `simulate.sh` invokes the binary. Since simulate.sh runs `$OBJ_DIR/V$MODULE`, the binary's CWD is the directory from which simulate.sh runs (the shell's CWD, NOT obj_dir). So use `$LOG_DIR/$MODULE.vcd` -- BUT the testbench doesn't know `$LOG_DIR` at compile time. Best approach: hard-code a relative path in the testbench template that the testbench-generator agent fills in based on workspace layout, OR pass VCD path as a testbench environment variable/command-line arg. Simplest: since simulate.sh already has `LOG_DIR`, modify it to pass the VCD path to the binary as a command-line arg, or set an environment variable. Alternatively, the testbench can write to a fixed relative name (e.g., `trace.vcd`) and simulate.sh can `mv` it to the correct location after simulation completes.

2. **Test-to-timestamp mapping for combinational modules**
   - What we know: Each test case increments `sim_time` by 1 in the testbench loop. Test N (1-indexed) maps to sim_time N-1 (0-indexed).
   - What's unclear: Whether we need to dump at sim_time=0 before the first test (initial state).
   - Recommendation: Dump before the loop starts (sim_time=0 as initial state), then dump after each eval. Test 1 is at sim_time=1, Test 2 at sim_time=2, etc. This gives clean 1:1 mapping.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual verification via `/chip-agent:debug` invocation on a module with known failures |
| Config file | none -- manual integration test |
| Quick run command | `python3 scripts/parse_vcd.py --vcd <test.vcd> --list-signals` |
| Full suite command | Manual: generate a module with deliberate errors, simulate, then debug |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SKILL-07 | Debug reads spec.json, Chisel source, sim_result.log from workspace | integration | Manual: `/chip-agent:debug TrivialModule` | Wave 0 |
| SKILL-07 | Debug identifies failed test vectors | integration | Manual: create failing module, run debug | Wave 0 |
| SKILL-07 | Debug maps failures to spec requirements | integration | Manual: verify debug report contains spec operation references | Wave 0 |
| SKILL-07 | Debug maps failures to Chisel logic | integration | Manual: verify debug report references Chisel source lines | Wave 0 |
| SKILL-07 | VCD parser extracts signal values | unit | `python3 scripts/parse_vcd.py --vcd <test.vcd> --signals io_result --time 1` | Wave 0 |
| SKILL-07 | Graceful degradation without VCD | integration | Manual: delete VCD, run debug, verify log-only analysis | Wave 0 |

### Sampling Rate
- **Per task commit:** `python3 scripts/parse_vcd.py --help` (verify script exists and runs)
- **Per wave merge:** Manual end-to-end: generate module -> introduce error in Chisel -> compile -> simulate -> debug
- **Phase gate:** Full end-to-end debug flow produces correct report with fix suggestions

### Wave 0 Gaps
- [ ] `scripts/parse_vcd.py` -- VCD parser script (core deliverable)
- [ ] `skills/debug/SKILL.md` -- debug skill definition
- [ ] `agents/debug-analyzer.md` -- debug agent rules
- [ ] A test VCD file for parser validation (can be generated by running simulate with --trace on TrivialModule)

## Sources

### Primary (HIGH confidence)
- [Verilator 5.046 Documentation - exe_verilator](https://veripool.org/guide/latest/exe_verilator.html) - --trace flag behavior, Makefile integration
- [Verilator 5.046 Documentation - verilating](https://verilator.org/guide/latest/verilating.html) - VCD tracing API, verilated_vcd_c.h usage
- [waveform_mcp GitHub](https://github.com/gokeshenzhen/waveform_mcp) - VCD parser architecture inspiration, analyzer pattern
- Project source: `agents/testbench-generator.md` - existing testbench template structure
- Project source: `scripts/simulate.sh` - current verilator invocation (line 56)
- Project source: existing skills in `skills/*/SKILL.md` - YAML frontmatter and skill patterns

### Secondary (MEDIUM confidence)
- [It's Embedded - Verilator Pt.2](https://itsembedded.com/dhd/verilator_2/) - C++ testbench VCD tracing examples
- [ZipCPU Blog - VCD Format](https://zipcpu.com/blog/2017/07/31/vcd.html) - VCD file structure and writing guide
- [Wikipedia - Value Change Dump](https://en.wikipedia.org/wiki/Value_change_dump) - VCD format specification overview
- [vcdvcd PyPI](https://pypi.org/project/vcdvcd/) - Python VCD parser reference (not used as dependency, but architecture reference)

### Tertiary (LOW confidence)
- None -- all findings verified with primary or secondary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all tools already in project, no new dependencies
- Architecture: HIGH - follows established skill/agent patterns from Phases 6-7
- VCD tracing: HIGH - Verilator's --trace is well-documented with stable API
- VCD parsing: MEDIUM - custom parser architecture at Claude's discretion; VCD format is simple but implementation needs testing
- Pitfalls: HIGH - based on verified Verilator behavior and project-specific knowledge

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable domain, no fast-moving dependencies)
