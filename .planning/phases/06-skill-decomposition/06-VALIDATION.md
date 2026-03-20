---
phase: 6
slug: skill-decomposition
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash test scripts (project convention from Phases 1-5) |
| **Config file** | none — Wave 0 creates `scripts/test-phase6.sh` |
| **Quick run command** | `bash scripts/test-phase6.sh` |
| **Full suite command** | `bash scripts/test-phase6.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/test-phase6.sh`
- **After every plan wave:** Run `bash scripts/test-phase6.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 0 | SKILL-01..05 | structural | `bash scripts/test-phase6.sh` | ❌ W0 | ⬜ pending |
| 06-02-01 | 02 | 1 | SKILL-01 | smoke | `bash scripts/test-phase6.sh` (check 1) | ❌ W0 | ⬜ pending |
| 06-02-02 | 02 | 1 | SKILL-02 | smoke | `bash scripts/test-phase6.sh` (check 2) | ❌ W0 | ⬜ pending |
| 06-02-03 | 02 | 1 | SKILL-03 | smoke | `bash scripts/test-phase6.sh` (check 3) | ❌ W0 | ⬜ pending |
| 06-03-01 | 03 | 1 | SKILL-05, SPEC-01 | smoke | `bash scripts/test-phase6.sh` (check 5-6) | ❌ W0 | ⬜ pending |
| 06-03-02 | 03 | 1 | SKILL-04, SPEC-02 | smoke | `bash scripts/test-phase6.sh` (check 4) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/test-phase6.sh` — structural verification for all skills (SKILL.md existence, frontmatter, directory structure, spec.json schema)

*Existing infrastructure (scripts/compile.sh, lint.sh, simulate.sh) covers runtime behavior. Wave 0 adds Phase 6-specific structural tests.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `/chip-agent:compile Foo` produces Verilog | SKILL-01 | Requires Claude Code runtime for slash command invocation | 1. Run `/chip-agent:compile TrivialModule` 2. Check `workspace/TrivialModule/generated/` for .v/.sv files |
| `/chip-agent:lint Foo` reports lint results | SKILL-02 | Requires Claude Code runtime | 1. Run `/chip-agent:lint TrivialModule` 2. Verify lint output shown |
| `/chip-agent:simulate Foo` produces sim_result.log | SKILL-03 | Requires Claude Code runtime | 1. Run `/chip-agent:simulate TrivialModule` 2. Check `workspace/TrivialModule/sim/logs/sim_result.log` |
| `/chip-agent:testbench Foo` reads spec.json | SKILL-04, SPEC-02 | Requires Claude Code runtime + fresh session test | 1. Ensure spec.json exists 2. In fresh session, run `/chip-agent:testbench TrivialModule` 3. Verify testbench generated without conversation context |
| `/chip-agent:requirement-parser` writes spec.json | SKILL-05, SPEC-01 | Requires Claude Code runtime | 1. Run `/chip-agent:requirement-parser a 4-bit adder` 2. Check `workspace/<Module>/spec.json` exists with valid schema |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
