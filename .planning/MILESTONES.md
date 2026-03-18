# Milestones

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

