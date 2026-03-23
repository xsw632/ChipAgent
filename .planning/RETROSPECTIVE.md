# Retrospective

## Milestone: v1.1 — Refine

**Shipped:** 2026-03-23
**Phases:** 4 | **Plans:** 8

### What Was Built
- Per-module workspace isolation (`workspace/<Module>/`) with compile, lint, simulate scripts accepting workspace paths
- Five modular slash commands decomposing the monolithic pipeline into standalone stages
- Refactored `/chip-agent:generate` orchestrator wiring sub-skills with workspace-aware paths
- Environment detection (`/chip-agent:initialize`) producing `.chipagent/env.json` with tool versions and capability flags
- VCD waveform trace generation integrated into simulation pipeline
- `/chip-agent:debug` command with Python VCD parser and debug-analyzer agent

### What Worked
- Spec-file communication (Option C) cleanly decoupled pipeline stages from conversation context
- Runtime plugin root detection via `.claude-plugin/plugin.json` ancestor search solved env var interpolation issues
- Single-responsibility skill design (compile ≠ lint ≠ simulate) made orchestrator composition straightforward
- Removing PostToolUse hook eliminated spurious sbt compilations and infinite loop risk
- Python stdlib-only VCD parser ensured zero-install portability

### What Was Inefficient
- ROADMAP.md plan checkboxes still fell out of sync (phases 5, 6, 8 showed `[ ]` despite having SUMMARY files)
- REQUIREMENTS.md traceability table showed "In Progress" for WKSP-01/02 despite being complete in the checkbox list
- Phase 7 Plan 01 took 34min (outlier) due to PostToolUse hook removal requiring careful analysis of hook interactions

### Patterns Established
- Workspace convention: `workspace/<Module>/generated/`, `workspace/<Module>/sim/logs/`
- Script backward compatibility: no args = v1.0 flat mode, positional arg = workspace mode
- Agent-backed skills: skill handles file I/O that agent cannot do directly
- Waiver file fallback chain: per-module → global → empty
- VCD lifecycle: traceEverOn → trace(tfp,99) → open → dump per eval → close

### Key Lessons
- Traceability tracking remains the weakest part of the workflow — plan/requirement checkboxes drift
- PostToolUse hooks with broad triggers are dangerous in automated pipelines (removed, not fixed)
- jq-with-heredoc-fallback is a reliable portable JSON assembly pattern

### Cost Observations
- Sessions: ~3
- Notable: All 8 plans executed in a single day (2026-03-20); 77 min total execution

---

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
