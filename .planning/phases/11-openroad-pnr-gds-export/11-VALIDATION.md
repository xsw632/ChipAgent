---
phase: 11
slug: openroad-pnr-gds-export
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash scripts + OpenROAD verification |
| **Config file** | none |
| **Quick run command** | `bash scripts/pnr.sh ALU` |
| **Full suite command** | `bash scripts/pnr.sh ALU && bash scripts/pnr.sh Counter8` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/pnr.sh ALU`
- **After every plan wave:** Run `bash scripts/pnr.sh ALU && bash scripts/pnr.sh Counter8`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | PNR-01 | smoke | `bash scripts/pnr.sh ALU && test -f MyDesign/ALU/workspace/pnr/ALU.routed.def` | ❌ W0 | ⬜ pending |
| 11-01-02 | 01 | 1 | PNR-01 | smoke | `bash scripts/pnr.sh Counter8 && test -f MyDesign/Counter8/workspace/pnr/Counter8.routed.def` | ❌ W0 | ⬜ pending |
| 11-01-03 | 01 | 1 | PNR-02 | smoke | `grep -q 'slack' MyDesign/ALU/workspace/pnr/reports/timing.rpt` | ❌ W0 | ⬜ pending |
| 11-01-04 | 01 | 1 | PNR-02 | smoke | `grep -q 'Internal' MyDesign/ALU/workspace/pnr/reports/power.rpt` | ❌ W0 | ⬜ pending |
| 11-01-05 | 01 | 1 | PNR-02 | smoke | `grep -q 'Design area' MyDesign/ALU/workspace/pnr/reports/area.rpt` | ❌ W0 | ⬜ pending |
| 11-01-06 | 01 | 1 | PNR-03 | integration | Run pnr.sh on both modules; neither requires manual die area input | ❌ W0 | ⬜ pending |
| 11-01-07 | 01 | 1 | PNR-03 | integration | `grep -L 'clkbuf' MyDesign/ALU/workspace/pnr/ALU.routed.def` succeeds | ❌ W0 | ⬜ pending |
| 11-01-08 | 01 | 1 | PNR-03 | integration | `grep -q 'clkbuf' MyDesign/Counter8/workspace/pnr/Counter8.routed.def` | ❌ W0 | ⬜ pending |
| 11-01-09 | 01 | 1 | GDS-01 | smoke | `test -f MyDesign/ALU/workspace/pnr/ALU.gds && test -s MyDesign/ALU/workspace/pnr/ALU.gds` | ❌ W0 | ⬜ pending |
| 11-01-10 | 01 | 1 | GDS-01 | smoke | `test -f MyDesign/Counter8/workspace/pnr/Counter8.gds && test -s MyDesign/Counter8/workspace/pnr/Counter8.gds` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/pnr.sh` — main PnR wrapper script
- [ ] `scripts/pnr.tcl` — OpenROAD Tcl PnR recipe
- [ ] `scripts/def2gds.py` — KLayout DEF-to-GDS merge script
- [ ] Both existing modules (ALU, Counter8) must have synthesized netlists in `workspace/pnr/` (already present from Phase 10)
- [ ] Both existing modules must have SDC files in `workspace/pnr/` (already present from Phase 9/10)

*Existing infrastructure covers framework needs.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
