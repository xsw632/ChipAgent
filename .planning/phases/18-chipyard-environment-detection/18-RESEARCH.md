# Phase 18: Chipyard Environment Detection - Research

**Researched:** 2026-04-14
**Domain:** Bash environment detection, Chipyard/RISCV toolchain discovery
**Confidence:** HIGH

## Summary

Phase 18 extends the existing `detect-env.sh` script and `/chip-agent:initialize` skill to discover Chipyard and RISCV toolchain installations. The existing codebase has mature patterns for directory detection (candidate arrays with file-based validation), tool detection (`detect_tool` function), and JSON assembly (jq with heredoc fallback). The implementation is straightforward: add two new detection blocks (Chipyard directory, RISCV toolchain) following the exact same pattern as the existing sky130hd/ORFS detection, compute a `can_chipyard` capability flag, and extend the JSON output.

**Primary recommendation:** Follow the existing sky130hd/ORFS detection pattern exactly. Add Chipyard detection block between the ORFS block and capability computation. The marker file for Chipyard validation is `build.sbt` + `generators/chipyard/src/main/scala` (NOT `generators/src/main/scala` as stated in CONTEXT.md -- verified on actual installation).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Candidate directory chain: `CHIPYARD_DIR` env var -> `~/chipyard` -> `/opt/chipyard` -- consistent with existing sky130hd/ORFS detection pattern
- Validate installation by checking for `build.sbt` + Chipyard marker (`generators/src/main/scala` exists)
- Docker-based Chipyard deferred to DCK-01/DCK-02 per REQUIREMENTS.md
- Report path only (no version -- Chipyard has no single version command)
- Candidate chain: `RISCV` env var -> `<chipyard>/.conda-env/` -> `<chipyard>/riscv-tools` -> `/opt/riscv`
- Validate via `riscv64-unknown-elf-gcc` binary presence (primary cross-compiler)
- No separate firtool detection (already auto-managed by Chisel)
- Report installed/path only (no version -- varies across toolchain builds)
- Note: Chipyard's RISCV toolchain is typically in `.conda-env/` directory within Chipyard installation
- `can_chipyard` = Chipyard found AND RISCV found (both required for RTL generation)
- New top-level `chipyard` section in env.json (path, installed, riscv_path, riscv_installed) + add `can_chipyard` to capabilities
- Initialize skill presents brief Chipyard install guidance when missing (link to Chipyard docs)
- detect-env.sh summary follows existing `[OK]/[MISSING]` pattern for Chipyard and RISCV lines

### Claude's Discretion
- Exact jq/heredoc JSON formatting for new chipyard section
- Specific stdout summary formatting for Chipyard/RISCV lines
- Install guidance wording and link placement

### Deferred Ideas (OUT OF SCOPE)
- Docker-based Chipyard execution (DCK-01, DCK-02)
- Chipyard version reporting (no standard version command available)
- RISCV toolchain version reporting (varies across builds)
- Separate firtool detection for Chipyard (auto-managed)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ENV-01 | `/chip-agent:initialize` detects Chipyard installation (local path vs Docker), validates `build.sbt` and RISCV toolchain existence | Chipyard directory detection block with candidate chain + marker file validation; RISCV toolchain detection via `riscv64-unknown-elf-gcc` binary presence |
| ENV-02 | Environment detection results written to `.chipagent/env.json` including Chipyard path, RISCV path, and `can_chipyard` capability flag | Extend jq/heredoc JSON assembly with new `chipyard` section; add `can_chipyard` to capabilities |
| ENV-03 | `detect-env.sh` script extended with Chipyard directory and RISCV toolchain detection logic | Two new detection blocks following existing sky130hd/ORFS pattern; stdout summary with `[OK]/[MISSING]` lines |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 4+ | Shell scripting | Already used by detect-env.sh; project standard for all scripts |
| jq | 1.6+ | JSON assembly | Already used in detect-env.sh for JSON output formatting |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| heredoc | built-in | JSON fallback | When jq is not available (already handled in existing script) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq + heredoc fallback | Pure bash JSON assembly | jq produces valid JSON; heredoc is error-prone for complex nesting. Keep dual-path approach. |

**Installation:** No new packages required. All dependencies already in use by detect-env.sh.

## Architecture Patterns

### Recommended Project Structure
```
scripts/
  detect-env.sh    # ADD: Chipyard + RISCV detection blocks (lines ~122-165)
  _common.sh       # NO CHANGES (shared path resolution)
skills/
  initialize/
    SKILL.md        # UPDATE: extend step 5 summary with Chipyard info + install guidance
```

### Pattern 1: Candidate Directory Detection (existing, reuse directly)
**What:** Check multiple candidate paths in priority order, validate each with a file-existence test.
**When to use:** For any tool/directory that could be installed in multiple locations.
**Example:**
```bash
# Source: detect-env.sh lines 89-103 (existing sky130hd detection)
SKY130HD_INSTALLED="false"
SKY130HD_DIR=""
SKY130HD_CANDIDATES=(
  "${SKY130HD_DIR_OVERRIDE:-}"
  "${ORFS_DIR:-}/flow/platforms/sky130hd"
  "$HOME/OpenROAD-flow-scripts/flow/platforms/sky130hd"
  "/opt/OpenROAD-flow-scripts/flow/platforms/sky130hd"
)
for candidate in "${SKY130HD_CANDIDATES[@]}"; do
  if [ -n "$candidate" ] && [ -f "$candidate/lib/sky130_fd_sc_hd__tt_025C_1v80.lib" ]; then
    SKY130HD_INSTALLED="true"
    SKY130HD_DIR="$candidate"
    break
  fi
done
```

### Pattern 2: jq JSON Assembly with Variables (existing, extend)
**What:** Pass shell variables into jq via `--arg`/`--argjson`, build JSON object.
**When to use:** Writing structured JSON from bash scripts.
**Example:**
```bash
# Source: detect-env.sh lines 176-260 (existing jq assembly)
jq -n \
  --argjson orfs_installed "$ORFS_INSTALLED" \
  --arg orfs_path "$ORFS_DIR_DETECTED" \
  --arg orfs_flow_path "$ORFS_FLOW_PATH" \
  '{
    orfs: {
      installed: $orfs_installed,
      path: $orfs_path,
      flow_path: $orfs_flow_path
    }
  }'
```

### Pattern 3: Stdout Status Summary (existing, extend)
**What:** Print `[OK]` or `[MISSING]` with path/version info for each detected component.
**When to use:** User-facing environment summary.
**Example:**
```bash
# Source: detect-env.sh lines 374-384 (existing PDK/ORFS summary)
if [ "$ORFS_INSTALLED" = "true" ]; then
  echo "ORFS:       [OK] $ORFS_DIR_DETECTED"
else
  echo "ORFS:       [MISSING]"
fi
```

### Anti-Patterns to Avoid
- **Using `set -e` in detect-env.sh:** Missing tools must produce "installed: false", not crash the script. The existing script explicitly avoids `set -e` (comment on line 4). [VERIFIED: detect-env.sh line 4]
- **Hardcoding paths:** Use candidate arrays with env var overrides, matching existing pattern.
- **Detecting version for Chipyard/RISCV:** CONTEXT.md explicitly defers version reporting. Both tools lack reliable single-command version output.
- **Breaking existing env.json schema:** New `chipyard` section must be additive; existing sections must remain unchanged.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON generation | String concatenation | jq with --arg/--argjson | Handles quoting, escaping, proper formatting |
| Tool detection | Custom binary search | `command -v` or file existence test | Existing `detect_tool` function and pattern |
| RISCV binary check | Parsing `ls` output | `[ -f "$path/bin/riscv64-unknown-elf-gcc" ]` | Simple file existence test, no parsing needed |

**Key insight:** The entire phase is about extending existing patterns, not creating new infrastructure. Every detection block in detect-env.sh follows the same template.

## Common Pitfalls

### Pitfall 1: Wrong Chipyard Marker File
**What goes wrong:** CONTEXT.md specifies `generators/src/main/scala` as the Chipyard marker, but the actual path is `generators/chipyard/src/main/scala`.
**Why it happens:** Chipyard's submodule structure places Scala sources under `generators/<project>/src/main/scala`, not `generators/src/main/scala` directly.
**How to avoid:** Validate with `build.sbt` existence as the primary marker (simpler, always at root). Use `generators/chipyard/src/main/scala` as secondary confirmation if desired. On the actual installation at `~/Desktop/chipyard`: `build.sbt` EXISTS, `generators/src/main/scala` MISSING, `generators/chipyard/src/main/scala` EXISTS. [VERIFIED: filesystem check on this machine]
**Warning signs:** If `generators/src/main/scala` check fails but `build.sbt` exists, the Chipyard installation is likely valid.

### Pitfall 2: Empty ~/chipyard Directory
**What goes wrong:** `~/chipyard` exists on this machine but is NOT a real Chipyard installation (only contains `.devcontainer/`).
**Why it happens:** Someone created the directory but never cloned Chipyard into it.
**How to avoid:** Always validate with file existence checks (`build.sbt`), not just directory existence. The candidate chain must check `[ -f "$candidate/build.sbt ]`, not just `[ -d "$candidate" ]`. [VERIFIED: `ls ~/chipyard/` shows only `.devcontainer`]
**Warning signs:** A candidate directory exists but has no `build.sbt` at its root.

### Pitfall 3: RISCV Path Candidates Depend on Chipyard Path
**What goes wrong:** The RISCV candidate chain references `$CHIPYARD_DIR` (which may be empty), causing false negatives.
**Why it happens:** RISCV toolchain detection must run AFTER Chipyard detection because some candidates are relative to the Chipyard directory.
**How to avoid:** Place RISCV detection block AFTER Chipyard detection block. Use the resolved `CHIPYARD_DIR_DETECTED` variable (or empty string if not found) in RISCV candidates. [VERIFIED: existing pattern in chipyard-rtl/SKILL.md lines 77-84]
**Warning signs:** RISCV detection runs before Chipyard detection, or references undefined variables.

### Pitfall 4: Heredoc Fallback JSON for Chipyard Section
**What goes wrong:** The heredoc fallback in detect-env.sh (lines 262-306) must be updated in sync with the jq path. Missing a field in the heredoc but present in jq (or vice versa) causes schema divergence.
**Why it happens:** Dual JSON assembly paths require maintaining two parallel representations.
**How to avoid:** Add chipyard section to BOTH the jq block AND the heredoc block. Test both paths (with and without jq installed). [VERIFIED: detect-env.sh has both paths at lines 175-260 (jq) and 262-306 (heredoc)]

### Pitfall 5: jq Boolean Type Coercion
**What goes wrong:** Using `--arg` instead of `--argjson` for boolean values produces string `"true"` instead of JSON boolean `true`.
**Why it happens:** In jq, `--arg` always produces a string; `--argjson` parses the value as JSON.
**How to avoid:** Use `--argjson` for all boolean and numeric values (`CHIPYARD_INSTALLED`, `RISCV_INSTALLED`, `CAN_CHIPYARD`). Use `--arg` for strings (paths). [VERIFIED: detect-env.sh uses this pattern correctly throughout]

## Code Examples

### Chipyard Detection Block (follows existing pattern)
```bash
# Insert after ORFS detection (line ~121), before Docker detection

# Detect Chipyard
CHIPYARD_INSTALLED="false"
CHIPYARD_DIR_DETECTED=""
CHIPYARD_CANDIDATES=(
  "${CHIPYARD_DIR:-}"
  "$HOME/chipyard"
  "$HOME/Desktop/chipyard"
  "/opt/chipyard"
)
for candidate in "${CHIPYARD_CANDIDATES[@]}"; do
  if [ -n "$candidate" ] && [ -f "$candidate/build.sbt" ] && [ -d "$candidate/generators/chipyard/src/main/scala" ]; then
    CHIPYARD_INSTALLED="true"
    CHIPYARD_DIR_DETECTED="$candidate"
    break
  fi
done
```

### RISCV Toolchain Detection Block
```bash
# Insert after Chipyard detection

# Detect RISCV toolchain
RISCV_INSTALLED="false"
RISCV_PATH=""
RISCV_CANDIDATES=(
  "${RISCV:-}"
  "${CHIPYARD_DIR_DETECTED:+$CHIPYARD_DIR_DETECTED/.conda-env/riscv-tools}"
  "${CHIPYARD_DIR_DETECTED:+$CHIPYARD_DIR_DETECTED/riscv-tools}"
  "/opt/riscv"
)
for candidate in "${RISCV_CANDIDATES[@]}"; do
  if [ -n "$candidate" ] && [ -f "$candidate/bin/riscv64-unknown-elf-gcc" ]; then
    RISCV_INSTALLED="true"
    RISCV_PATH="$candidate"
    break
  fi
done
```

### Capability Flag Computation
```bash
# Add after existing capability computations (line ~168)

CAN_CHIPYARD="false"
if [ "$CHIPYARD_INSTALLED" = "true" ] && [ "$RISCV_INSTALLED" = "true" ]; then
  CAN_CHIPYARD="true"
fi
```

### jq JSON Extension (add to existing jq call)
```bash
# Add these arguments to the existing jq -n call:
  --argjson chipyard_installed "$CHIPYARD_INSTALLED" \
  --arg chipyard_path "$CHIPYARD_DIR_DETECTED" \
  --argjson riscv_installed "$RISCV_INSTALLED" \
  --arg riscv_path "$RISCV_PATH" \
  --argjson can_chipyard "$CAN_CHIPYARD" \
# And add to the JSON object:
  chipyard: {
    installed: $chipyard_installed,
    path: $chipyard_path,
    riscv_installed: $riscv_installed,
    riscv_path: $riscv_path
  },
  # In capabilities section, add:
  capabilities: {
    // ... existing flags ...
    can_chipyard: $can_chipyard
  }
```

### Stdout Summary Extension
```bash
# Add after ORFS summary line (line ~384):

if [ "$CHIPYARD_INSTALLED" = "true" ]; then
  echo "Chipyard:   [OK] $CHIPYARD_DIR_DETECTED"
else
  echo "Chipyard:   [MISSING]"
fi

if [ "$RISCV_INSTALLED" = "true" ]; then
  echo "RISCV:      [OK] $RISCV_PATH"
else
  echo "RISCV:      [MISSING]"
fi

# Add to capabilities section:
if [ "$CAN_CHIPYARD" = "true" ]; then
  echo "  Chipyard:   YES"
else
  echo "  Chipyard:   NO"
fi
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| N/A | Existing detect-env.sh pattern | Pre-v1.0 | Mature pattern, no changes needed to approach |

**Deprecated/outdated:**
- None relevant to this phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Chipyard marker file is `build.sbt` + `generators/chipyard/src/main/scala` (not `generators/src/main/scala` as CONTEXT.md states) | Code Examples | Medium -- if wrong Chipyard variant has different structure, detection fails. Mitigated by `build.sbt` as primary marker. |
| A2 | `$HOME/Desktop/chipyard` should be in the candidate chain (actual install location on this machine, used by chipyard-rtl SKILL.md default) | Code Examples | Low -- adds one extra candidate; no harm if directory does not exist. |
| A3 | Chipyard install guidance link should point to https://chipyard.readthedocs.io | SKILL.md update | Low -- standard Chipyard documentation URL. |
| A4 | The `initialize` SKILL.md step 5 is the correct place to add Chipyard/RISCV status display and install guidance | Architecture | Low -- follows existing pattern where step 5 presents the summary. |

**Note:** Claim A1 directly contradicts CONTEXT.md (which says `generators/src/main/scala`). The planner should use `build.sbt` as the primary validation (always reliable) and `generators/chipyard/src/main/scala` as secondary (if needed). This was verified on the actual Chipyard installation at `~/Desktop/chipyard`.

## Open Questions

1. **Should `$HOME/Desktop/chipyard` be a candidate?**
   - What we know: The actual Chipyard on this machine is at `~/Desktop/chipyard`. The chipyard-rtl SKILL.md hardcodes this as default. But CONTEXT.md only specifies `CHIPYARD_DIR` env, `~/chipyard`, `/opt/chipyard`.
   - What's unclear: Whether the candidate chain should include `~/Desktop/chipyard` or if the user should always set `CHIPYARD_DIR` env var.
   - Recommendation: Add `~/Desktop/chipyard` to the candidate chain. It is already the default in the chipyard-rtl SKILL.md, so it is a known install location. No harm in checking an extra directory.

2. **CONTEXT.md marker file discrepancy**
   - What we know: CONTEXT.md says validate with `generators/src/main/scala`. Verified on actual installation: that path does NOT exist. The correct path is `generators/chipyard/src/main/scala`.
   - What's unclear: Whether CONTEXT.md meant `generators/chipyard/src/main/scala` and was a typo, or if the user has a different expectation.
   - Recommendation: Use `build.sbt` as the primary marker (reliable across all Chipyard variants). Optionally check `generators/chipyard/src/main/scala` as secondary. The planner should note this discrepancy.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash | detect-env.sh | Yes | 5+ | -- |
| jq | JSON formatting | Yes | system | heredoc fallback (already in script) |
| Chipyard | Detection target | Yes | at ~/Desktop/chipyard | N/A (detection produces "false") |
| RISCV toolchain | Detection target | Yes | .conda-env/riscv-tools + /opt/riscv | N/A (detection produces "false") |
| riscv64-unknown-elf-gcc | RISCV validation | Yes | in both conda-env and /opt/riscv | N/A |

**Missing dependencies with no fallback:**
- None. All tools required for the implementation are available. Chipyard/RISCV themselves are detection targets, not build dependencies.

**Missing dependencies with fallback:**
- jq: heredoc fallback already implemented in detect-env.sh.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None for bash scripts |
| Config file | none |
| Quick run command | N/A |
| Full suite command | N/A |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ENV-01 | Chipyard detected when build.sbt + markers present | manual-only | `bash scripts/detect-env.sh && cat .chipagent/env.json \| jq .chipyard` | No |
| ENV-02 | env.json contains chipyard section and can_chipyard | manual-only | `cat .chipagent/env.json \| jq '.chipyard, .capabilities.can_chipyard'` | No |
| ENV-03 | detect-env.sh stdout shows Chipyard/RISCV lines | manual-only | `bash scripts/detect-env.sh \| grep -E 'Chipyard|RISCV'` | No |

**Justification for manual-only:** No shell test framework (bats, shellspec) is installed in this project. The detection script is a bash script that checks local environment state -- mocking filesystem paths in a unit test would not validate real behavior. Manual testing against the actual Chipyard installation provides higher confidence.

### Sampling Rate
- **Per task commit:** Manual run of `bash scripts/detect-env.sh` to verify output
- **Per wave merge:** Verify env.json contains new chipyard section with correct values
- **Phase gate:** Full manual test with Chipyard present + simulate absent case

### Wave 0 Gaps
- No shell test framework needed -- this phase uses manual validation against the real Chipyard installation
- Existing test infrastructure (TypeScript MCP server tests) does not cover bash scripts

## Security Domain

> This phase involves only bash script extension (environment detection) and documentation updates (SKILL.md). No user input processing, no network requests, no data storage beyond the existing env.json file.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A |
| V3 Session Management | no | N/A |
| V4 Access Control | no | N/A |
| V5 Input Validation | yes | Env var values treated as untrusted; `[ -n "$candidate" ]` check prevents empty-string injection |
| V6 Cryptography | no | N/A |

### Known Threat Patterns for bash/detection scripts

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Env var injection | Tampering | Env vars used only as directory paths; validated with `-f`/`-d` checks before use |
| Symlink attack | Tampering | `[ -f ]` follows symlinks but validates the target; acceptable for local dev tool |

## Sources

### Primary (HIGH confidence)
- `scripts/detect-env.sh` -- full script read, 429 lines, all patterns analyzed [VERIFIED: codebase]
- `scripts/_common.sh` -- shared path resolution [VERIFIED: codebase]
- `skills/initialize/SKILL.md` -- initialize skill instructions [VERIFIED: codebase]
- `skills/chipyard-rtl/SKILL.md` -- existing Chipyard integration patterns [VERIFIED: codebase]
- Filesystem verification of `~/Desktop/chipyard/` -- structure, markers, RISCV paths [VERIFIED: bash commands]

### Secondary (MEDIUM confidence)
- Chipyard documentation at https://chipyard.readthedocs.io [CITED: official docs URL]
- GitHub repository at https://github.com/ucb-bar/chipyard [CITED: official repo]

### Tertiary (LOW confidence)
- None -- all findings verified against local codebase and filesystem.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - no new dependencies; extending existing bash/jq infrastructure
- Architecture: HIGH - follows established patterns in detect-env.sh; all integration points verified in codebase
- Pitfalls: HIGH - verified against actual Chipyard installation on this machine; marker file discrepancy confirmed

**Research date:** 2026-04-14
**Valid until:** 2026-05-14 (stable -- bash patterns and Chipyard structure unlikely to change)
