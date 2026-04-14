---
phase: 18-chipyard-environment-detection
fixed_at: 2026-04-14T18:30:00Z
review_path: .planning/phases/18-chipyard-environment-detection/18-REVIEW.md
iteration: 2
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 18: Code Review Fix Report

**Fixed at:** 2026-04-14T18:30:00Z
**Source review:** .planning/phases/18-chipyard-environment-detection/18-REVIEW.md
**Iteration:** 2

**Summary:**
- Findings in scope: 2
- Fixed: 2
- Skipped: 0

## Fixed Issues

### WR-01: Heredoc fallback produces invalid JSON for paths containing special characters

**Files modified:** `scripts/detect-env.sh`
**Commit:** 2e53324
**Applied fix:** Added a `json_escape()` helper function that escapes backslashes and double quotes via sed. Applied `json_escape` to all interpolated string values (versions, paths, timestamps) in the heredoc JSON fallback block (lines 335-385). Boolean values remain unescaped since they are always literal `true`/`false`. The `jq` branch was left unchanged as it already handles escaping correctly via `--arg`.

### WR-02: BACKEND_MODE always "docker" when Docker is installed, with no user override

**Files modified:** `scripts/detect-env.sh`
**Commit:** b9a157c
**Applied fix:** Replaced the unconditional Docker auto-detect logic with a three-tier override chain: (1) if `CHIPAGENT_BACKEND_MODE` env var is set, use it; (2) else if Docker is installed, use "docker"; (3) else use "local". This allows users with both Docker and a local ORFS build to force local mode by setting the environment variable.

---

_Fixed: 2026-04-14T18:30:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_
