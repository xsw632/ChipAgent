# Milestones

## v1.1.2 RTL-to-GDS (Shipped: 2026-04-01)

**Phases completed:** 4 phases, 5 plans

**Key accomplishments:**
- PDK environment auto-detection: `/chip-agent:initialize` discovers Yosys, OpenROAD, KLayout versions and nangate45 PDK path; pre-flight validation checks 5 required PDK files
- SDC auto-generation from Verilog: detects sequential vs combinational modules, creates appropriate clock constraints (real clock or virtual + set_max_delay)
- Yosys ASIC synthesis pipeline: Tcl recipe + bash wrapper producing gate-level netlists and synthesis statistics with nangate45 liberty cells
- OpenROAD PnR + GDS export: full floorplan → place → CTS → route flow with auto-die-sizing, conditional CTS skip for combinational modules, and KLayout DEF→GDS merge
- `/chip-agent:pnr` slash command: single command wiring synthesis through GDS with formatted timing/power/area/DRC report and auto-fix retry (up to 3 attempts, 50% clock period relaxation)

**Stats:**
- Timeline: 2 days (2026-03-31 → 2026-04-01)
- LOC: ~8,700 total project
- Git range: feat(09-01) → docs(phase-12)
- New scripts: synth.sh, synth.tcl, pnr.sh, pnr.tcl, def2gds.py, generate_sdc.sh, validate-pdk.sh

---

## v1.1 Refine (Shipped: 2026-03-23)

**Phases completed:** 4 phases, 8 plans, 13 tasks

**Key accomplishments:**
- Per-module workspace isolation (`workspace/<Module>/`) with workspace-aware compile, lint, and simulate scripts (backward-compatible with v1.0 flat layout)
- Five modular slash commands (`/compile`, `/lint`, `/simulate`, `/requirement-parser`, `/testbench`) decomposing the monolithic pipeline
- Refactored `/chip-agent:generate` orchestrator calling agents/scripts directly with workspace paths; removed PostToolUse hook
- Environment detection via `/chip-agent:initialize` producing `.chipagent/env.json` with tool versions and capability flags
- VCD waveform trace generation integrated into simulation pipeline for debug signal analysis
- `/chip-agent:debug` command with Python VCD parser and debug-analyzer agent for structured failure diagnosis

**Stats:**
- Timeline: 1 day (2026-03-20)
- Commits: 40 (59 files changed, 6,956 insertions, 366 deletions)
- LOC: ~2,106 (scripts, skills, agents)
- Git range: feat(05-01) → feat(08-02) + 3 quick tasks

---

## v1.0 MVP (Shipped: 2026-03-18)

**Phases completed:** 4 phases, 9 plans, 0 tasks

**Key accomplishments:**
- Claude Code plugin scaffold with `/chip-agent:generate` slash command and npm packaging
- sbt/Chisel build pipeline compiling to SystemVerilog via FIRRTL/firtool
- NL-to-Chisel subagents parsing hardware descriptions into compilable Chisel code
- Verilator lint infrastructure with waiver files and 3-attempt auto-fix loop
- C++ testbench generation and Verilator simulation with formatted verification reports
- End-to-end acceptance test: ALU with 6 operations (ADD/SUB/AND/OR/XOR/SLT) passing all test cases

**Stats:**
- Timeline: 2 days (2026-03-16 → 2026-03-18)
- Files: 60 files, 7,035 insertions
- LOC: ~2,453
- Git range: initial commit → feat(04-02)

**Known Gaps:**
- PLUG-01, PLUG-02, PLUG-03, PLUG-04: Tracking gaps — features delivered but not checked off in requirements

---

