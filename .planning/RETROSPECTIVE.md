# Retrospective

## Milestone: v1.0 — MVP

**Shipped:** 2026-03-18
**Phases:** 4 | **Plans:** 9

### What Was Built
- Claude Code plugin scaffold with `/chip-agent:generate` slash command
- sbt/Chisel build pipeline compiling to SystemVerilog via FIRRTL/firtool
- NL-to-Chisel subagents (requirement-parser + chisel-generator) with JSON spec contract
- Verilator lint script with waiver files and 3-attempt auto-fix loop
- C++ testbench generation and simulation with formatted verification reports
- End-to-end acceptance test: ALU with 6 operations passing all 12 test cases

### What Worked
- Coarse 4-phase structure kept planning overhead low while covering all 30 requirements
- JSON spec as inter-agent contract gave clean separation between parser and generator
- Per-file linting pattern avoided Verilator MULTITOP issues
- Skill-orchestrated lint (instead of hooks) prevented infinite loop problems
- Waiver file approach for Chisel-generated clock/reset warnings

### What Was Inefficient
- PLUG-01 through PLUG-04 requirements were delivered but never checked off in traceability table
- Phase 3 plan checkboxes in ROADMAP.md were not updated despite summaries existing
- Phase 4 progress row showed "0/2 Not started" even after completion

### Patterns Established
- Combinational modules use single eval() call, no clock cycling
- Testbenches use struct array pattern for test cases
- simulate.sh passes waiver file to Verilator during verilation
- Pipeline stages follow 3-attempt auto-fix pattern consistently

### Key Lessons
- Keep traceability table in sync with actual completion status
- Update ROADMAP progress table as part of plan completion workflow
- Waiver files are essential for Chisel-generated Verilog (clock/reset warnings are ubiquitous)

### Cost Observations
- Sessions: ~5
- Notable: Fast execution — 2 days from project init to full pipeline working
