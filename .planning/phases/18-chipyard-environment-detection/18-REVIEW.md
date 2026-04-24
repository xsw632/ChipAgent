---
phase: 18-chipyard-environment-detection
reviewed: 2026-04-14T18:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - scripts/detect-env.sh
  - skills/initialize/SKILL.md
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 18: Code Review Report

**Reviewed:** 2026-04-14T18:00:00Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Re-reviewed `scripts/detect-env.sh` (514 lines) and `skills/initialize/SKILL.md` (81 lines) after prior fixes were applied. The previous critical finding (CR-01: eval-based command injection) has been resolved -- the code now uses a `case` dispatch pattern in `get_version_output()` (lines 17-31). The previous WR-01 (dead `status_label` function) is also resolved. The previous WR-02 (unguarded `SKY130HD_DIR` in GDS check) is resolved with an explicit `-n` guard at line 218.

Two new warnings and three info findings remain. No critical or security issues.

## Previous Findings -- Resolved

| ID | Description | Status |
|----|-------------|--------|
| CR-01 | Command injection via `eval` in detect_tool | Fixed -- replaced with `case` dispatch (lines 17-31) |
| WR-01 | Dead `status_label` function | Fixed -- removed entirely |
| WR-02 | Unguarded `SKY130HD_DIR` in GDS check | Fixed -- explicit `-n` guard added (line 218) |

## Critical Issues

No critical issues found.

## Warnings

### WR-01: Heredoc fallback produces invalid JSON for paths containing special characters

**File:** `scripts/detect-env.sh:331-381`
**Issue:** When `jq` is not available, the script falls back to a heredoc that interpolates shell variables directly into JSON. If any detected tool path contains a double quote (`"`), backslash (`\`), or control character, the output JSON will be malformed. This is especially relevant on Windows (MSYS/Cygwin) where `_common.sh` (line 12) converts paths to mixed-mode `C:/...` format -- if that path were to contain a backslash that survived `cygpath -m`, it would break the heredoc JSON. The `jq` branch (lines 232-329) handles this correctly via `--arg` escaping.
**Fix:** Add a sanitization helper for the fallback path:
```bash
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
```
Then use `"$(json_escape "$JAVA_PATH")"` in the heredoc. Alternatively, consider making `jq` a hard dependency and removing the fallback.

### WR-02: BACKEND_MODE always "docker" when Docker is installed, with no user override

**File:** `scripts/detect-env.sh:150-153`
**Issue:** The logic unconditionally sets `BACKEND_MODE="docker"` whenever Docker is installed, even if the user has `ORFS_DIR` set pointing to a local installation. Users with both Docker and a local ORFS build have no way to force local mode. This matters because Docker-based and local ORFS flows may produce different results or have different capabilities.
**Fix:** Respect an explicit override before auto-detecting:
```bash
if [ -n "${CHIPAGENT_BACKEND_MODE:-}" ]; then
  BACKEND_MODE="$CHIPAGENT_BACKEND_MODE"
elif [ "$DOCKER_INSTALLED" = "true" ]; then
  BACKEND_MODE="docker"
else
  BACKEND_MODE="local"
fi
```

## Info

### IN-01: Global TOOL_INSTALLED/TOOL_VERSION/TOOL_PATH used as implicit return values

**File:** `scripts/detect-env.sh:36-58`
**Issue:** The `detect_tool` function communicates results via three global variables that are immediately copied into tool-specific variables (lines 62-104). This pattern is correct as written but is fragile under maintenance -- any caller that invokes `detect_tool` twice without copying results between calls will silently lose the first result. The variable names `TOOL_INSTALLED`, `TOOL_VERSION`, `TOOL_PATH` do not convey their transient nature.
**Fix:** Low priority. Consider prefixing with `__` (e.g., `__TOOL_INSTALLED`) to signal internal/temporary usage, or document the contract in the function header comment.

### IN-02: Missing executable permission on detect-env.sh

**File:** `scripts/detect-env.sh` (filesystem)
**Issue:** The file lacks the executable bit (`-rw-rw-r--`), unlike sibling scripts (`compile.sh`, `lint.sh`, etc. which are `-rwxrwxr-x`). While the skill invokes it through the Bash tool (which does not require +x), this inconsistency makes the file harder to run directly during development or debugging (`./scripts/detect-env.sh` would fail with "Permission denied").
**Fix:** `chmod +x scripts/detect-env.sh`

### IN-03: SKILL.md lists ORFS as requirement for Can Synthesize, but script does not check it

**File:** `skills/initialize/SKILL.md:53`
**Issue:** The skill documentation states `Can Synthesize (requires Yosys + sky130hd PDK + ORFS)` but the script at lines 210-212 sets `CAN_SYNTHESIZE="true"` when only `YOSYS_INSTALLED` and `SKY130HD_INSTALLED` are true, without checking `ORFS_INSTALLED`. This is a documentation/script mismatch. The script behavior is arguably correct (Yosys can synthesize without ORFS), but the skill description is misleading.
**Fix:** Update `skills/initialize/SKILL.md` line 53 to read:
```
- **Can Synthesize** (requires Yosys + sky130hd PDK): whether RTL synthesis is possible
```

---

_Reviewed: 2026-04-14T18:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
