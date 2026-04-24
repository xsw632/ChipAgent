---
phase: 18-chipyard-environment-detection
verified: 2026-04-14T09:20:00Z
status: passed
score: 11/11 must-haves verified
overrides_applied: 0
re_verification: false
---

# Phase 18: Chipyard Environment Detection Verification Report

**Phase Goal:** Users can discover Chipyard and RISCV toolchain availability through the existing initialize command
**Verified:** 2026-04-14T09:20:00Z
**Status:** PASSED
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

ROADMAP Success Criteria (contract) and PLAN frontmatter truths combined and deduplicated:

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Running `/chip-agent:initialize` with Chipyard installed writes `can_chipyard: true` and Chipyard path to `.chipagent/env.json` | VERIFIED | `bash scripts/detect-env.sh` produces env.json with `can_chipyard: true`, `chipyard.path: "/home/mingzhenjia/Desktop/chipyard"`, `chipyard.installed: true` |
| 2 | Running `/chip-agent:initialize` without Chipyard writes `can_chipyard: false` without errors | VERIFIED | `HOME=/tmp/testabsent_* bash scripts/detect-env.sh` completes exit 0 with `chipyard.installed: false`, `can_chipyard: false`, no errors |
| 3 | `detect-env.sh` detects and reports Chipyard directory and RISCV toolchain path when present | VERIFIED | Chipyard detected at `/home/mingzhenjia/Desktop/chipyard` via `build.sbt` + `generators/chipyard/src/main/scala` markers; RISCV at `.conda-env/riscv-tools` via `riscv64-unknown-elf-gcc` |
| 4 | Environment validation checks for `build.sbt` existence and RISCV toolchain binaries in detected Chipyard path | VERIFIED | Line 147: `[ -f "$candidate/build.sbt" ] && [ -d "$candidate/generators/chipyard/src/main/scala" ]`; Line 164: `[ -f "$candidate/bin/riscv64-unknown-elf-gcc" ]` |
| 5 | `can_chipyard` flag is true only when both Chipyard AND RISCV are found | VERIFIED | Lines 204-207: `if [ "$CHIPYARD_INSTALLED" = "true" ] && [ "$RISCV_INSTALLED" = "true" ]; then CAN_CHIPYARD="true"`. Absent test confirmed `can_chipyard: false` when Chipyard missing despite RISCV present at `/opt/riscv` |
| 6 | `env.json` contains a chipyard section with installed, path, riscv_installed, riscv_path fields | VERIFIED | `jq '.chipyard | has("installed") and has("path") and has("riscv_installed") and has("riscv_path")'` returns `true` |
| 7 | `env.json` capabilities includes can_chipyard boolean | VERIFIED | `jq '.capabilities | has("can_chipyard")'` returns `true` |
| 8 | Stdout summary shows Chipyard and RISCV lines with [OK]/[MISSING] pattern | VERIFIED | Lines 450-460 implement both patterns. Live run shows `Chipyard:   [OK] /home/mingzhenjia/Desktop/chipyard` and `RISCV:      [OK] ...` |
| 9 | Script does not crash when Chipyard or RISCV are absent | VERIFIED | `HOME=/tmp/testabsent_*` run exits 0, outputs `[MISSING]` for Chipyard, no stderr |
| 10 | Initialize skill step 5 summary includes Chipyard and RISCV status display | VERIFIED | SKILL.md line 55: `**Can Chipyard** (requires Chipyard + RISCV toolchain): whether Chipyard RTL generation is possible` |
| 11 | Initialize skill shows Chipyard and RISCV install guidance when missing | VERIFIED | SKILL.md line 69: Chipyard clone URL + ReadTheDocs link; line 70: RISCV setup-tools.sh reference |

**Score:** 11/11 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/detect-env.sh` | Chipyard + RISCV detection, can_chipyard capability, JSON output with chipyard section | VERIFIED | 504 lines, substantive implementation. `CHIPYARD_CANDIDATES` (2 matches), `RISCV_CANDIDATES` (2 matches), `can_chipyard` (3 matches), `generators/chipyard/src/main/scala` (1 match), `riscv64-unknown-elf-gcc` (1 match), `build.sbt` (1 match) |
| `skills/initialize/SKILL.md` | Updated initialize skill with Chipyard/RISCV status and install guidance | VERIFIED | 81 lines. 5 Chipyard mentions, 4 RISCV mentions. Contains "Can Chipyard" capability, chipyard.readthedocs.io link, scripts/setup-tools.sh reference |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `scripts/detect-env.sh` | `.chipagent/env.json` | jq -n / heredoc write | WIRED | Both jq (line 215) and heredoc (line 313) paths produce identical chipyard section with 4 fields |
| `scripts/detect-env.sh` | stdout | echo summary lines | WIRED | Lines 450-460 output Chipyard/RISCV status; lines 496-500 output Chipyard capability in Capabilities section |
| `skills/initialize/SKILL.md` | `.chipagent/env.json` | skill reads chipyard section | WIRED | SKILL.md references chipyard, can_chipyard, Chipyard, RISCV consistently with env.json schema |
| `skills/initialize/SKILL.md` | `scripts/detect-env.sh` | skill invokes script in step 2 | WIRED | Step 2 instructs Claude to run `<plugin-root>/scripts/detect-env.sh` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `scripts/detect-env.sh` (jq output) | `chipyard_installed`, `chipyard_path`, `riscv_installed`, `riscv_path`, `can_chipyard` | Filesystem candidate checks (build.sbt, generators dir, riscv64-unknown-elf-gcc) | FLOWING | Live run: detected real Chipyard at `/home/mingzhenjia/Desktop/chipyard` with valid build.sbt, real RISCV at `.conda-env/riscv-tools` with real `riscv64-unknown-elf-gcc` |
| `scripts/detect-env.sh` (heredoc fallback) | Same variables | Same source | FLOWING | Parallel path using bash variable interpolation produces same structure |
| `skills/initialize/SKILL.md` | N/A (instruction file) | env.json consumed during skill execution | N/A | Instruction file -- data flow is Claude reads env.json and presents results |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| detect-env.sh syntax check | `bash -n scripts/detect-env.sh` | "SYNTAX OK" | PASS |
| Chipyard detection with real install | `bash scripts/detect-env.sh 2>/dev/null; jq -r '.chipyard.installed' .chipagent/env.json` | `true` | PASS |
| RISCV detection with real install | `bash scripts/detect-env.sh 2>/dev/null; jq -r '.chipyard.riscv_installed' .chipagent/env.json` | `true` | PASS |
| Absent scenario: chipyard.installed=false | `HOME=/tmp/testabsent_* bash scripts/detect-env.sh 2>/dev/null; jq -r '.chipyard.installed' .chipagent/env.json` | `false` | PASS |
| Absent scenario: can_chipyard=false | `HOME=/tmp/testabsent_* bash scripts/detect-env.sh 2>/dev/null; jq -r '.capabilities.can_chipyard' .chipagent/env.json` | `false` | PASS |
| Existing capabilities unchanged | `bash scripts/detect-env.sh 2>/dev/null; jq -r '.capabilities.can_compile,.capabilities.can_pnr,.capabilities.can_gds' .chipagent/env.json` | `true\|true\|true` | PASS |
| Stdout Chipyard line | `bash scripts/detect-env.sh 2>&1 \| grep 'Chipyard:' \| head -1` | `Chipyard:   [OK] /home/mingzhenjia/Desktop/chipyard` | PASS |
| Capabilities section includes Chipyard | `bash scripts/detect-env.sh 2>&1 \| grep 'Capabilities' -A 10 \| grep 'Chipyard'` | `Chipyard:   YES` | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| ENV-01 | 18-02 | `/chip-agent:initialize` detects Chipyard installation, validates build.sbt and RISCV toolchain existence | SATISFIED | SKILL.md step 2 invokes detect-env.sh which checks build.sbt + generators dir + riscv64-unknown-elf-gcc; step 5 presents results including Can Chipyard capability |
| ENV-02 | 18-01 | Environment detection results written to `.chipagent/env.json` including Chipyard path, RISCV path, and `can_chipyard` capability flag | SATISFIED | env.json confirmed to contain `chipyard.installed`, `chipyard.path`, `chipyard.riscv_installed`, `chipyard.riscv_path`, and `capabilities.can_chipyard` |
| ENV-03 | 18-01 | `detect-env.sh` script extended with Chipyard directory and RISCV toolchain detection logic | SATISFIED | detect-env.sh lines 137-169 implement Chipyard + RISCV detection with candidate chains, build.sbt marker, and riscv64-unknown-elf-gcc binary check |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | - | - | - | No anti-patterns detected |

### Human Verification Required

No items require human verification. All must-haves are programmatically verifiable bash script behavior:
- Script output is text-based and fully captured by automated checks
- env.json content is machine-readable and validated via jq
- SKILL.md is an instruction file validated by grep patterns
- No UI rendering, no external service calls, no visual inspection needed

### Gaps Summary

No gaps found. All 11 truths verified, both artifacts substantive and wired, all 4 key links confirmed, all 3 requirements (ENV-01, ENV-02, ENV-03) satisfied. Behavioral spot-checks passed (8/8). Anti-pattern scan clean.

---

_Verified: 2026-04-14T09:20:00Z_
_Verifier: Claude (gsd-verifier)_
