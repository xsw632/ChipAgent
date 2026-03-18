---
phase: 2
slug: nl-parsing-chisel-generation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell-based integration tests (no ScalaTest/ChiselTest) |
| **Config file** | None — compilation scripts serve as test harness |
| **Quick run command** | `scripts/compile.sh` |
| **Full suite command** | `scripts/compile.sh && test -f generated/ALU.v` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `scripts/compile.sh`
- **After every plan wave:** Run `scripts/compile.sh && test -f generated/ALU.v`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | PARSE-01 | manual | N/A — validated by downstream compilation | N/A | ⬜ pending |
| 02-01-02 | 01 | 1 | PARSE-02 | manual | N/A — validated by downstream compilation | N/A | ⬜ pending |
| 02-01-03 | 01 | 1 | PARSE-03 | integration | `scripts/compile.sh && test -f generated/ALU.v` | ❌ W0 | ⬜ pending |
| 02-02-01 | 02 | 1 | GEN-01 | integration | `scripts/compile.sh` | ✅ | ⬜ pending |
| 02-02-02 | 02 | 1 | GEN-02 | integration | `grep "package chipagent" chisel-project/src/main/scala/chipagent/ALU.scala` | ❌ W0 | ⬜ pending |
| 02-02-03 | 02 | 1 | GEN-03 | integration | `grep "ALU" chisel-project/src/main/scala/chipagent/Generate.scala` | ✅ | ⬜ pending |
| 02-02-04 | 02 | 1 | GEN-04 | integration | `scripts/compile.sh` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/test-phase2.sh` — end-to-end test: compile ALU, verify output files exist, check package conventions
- [ ] No ScalaTest infrastructure needed — compilation success IS the test for this phase

*Existing `scripts/compile.sh` covers GEN-01, GEN-03, GEN-04. Wave 0 adds ALU-specific checks.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| NL input produces structured JSON spec | PARSE-01 | Agent output is ephemeral (in-conversation) | Invoke `/chip-agent:generate` with ALU description, verify JSON spec appears |
| Spec contains module name, ports, operations, constraints | PARSE-02 | Agent output format validation | Check JSON output has all required fields |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
