# Phase 8: Debug Command - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can diagnose simulation failures without manually cross-referencing artifacts. `/chip-agent:debug Foo` reads workspace artifacts, performs failure analysis with VCD signal-level evidence, and produces a structured report with targeted Chisel fix suggestions. Phase also enables VCD trace generation in the simulation pipeline.

</domain>

<decisions>
## Implementation Decisions

### Waveform Integration
- Write a lightweight Python VCD parser in `scripts/parse_vcd.py` — inspired by waveform_mcp's approach but minimal and self-contained (no external MCP dependency)
- Per-failure signal drill-down: for each failed test, query specific signals (inputs, outputs, control) at the failure timestamp
- VCD traces always generated: `simulate.sh` passes `--trace` to Verilator by default
- VCD file stored at `workspace/<Module>/sim/logs/<Module>.vcd`
- Phase 8 modifies `simulate.sh` to add `--trace` flag and updates testbench-generator agent to include VCD tracing hooks (`verilated_vcd_c.h`, `tfp->open/dump/close`)

### Analysis Output
- Debug writes a structured report to `workspace/<Module>/debug/debug_report.md` AND displays a summary in conversation
- Report sections: Summary (pass/fail counts), Failed Tests (per-test: inputs, expected vs actual, signal trace), Root Cause Analysis (mapped to spec + Chisel logic), Fix Suggestions (specific code changes)
- Structured sections format, not narrative

### Fix Suggestion Depth
- Diagnose + suggest specific Chisel code fixes — does NOT auto-apply (user reviews and decides)
- Fix suggestions target Chisel source as primary (the "real" code); if testbench expected values appear wrong, flag it but still point to Chisel
- Full traceability chain: each failed test maps to (1) the spec operation it tests, (2) the Chisel switch/is block implementing it, (3) the signal values at failure time from VCD

### Artifact Scope
- Core 4 artifacts: spec.json, Chisel source (`chipagent/<Module>.scala`), sim_result.log, VCD waveform
- Graceful degradation: missing VCD = fall back to log-only analysis; missing sim_result.log = suggest "run simulate first"; missing spec.json or Chisel source = hard error

### Claude's Discretion
- Python VCD parser internal architecture (classes, functions, data structures)
- Exact debug report markdown formatting
- How to parse and match sim_result.log test lines to spec.json operations
- Skill YAML frontmatter and tool permissions

</decisions>

<specifics>
## Specific Ideas

- Inspired by waveform_mcp (https://github.com/gokeshenzhen/waveform_mcp) for VCD parsing approach, but implemented as a lightweight Python script — not as an MCP server dependency (too heavy, too many tokens)
- VCD parser only needs: read VCD, extract signal values at given timestamps, output JSON — subset of what waveform_mcp does
- Testbench VCD hooks pattern: `#include "verilated_vcd_c.h"`, `VerilatedVcdC* tfp = new VerilatedVcdC; dut->trace(tfp, 99); tfp->open("trace.vcd"); tfp->dump(sim_time); tfp->close();`

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/simulate.sh`: Already handles workspace paths; needs `--trace` flag addition (line 56 verilator call)
- `agents/testbench-generator.md`: Generates C++ testbenches; needs VCD tracing hooks added to its template
- `skills/simulate/SKILL.md`: Wraps simulate.sh; no changes needed (script handles trace internally)
- Existing skill pattern (YAML frontmatter + step-by-step) in `skills/*/SKILL.md`

### Established Patterns
- Workspace path resolution: `workspace/<Module>/` with organized subdirectories
- sim_result.log format: `[TEST N] <op>: <inputs> | expect=X got=Y | PASS|FAIL` with `RESULT: PASSED|FAILED X/Y tests` summary
- spec.json contains `operations[]` with opcode, name, expression — maps directly to test cases
- Skills use `disable-model-invocation: true` for script-wrappers, `model: inherit` for agent-backed skills
- Plugin root detection via `.claude-plugin/plugin.json` ancestor search

### Integration Points
- New skill: `skills/debug/SKILL.md` — agent-backed skill (model: inherit) that reads workspace artifacts
- New agent: `agents/debug-analyzer.md` — reads 4 artifacts, cross-references, produces report
- New script: `scripts/parse_vcd.py` — called by debug agent via Bash tool
- Modified: `scripts/simulate.sh` — add `--trace` to verilator command
- Modified: `agents/testbench-generator.md` — add VCD tracing hooks to generated C++ code
- Report output: `workspace/<Module>/debug/debug_report.md`

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-debug-command*
*Context gathered: 2026-03-20*
