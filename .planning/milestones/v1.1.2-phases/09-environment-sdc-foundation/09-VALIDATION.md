---
phase: 9
slug: environment-sdc-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-31
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash scripts + jq assertions |
| **Config file** | none — scripts are self-contained |
| **Quick run command** | `bash scripts/detect-env.sh && jq '.tools.yosys.installed' .chipagent/env.json` |
| **Full suite command** | `bash scripts/detect-env.sh && bash scripts/validate-pdk.sh && bash scripts/generate_sdc.sh ALU` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/detect-env.sh && cat .chipagent/env.json`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | ENV-01 | smoke | `bash scripts/detect-env.sh && jq '.tools.yosys.installed, .tools.openroad.installed, .tools.klayout.installed' .chipagent/env.json` | ❌ W0 | ⬜ pending |
| 09-01-02 | 01 | 1 | ENV-01 | smoke | `jq '.pdk.nangate45.installed' .chipagent/env.json` | ❌ W0 | ⬜ pending |
| 09-01-03 | 01 | 1 | ENV-01 | smoke | `jq '.capabilities.can_synthesize, .capabilities.can_pnr, .capabilities.can_gds' .chipagent/env.json` | ❌ W0 | ⬜ pending |
| 09-02-01 | 02 | 1 | ENV-02 | unit | `bash scripts/validate-pdk.sh && echo PASS` | ❌ W0 | ⬜ pending |
| 09-02-02 | 02 | 1 | ENV-02 | negative | `NANGATE45_DIR=/nonexistent bash scripts/validate-pdk.sh; [ $? -ne 0 ] && echo PASS` | ❌ W0 | ⬜ pending |
| 09-03-01 | 03 | 2 | SYN-02 | smoke | `bash scripts/generate_sdc.sh ALU && grep create_clock workspace/pnr/constraint.sdc` | ❌ W0 | ⬜ pending |
| 09-03-02 | 03 | 2 | SYN-02 | smoke | `bash scripts/generate_sdc.sh Decoder3to8 && grep set_max_delay workspace/pnr/constraint.sdc` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Compile ALU and Decoder3to8 Verilog via `scripts/compile.sh` (needed for SDC generation tests)
- [ ] No new test framework needed — bash scripts + jq suffice

*Existing infrastructure covers most phase requirements. Only pre-compiled Verilog is needed for SYN-02 tests.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Initialize skill SKILL.md documents new env.json fields | ENV-01 | Documentation review | Read `skills/initialize/SKILL.md` and verify new fields are documented |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
