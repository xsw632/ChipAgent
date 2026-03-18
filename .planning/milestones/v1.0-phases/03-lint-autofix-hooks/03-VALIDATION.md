---
phase: 3
slug: lint-autofix-hooks
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell-based integration tests (bash scripts) |
| **Config file** | None — tests are bash scripts |
| **Quick run command** | `scripts/lint.sh` |
| **Full suite command** | `scripts/compile.sh && scripts/lint.sh` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `scripts/lint.sh`
- **After every plan wave:** Run `scripts/compile.sh && scripts/lint.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | LINT-01 | integration | `scripts/lint.sh; echo $?` | No — Wave 0 | ⬜ pending |
| 3-01-02 | 01 | 1 | LINT-04 | integration | `verilator --lint-only generated/ALU.v; echo $?` | No — Wave 0 | ⬜ pending |
| 3-01-03 | 01 | 1 | LINT-05 | integration | `test -f generated/lint-warnings.log` | No — Wave 0 | ⬜ pending |
| 3-01-04 | 01 | 1 | HOOK-01 | smoke | `jq '.hooks.PostToolUse' hooks/hooks.json` | Yes (needs rewrite) | ⬜ pending |
| 3-01-05 | 01 | 1 | HOOK-02 | smoke | `grep 'CLAUDE_PLUGIN_ROOT' hooks/hooks.json` | Yes | ⬜ pending |
| 3-01-06 | 01 | 1 | HOOK-03 | manual+smoke | Verify only compile hook in PostToolUse | N/A | ⬜ pending |
| 3-01-07 | 01 | 1 | LINT-02 | manual | N/A — validated via pipeline execution | N/A | ⬜ pending |
| 3-01-08 | 01 | 1 | LINT-03 | manual | N/A — validated via pipeline execution | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/lint.sh` — Verilator lint wrapper script
- [ ] `generated/chisel-warnings.vlt` — waiver file for known Chisel warnings
- [ ] `scripts/test-phase3.sh` — integration test for lint pipeline

*These are created in Wave 1 as part of the lint script and hook configuration tasks.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Lint errors trigger auto-fix loop (max 3 attempts) | LINT-02 | Requires skill orchestration via generate.md pipeline | Run `/chip-agent:generate` with a known-bad module, verify lint-fix-relint cycle |
| After 3 failures, pipeline stops | LINT-03 | Requires skill orchestration and repeated failures | Run `/chip-agent:generate` with unfixable lint error, verify pipeline stops after 3 attempts |
| No infinite loops from hooks | HOOK-03 | Requires observing hook behavior during actual tool usage | Edit a Scala file, verify compile hook fires once, verify no lint hook chain |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
