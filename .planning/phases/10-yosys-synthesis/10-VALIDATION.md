---
phase: 10
slug: yosys-synthesis
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-31
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash scripts + OpenROAD verification |
| **Config file** | none — Wave 0 creates scripts |
| **Quick run command** | `bash scripts/synth.sh ALU` |
| **Full suite command** | `bash scripts/synth.sh ALU && bash scripts/synth.sh Counter8` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/synth.sh ALU`
- **After every plan wave:** Run `bash scripts/synth.sh ALU && bash scripts/synth.sh Counter8` + OpenROAD parse test
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | SYN-01 (comb) | smoke | `bash scripts/synth.sh ALU && test -f MyDesign/ALU/workspace/pnr/ALU.synth.v` | ❌ W0 | ⬜ pending |
| 10-01-02 | 01 | 1 | SYN-01 (seq) | smoke | `bash scripts/synth.sh Counter8 && test -f MyDesign/Counter8/workspace/pnr/Counter8.synth.v` | ❌ W0 | ⬜ pending |
| 10-01-03 | 01 | 1 | SYN-01 (compat) | integration | `openroad -no_init -exit -cmd "read_liberty ...; read_lef ...; read_verilog <netlist>; link_design <Module>"` | ❌ W0 | ⬜ pending |
| 10-01-04 | 01 | 1 | SYN-03 | smoke | `grep 'Number of cells:' workspace/pnr/reports/synth_stat.txt && grep 'Chip area' workspace/pnr/reports/synth_stat.txt` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/synth.sh` — main synthesis wrapper script
- [ ] `scripts/synth.tcl` — Yosys Tcl synthesis recipe
- [ ] Both existing modules (ALU, Counter8) must have compiled Verilog in `workspace/generated/` (already present from Phase 9)

*Existing infrastructure covers framework needs — no new test framework required.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| *None* | — | — | — |

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
