---
phase: 18-chipyard-environment-detection
reviewed: 2026-04-14T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - scripts/detect-env.sh
  - skills/initialize/SKILL.md
findings:
  critical: 1
  warning: 2
  info: 2
  total: 5
status: issues_found
---

# Phase 18: Code Review Report

**Reviewed:** 2026-04-14T00:00:00Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Reviewed the new environment detection script (`scripts/detect-env.sh`) and its accompanying skill definition (`skills/initialize/SKILL.md`). The script detects 9 tools, sky130hd PDK, ORFS, Docker, Chipyard, and the RISCV toolchain, then writes results to `.chipagent/env.json` and prints a human-readable summary.

One critical finding: `eval` is used on interpolated command strings, which creates a command injection vector if a caller passes crafted input through the version command argument. Two warnings relate to dead code (an unused function and unreachable variable expansion) and one info item flags the fallback JSON path. The SKILL.md is well-structured and has no significant issues.

## Critical Issues

### CR-01: Command injection via eval in detect_tool

**File:** `scripts/detect-env.sh:28`
**Issue:** The `detect_tool` function uses `eval "$version_command"` on line 28. The `version_command` argument is a string that gets evaluated by the shell. While current call sites (lines 43-86) pass hardcoded command strings, the function design is fragile -- any future caller passing user-controlled input into `detect_tool` would enable arbitrary command execution. Additionally, `eval` is unnecessary here because the version commands are simple pipelines that can be invoked directly via `$()` without eval.

The current hardcoded call sites are safe, but the pattern itself is a latent risk and violates the project's own security guidelines (CLAUDE.md references security checks, and the global rules mandate no `eval` usage).

**Fix:**
Replace `eval` with direct invocation. Since the version commands are static strings known at each call site, pass the command as separate arguments or use a dispatch pattern:

```bash
# Option A: Pass command components as array, avoid eval entirely
detect_tool() {
  local tool_name="$1"
  local command_name="$2"
  shift 2
  # Remaining args are the version command + args
  local version_output
  version_output=$("$@" 2>&1 | head -1 || true)
  # ...
}

# Call site example:
detect_tool "java" "java" java -version
```

Or if the pipeline variants (`| head -1`, `| tail -1`) need preserving:

```bash
# Option B: Use a case/dispatch instead of eval
get_version_output() {
  local tool="$1"
  case "$tool" in
    java)     java -version 2>&1 | head -1 ;;
    sbt)      sbt --batch --version 2>&1 | tail -1 ;;
    scala)    scala -version 2>&1 | head -1 ;;
    verilator) verilator --version 2>&1 | head -1 ;;
    make)     make --version 2>&1 | head -1 ;;
    gpp)      g++ --version 2>&1 | head -1 ;;
    yosys)    yosys --version 2>&1 | head -1 ;;
    openroad) openroad -version 2>&1 | head -1 ;;
    klayout)  klayout -v 2>&1 | head -1 ;;
    *) echo "" ;;
  esac
}
```

## Warnings

### WR-01: Dead code -- status_label function defined but never called

**File:** `scripts/detect-env.sh:367-373`
**Issue:** The `status_label` function is defined on lines 367-373 but is never invoked anywhere in the script. The summary output (lines 378-460) uses inline `if/else` blocks instead of calling this function. This is dead code that adds confusion for maintainers.

**Fix:** Either remove the unused `status_label` function entirely, or refactor the summary output section to use it:

```bash
# Remove lines 367-373, or refactor summary to use it:
echo "$(status_label "$JAVA_INSTALLED" "Java:") $JAVA_VERSION"
```

### WR-02: SKY130HD_DIR empty in GDS check when PDK not found

**File:** `scripts/detect-env.sh:200`
**Issue:** Line 200 checks `[ -f "$SKY130HD_DIR/gds/sky130_fd_sc_hd.gds" ]` for the CAN_GDS capability. However, if the sky130hd PDK was not detected (i.e., no candidate matched on line 98), `SKY130HD_DIR` remains empty (set to `""` on line 90). The test then becomes `[ -f "/gds/sky130_fd_sc_hd.gds" ]`, which checks the filesystem root. While this will always fail (correct outcome), it is a fragile check that depends on the path not existing at root rather than being explicitly guarded. If for some unusual reason a file exists at `/gds/sky130_fd_sc_hd.gds`, CAN_GDS would be set to true without a valid PDK installation.

**Fix:** Add an explicit guard:
```bash
if [ "$KLAYOUT_INSTALLED" = "true" ] && [ "$SKY130HD_INSTALLED" = "true" ] && [ -n "$SKY130HD_DIR" ] && [ -f "$SKY130HD_DIR/gds/sky130_fd_sc_hd.gds" ]; then
```

## Info

### IN-01: Fallback JSON heredoc does not escape variable values

**File:** `scripts/detect-env.sh:313-363`
**Issue:** The `else` branch (when `jq` is not installed) writes JSON via a heredoc that interpolates shell variables directly. If any tool path or version string contains characters like `"`, `\`, or newlines, the resulting JSON would be malformed. The `jq` branch handles this correctly because `jq --arg` properly escapes values. This is low risk because tool paths and versions are unlikely to contain such characters, and the jq branch is the primary code path.

**Fix:** Document the limitation with a comment, or add basic sanitization for the fallback path:
```bash
# Sanitize for JSON safety in heredoc fallback
sanitize_for_json() { echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
```

### IN-02: SKILL.md install instructions use apt-specific commands

**File:** `skills/initialize/SKILL.md:57-65`
**Issue:** The install instructions in the skill definition default to `apt install` commands. The project also supports macOS (referenced in Xcode Command Line Tools mentions) but the primary install commands are Debian/Ubuntu-specific. This is a documentation completeness issue rather than a bug.

**Fix:** Consider adding Homebrew equivalents for macOS users, e.g., `brew install verilator`, `brew install yosys`, etc.

---

_Reviewed: 2026-04-14T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
