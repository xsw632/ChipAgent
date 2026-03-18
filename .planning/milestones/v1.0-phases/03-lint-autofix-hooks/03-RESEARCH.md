# Phase 3: Lint, Auto-Fix + Hooks - Research

**Researched:** 2026-03-17
**Domain:** Verilator lint checking, auto-fix loop design, Claude Code plugin hooks
**Confidence:** HIGH

## Summary

Phase 3 adds Verilator lint checking to the pipeline and upgrades the hook-based automation layer. The core technical work is threefold: (1) a `scripts/lint.sh` script that runs `verilator --lint-only` on generated Verilog, (2) an auto-fix loop where lint errors feed back to the Chisel generator agent for correction (max 3 attempts), and (3) properly structured `hooks/hooks.json` that chains compile and lint stages without creating infinite loops.

Empirical testing on the current project's generated Verilog reveals that `verilator --lint-only` (default mode, without `-Wall`) passes cleanly on both `ALU.v` and `TrivialModule.v`. The `-Wall` flag adds style warnings -- specifically `UNUSEDSIGNAL` for Chisel's mandatory `clock` and `reset` ports on combinational modules. These are known-benign warnings inherent to Chisel-generated code and should be suppressed via a Verilator waiver file, not by modifying generated Verilog.

The existing `hooks/hooks.json` uses a legacy flat-array format that differs from the current official event-keyed format documented by Anthropic. This must be corrected as part of the hook work. The key infinite-loop prevention mechanism is precise matcher targeting: hooks must match on `Bash` tool (for lint.sh output) rather than `Write|Edit` (which would re-trigger on Chisel source fixes), and the lint script must only trigger after compile.sh succeeds.

**Primary recommendation:** Create `scripts/lint.sh` with Verilator lint + waiver file for known Chisel warnings, update `hooks/hooks.json` to the official event-keyed format with two PostToolUse hooks (compile on Scala write, lint on Verilog generation), and update `generate.md` to orchestrate the lint stage with a 3-attempt auto-fix loop.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LINT-01 | `scripts/lint.sh` runs `verilator --lint-only` on generated Verilog | Verilator 5.008 confirmed installed; `--lint-only` flag verified; lint.sh script pattern documented |
| LINT-02 | Lint errors trigger auto-fix loop (max 3 attempts) | Auto-fix loop design via generate.md skill orchestration; error output parsing from Verilator stderr |
| LINT-03 | After 3 failed attempts, pipeline stops and reports remaining errors | Generate.md skill logic with attempt counter; clear error reporting format documented |
| LINT-04 | `verilator --lint-only generated/*.v` produces no ERROR output on success | Verified: current ALU.v and TrivialModule.v pass basic lint cleanly (exit 0, no errors) |
| LINT-05 | Warnings are documented in verification report with explanations | Waiver file pattern for known Chisel warnings (UNUSEDSIGNAL clock/reset); `-Wno-fatal` for non-blocking warning capture |
| HOOK-01 | `hooks/hooks.json` defines PostToolUse hooks for pipeline automation | Official event-keyed format documented; current file needs migration from legacy format |
| HOOK-02 | Hooks use `${CLAUDE_PLUGIN_ROOT}` for all script paths | Verified in official docs: `${CLAUDE_PLUGIN_ROOT}` is the standard plugin path variable |
| HOOK-03 | Hook matchers are precise (no infinite loops) | Matcher design: compile triggers on `Write\|Edit` of Scala files (via skill orchestration), lint triggers after compile success |
</phase_requirements>

## Standard Stack

### Core (Already Established)
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Verilator | 5.008 | Verilog lint and simulation | Installed and verified on this system |
| Chisel3 | 3.6.1 | Hardware construction DSL | Project-pinned |
| Scala | 2.13.10 | Chisel host language | Project-pinned |
| sbt | 1.10.7 | Build tool | Project-pinned |

### Phase 3 New Components
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| Verilator waiver file (.vlt) | N/A | Suppress known-benign Chisel warnings | Always included in lint invocation |
| `scripts/lint.sh` | N/A | Lint wrapper script | After every successful compile |
| Updated `hooks/hooks.json` | N/A | Event-keyed hook automation | Automatically chains compile and lint |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Verilator waiver file | Inline `/* verilator lint_off */` comments | Waiver file is better -- never modify generated Verilog |
| `-Wno-UNUSEDSIGNAL` CLI flag | Waiver file with `lint_off` rules | Waiver file is more precise (matches specific signals, not all UNUSEDSIGNAL) |
| Verible (CHIPS Alliance linter) | Verilator lint | Verilator is already installed, used for simulation in Phase 4; single tool avoids complexity |
| SARIF JSON output | Parse stderr text | SARIF (`--diagnostics-sarif`) is NOT available in Verilator 5.008 (verified); must parse text |

**Installation:** No new installation needed. Verilator 5.008 is already installed.

## Architecture Patterns

### Recommended Project Structure (Phase 3 additions)
```
ChipAgent/
  hooks/
    hooks.json               # REWRITTEN: event-keyed format with compile + lint hooks
  scripts/
    compile.sh               # Existing: sbt compilation wrapper
    lint.sh                  # NEW: Verilator lint wrapper
  generated/
    chisel-warnings.vlt      # NEW: Verilator waiver file for known Chisel warnings
  skills/
    generate.md              # UPDATED: adds lint stage (Step 4) with auto-fix loop
```

### Pattern 1: Lint Script (LINT-01, LINT-04)

**What:** A bash script that runs `verilator --lint-only` on generated Verilog files.

**When to use:** After every successful compile, before testbench generation.

**Design:**
```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTPUT_DIR="$PLUGIN_ROOT/generated"
WAIVER="$OUTPUT_DIR/chisel-warnings.vlt"

# Find .v files to lint (exclude support files like filelist.f)
V_FILES=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.v" 2>/dev/null)
if [ -z "$V_FILES" ]; then
  echo "LINT ERROR: No .v files found in $OUTPUT_DIR"
  exit 1
fi

# Lint each file individually (avoids MULTITOP warning)
LINT_PASS=true
for vfile in $V_FILES; do
  echo "Linting: $(basename "$vfile")"
  LINT_LOG=$(mktemp)

  ARGS=(--lint-only)
  [ -f "$WAIVER" ] && ARGS+=("$WAIVER")
  ARGS+=("$vfile")

  EXIT_CODE=0
  verilator "${ARGS[@]}" > "$LINT_LOG" 2>&1 || EXIT_CODE=$?

  if [ "$EXIT_CODE" -ne 0 ]; then
    echo "LINT ERRORS in $(basename "$vfile"):"
    cat "$LINT_LOG"
    LINT_PASS=false
  fi

  # Capture warnings separately (with -Wno-fatal so exit 0)
  verilator --lint-only -Wall -Wno-fatal ${WAIVER:+"$WAIVER"} "$vfile" 2>&1 \
    | grep '^%Warning' >> "$PLUGIN_ROOT/generated/lint-warnings.log" 2>/dev/null || true

  rm -f "$LINT_LOG"
done

if [ "$LINT_PASS" = true ]; then
  echo "LINT PASSED: All files clean"
  exit 0
else
  echo "LINT FAILED: See errors above"
  exit 1
fi
```

**Key decisions:**
- Lint each `.v` file individually to avoid `MULTITOP` warnings when multiple modules exist
- Use waiver file if present (for known Chisel warnings)
- Separate pass for `-Wall -Wno-fatal` to capture warnings without failing the build
- Warnings are logged to `generated/lint-warnings.log` for LINT-05 documentation

### Pattern 2: Verilator Waiver File (LINT-05)

**What:** A `.vlt` file that suppresses known-benign warnings from Chisel-generated Verilog.

**When to use:** Always included in lint invocations.

**Content:**
```
// Verilator waiver file for Chisel-generated Verilog
// Chisel always emits clock and reset ports, even for combinational modules.
// These are harmless structural artifacts of the Chisel compilation flow.

`verilator_config

// Chisel emits clock/reset on all modules, even purely combinational ones.
// These signals are unused in combinational logic but required by Chisel's Module base class.
lint_off -rule UNUSEDSIGNAL -file "*/generated/*" -match "Signal is not used: 'clock'"
lint_off -rule UNUSEDSIGNAL -file "*/generated/*" -match "Signal is not used: 'reset'"
```

**Why this is the right approach:**
- Empirically verified: `verilator --lint-only` (without `-Wall`) already passes cleanly on ALU.v and TrivialModule.v
- The `UNUSEDSIGNAL` warnings for clock/reset only appear with `-Wall` and are inherent to ALL Chisel-generated combinational modules
- The waiver file targets specific signals (`clock`, `reset`) in specific directories (`generated/`), not a blanket suppression
- Generated Verilog must NEVER be hand-edited (it is reproducible via compile.sh)

### Pattern 3: Auto-Fix Loop (LINT-02, LINT-03)

**What:** When lint errors are found, the pipeline feeds errors back to the chisel-generator agent for Chisel source correction, up to 3 attempts.

**When to use:** In the `generate.md` skill pipeline, after lint.sh reports errors.

**Loop design (in generate.md):**
```
Step 4 -- Lint
  Run scripts/lint.sh
  IF lint passes:
    Continue to Step 5 (Verify)
  IF lint fails:
    FOR attempt = 1 to 3:
      1. Read lint error output from lint.sh
      2. Feed errors to chisel-generator agent along with:
         - The current Chisel source file
         - The lint error messages
         - Instruction: "Fix the Chisel source to eliminate these Verilator lint errors"
      3. Agent modifies the Chisel source
      4. PostToolUse hook auto-triggers compile.sh
      5. IF compile succeeds, run lint.sh again
      6. IF lint passes, break loop
    IF still failing after 3 attempts:
      STOP pipeline
      Report: "Lint auto-fix failed after 3 attempts. Remaining errors: [errors]"
```

**Important:** The auto-fix targets the **Chisel source**, not the generated Verilog. Lint errors in generated Verilog are fixed by modifying the upstream Chisel code, recompiling, and re-linting.

**Common lint errors that need Chisel-level fixes:**
- Width mismatch warnings: Fix port widths or operation expressions in Chisel
- Undriven signals: Add default assignments in Chisel
- Combinational loops: Restructure Chisel logic

**Common lint errors that are NOT fixable at Chisel level:**
- `UNUSEDSIGNAL` for clock/reset: Handled by waiver file
- `MULTITOP`: Handled by linting files individually

### Pattern 4: Hooks Configuration (HOOK-01, HOOK-02, HOOK-03)

**What:** The `hooks/hooks.json` file must use the official event-keyed format with precise matchers.

**Current (INCORRECT) format:**
```json
{
  "hooks": [
    {
      "type": "PostToolUse",
      "matcher": { "tool": "Write|Edit", "path": "*/src/main/scala/**/*.scala" },
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/compile.sh",
      "timeout": 120000
    }
  ]
}
```

**Correct (OFFICIAL) format:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/compile.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

**Key format differences:**
1. `hooks` is an **object keyed by event name**, not an array
2. Each event maps to an **array of matcher groups**, not individual hook objects
3. `matcher` is a **regex string** (e.g., `"Write|Edit"`), not an object with `tool`/`path` fields
4. Each matcher group has a nested `hooks` array of handler objects
5. `timeout` is in **seconds** (not milliseconds)
6. Handler objects have `"type": "command"` explicitly

**Infinite loop prevention strategy:**

The PostToolUse hook for compile.sh fires when Claude writes/edits Scala files. This works because:
- The hook runs compile.sh, which runs sbt (external process)
- sbt writes Verilog to `generated/`, but this is NOT a Claude tool call
- Therefore the PostToolUse hook does NOT re-fire

The lint step should NOT be a PostToolUse hook. Instead, lint should be orchestrated by the `generate.md` skill after confirming compilation success. This is because:
- A lint hook on `Bash` tool would fire on ANY bash command, not just compile.sh
- Making lint a hook creates a complex chain: Write Scala -> compile hook -> compile writes Verilog -> ??? lint hook ???
- The generate.md skill already orchestrates the pipeline and can run lint.sh explicitly

**Recommended hooks configuration:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/compile.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

Only the compile hook should be a PostToolUse automation. Lint is orchestrated by the skill (generate.md) after compile succeeds. This prevents infinite loops and keeps the pipeline linear.

### Anti-Patterns to Avoid

- **Linting generated Verilog and trying to fix the Verilog directly:** Always fix the upstream Chisel source and recompile. Generated Verilog is never hand-edited.
- **Adding lint as a PostToolUse hook:** This creates unpredictable triggering. Lint should be an explicit skill-orchestrated step.
- **Using `-Wall` as the default lint mode:** `-Wall` enables style warnings that include unavoidable Chisel artifacts. Use default lint mode for pass/fail; use `-Wall -Wno-fatal` separately for warning documentation.
- **Linting all `.v` files at once:** Causes `MULTITOP` warnings. Lint each file individually.
- **Using the legacy flat-array hooks format:** Must migrate to official event-keyed format.
- **Suppressing ALL `UNUSEDSIGNAL` warnings globally:** Use targeted waiver rules matching specific signals and file paths.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Verilog lint checking | Custom Verilog parser | `verilator --lint-only` | Verilator is the industry standard; catches real hardware bugs |
| Warning suppression | Inline Verilog comments | `.vlt` waiver file | Never modify generated code; waiver is external and version-controllable |
| Lint error parsing | Regex-based error parser | Pass raw Verilator output to Claude agent | Claude can interpret Verilator error messages and map them to Chisel fixes |
| Hook infinite-loop guard | Custom state tracking / lock files | Precise matcher + skill orchestration | The hook system's matcher regex is sufficient when used correctly |
| Waiver file generation | Manual waiver authoring | `verilator --waiver-output` then curate | Verilator auto-generates the waiver template |

**Key insight:** Verilator lint errors in generated Verilog almost always trace back to Chisel source issues. The auto-fix loop must work at the Chisel level, not the Verilog level. Claude (the generator agent) can interpret Verilator error messages and fix the corresponding Chisel code.

## Common Pitfalls

### Pitfall 1: UNUSEDSIGNAL for clock/reset on Combinational Modules
**What goes wrong:** Verilator reports `%Warning-UNUSEDSIGNAL` for `clock` and `reset` on purely combinational Chisel modules.
**Why it happens:** Chisel's `Module` base class always emits `clock` and `reset` ports in the generated Verilog, even when the module has no sequential logic.
**How to avoid:** Use a Verilator waiver file (`chisel-warnings.vlt`) with targeted `lint_off` rules for clock/reset in `generated/`.
**Warning signs:** `-Wall` lint fails on clean combinational modules with only UNUSEDSIGNAL warnings.

### Pitfall 2: MULTITOP Warning When Linting Multiple Files
**What goes wrong:** `verilator --lint-only generated/*.v` produces `%Warning-MULTITOP: Multiple top level modules`.
**Why it happens:** Each `.v` file contains its own top module. When Verilator processes them together, it sees multiple tops.
**How to avoid:** Lint each `.v` file individually in a loop, not all at once.
**Warning signs:** Clean files suddenly report warnings when linted together.

### Pitfall 3: Hooks Using Legacy Format
**What goes wrong:** Hooks silently fail or behave unexpectedly.
**Why it happens:** The existing `hooks/hooks.json` uses a flat-array format with object-based matchers (`{ "tool": "...", "path": "..." }`). The current official format uses event-keyed objects with regex string matchers.
**How to avoid:** Rewrite `hooks/hooks.json` to the official format (event-keyed with nested hooks array).
**Warning signs:** Hooks not firing after tool use, `/hooks` menu showing unexpected results.

### Pitfall 4: Lint Hook Triggering Infinite Loop
**What goes wrong:** Lint hook fires, finds error, agent fixes Chisel, compile hook fires, new Verilog generated, lint hook fires again, finds new error, loop continues.
**Why it happens:** PostToolUse hooks fire on every matching tool call, including fixes made during the auto-fix loop.
**How to avoid:** Do NOT make lint a PostToolUse hook. Keep compile as the only PostToolUse hook. Run lint explicitly from the generate.md skill.
**Warning signs:** Claude enters a long loop of compile-lint-fix-compile-lint cycles.

### Pitfall 5: Trying to Fix Generated Verilog Instead of Chisel Source
**What goes wrong:** Lint errors are "fixed" by editing the `.v` file, but changes are overwritten on next compile.
**Why it happens:** Natural instinct is to fix the file that has the error, but generated files are ephemeral.
**How to avoid:** The auto-fix loop must always modify the Chisel `.scala` source, recompile, and re-lint. Never touch `generated/*.v`.
**Warning signs:** Lint passes once but fails again after any recompile.

### Pitfall 6: Hook Timeout Too Short for sbt Compilation
**What goes wrong:** PostToolUse hook for compile.sh times out, appearing as a hook failure.
**Why it happens:** sbt compilation can take 30-90 seconds, especially on first run after dependency download.
**How to avoid:** Set timeout to 120 seconds (matching compile.sh's internal timeout). Note: official format uses seconds, not milliseconds.
**Warning signs:** "Hook timed out" errors in Claude Code transcript.

## Code Examples

### lint.sh Script (LINT-01, LINT-04)
```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUTPUT_DIR="$PLUGIN_ROOT/generated"
WAIVER="$OUTPUT_DIR/chisel-warnings.vlt"

# Find .v files to lint
V_FILES=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.v" 2>/dev/null)
if [ -z "$V_FILES" ]; then
  echo "LINT ERROR: No .v files found in $OUTPUT_DIR"
  exit 1
fi

LINT_PASS=true
WARNINGS_LOG="$OUTPUT_DIR/lint-warnings.log"
> "$WARNINGS_LOG"  # truncate

for vfile in $V_FILES; do
  BASENAME=$(basename "$vfile")
  echo "Linting: $BASENAME"

  # Build verilator args
  ARGS=(--lint-only)
  [ -f "$WAIVER" ] && ARGS+=("$WAIVER")
  ARGS+=("$vfile")

  # Run lint (errors cause non-zero exit)
  LINT_OUT=$(mktemp)
  EXIT_CODE=0
  verilator "${ARGS[@]}" > "$LINT_OUT" 2>&1 || EXIT_CODE=$?

  if [ "$EXIT_CODE" -ne 0 ]; then
    echo "LINT ERRORS in $BASENAME:"
    echo "---"
    cat "$LINT_OUT"
    echo "---"
    LINT_PASS=false
  fi

  # Capture warnings (Wall + Wno-fatal = warnings printed but exit 0)
  WARN_ARGS=(--lint-only -Wall -Wno-fatal)
  [ -f "$WAIVER" ] && WARN_ARGS+=("$WAIVER")
  WARN_ARGS+=("$vfile")

  verilator "${WARN_ARGS[@]}" 2>&1 | grep '^%Warning' >> "$WARNINGS_LOG" 2>/dev/null || true

  rm -f "$LINT_OUT"
done

# Report warnings if any remain
if [ -s "$WARNINGS_LOG" ]; then
  WARN_COUNT=$(wc -l < "$WARNINGS_LOG")
  echo "Warnings ($WARN_COUNT remaining after waiver):"
  cat "$WARNINGS_LOG"
fi

if [ "$LINT_PASS" = true ]; then
  echo "LINT PASSED: All files clean"
  exit 0
else
  echo "LINT FAILED: Fix errors above and retry"
  exit 1
fi
```

### Verilator Waiver File (chisel-warnings.vlt)
```
// Verilator waiver file for Chisel-generated Verilog
// Chisel's Module base class always emits clock and reset ports,
// even for purely combinational modules. These signals are unused
// in combinational logic but are structural artifacts of the
// Chisel compilation flow. This is expected and benign.

`verilator_config

lint_off -rule UNUSEDSIGNAL -file "*/generated/*" -match "Signal is not used: 'clock'"
lint_off -rule UNUSEDSIGNAL -file "*/generated/*" -match "Signal is not used: 'reset'"
```

### Updated hooks/hooks.json (HOOK-01, HOOK-02, HOOK-03)
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/compile.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

### Updated generate.md Lint Stage (LINT-02, LINT-03, LINT-05)
```markdown
### Step 4 -- Lint

Run Verilator lint on the generated Verilog:

1. Run `scripts/lint.sh`
2. If lint passes, continue to Step 5 (Verify)
3. If lint fails (non-zero exit):
   a. Read the error output carefully
   b. Identify the Chisel source issue that caused the Verilog lint error
   c. Use the chisel-generator agent to fix the Chisel source
   d. The PostToolUse hook will auto-trigger compile.sh
   e. After compile succeeds, run lint.sh again
   f. Repeat up to 3 total attempts
4. If lint still fails after 3 attempts, STOP and report:
   "Lint auto-fix failed after 3 attempts. Remaining errors:"
   followed by the lint error output.
5. Any remaining warnings (after waiver suppression) are noted in
   the verification output with explanations.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No lint step | Verilator `--lint-only` in pipeline | This phase | Catches Verilog issues before simulation |
| Manual Verilog inspection | Automated lint + auto-fix loop | This phase | No human intervention needed |
| Inline lint suppression comments | `.vlt` waiver files | Verilator 4.028+ | Never modify generated code |
| Text-only diagnostics | SARIF JSON output (`--diagnostics-sarif`) | Verilator 5.024+ | NOT available in 5.008; use text parsing |
| Flat-array hooks format | Event-keyed hooks format | Claude Code 2026 | Must migrate existing hooks.json |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Shell-based integration tests (bash scripts) |
| Config file | None -- tests are bash scripts |
| Quick run command | `scripts/lint.sh` |
| Full suite command | `scripts/compile.sh && scripts/lint.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LINT-01 | lint.sh runs verilator --lint-only | integration | `scripts/lint.sh; echo $?` | No -- Wave 0 |
| LINT-02 | Lint errors trigger auto-fix loop | manual (skill orchestration) | N/A -- validated via pipeline execution | N/A |
| LINT-03 | After 3 failures, pipeline stops | manual (skill orchestration) | N/A -- validated via pipeline execution | N/A |
| LINT-04 | No ERROR output on lint-clean Verilog | integration | `verilator --lint-only generated/ALU.v; echo $?` | No -- Wave 0 |
| LINT-05 | Warnings documented with explanations | integration | `test -f generated/lint-warnings.log` | No -- Wave 0 |
| HOOK-01 | hooks.json defines PostToolUse hooks | smoke | `jq '.hooks.PostToolUse' hooks/hooks.json` | Yes (needs rewrite) |
| HOOK-02 | Hooks use CLAUDE_PLUGIN_ROOT | smoke | `grep 'CLAUDE_PLUGIN_ROOT' hooks/hooks.json` | Yes (already present) |
| HOOK-03 | No infinite loops | manual + smoke | Verify only compile hook in PostToolUse (no lint hook) | N/A |

### Sampling Rate
- **Per task commit:** `scripts/lint.sh` (verify lint passes)
- **Per wave merge:** `scripts/compile.sh && scripts/lint.sh && jq '.hooks.PostToolUse' hooks/hooks.json`
- **Phase gate:** Full pipeline test: compile ALU, lint ALU.v, verify no errors

### Wave 0 Gaps
- [ ] `scripts/lint.sh` -- Verilator lint wrapper script
- [ ] `generated/chisel-warnings.vlt` -- waiver file for known Chisel warnings
- [ ] `scripts/test-phase3.sh` -- integration test for lint pipeline

## Open Questions

1. **Whether to use `-Wall` as default lint mode**
   - What we know: Default mode (no `-Wall`) passes cleanly on current Verilog. `-Wall` adds style warnings that include unavoidable Chisel artifacts (UNUSEDSIGNAL for clock/reset).
   - What's unclear: Whether users want to see style warnings or only true errors.
   - Recommendation: Use default mode (no `-Wall`) for pass/fail gating. Run `-Wall -Wno-fatal` separately to capture and document warnings for LINT-05. The waiver file handles known Chisel artifacts.

2. **Scope of lint.sh -- single file vs. all files**
   - What we know: The pipeline generates one module at a time. But `generated/` may contain files from previous runs (ALU.v AND TrivialModule.v).
   - What's unclear: Should lint.sh lint only the newly generated file or all `.v` files?
   - Recommendation: Lint all `.v` files individually. This catches regressions if Generate.scala is modified to emit multiple modules. Accept a `--file` argument to lint a specific file for faster pipeline runs.

3. **Whether compile hook matcher needs path filtering**
   - What we know: The official hooks format uses regex string matchers on tool name only (e.g., `"Write|Edit"`). The legacy format had a `path` field, but this is not in the official spec.
   - What's unclear: Whether the current Claude Code version supports path-based matchers within the regex string.
   - Recommendation: Use `"Write|Edit"` matcher without path filtering. The compile.sh script already handles being called on non-Scala file edits gracefully (it just compiles whatever the project has). Since this is a plugin specifically for Chisel projects, all Write/Edit operations within the plugin context are relevant.

## Sources

### Primary (HIGH confidence)
- Verilator 5.008 local installation -- all lint flags, exit codes, and waiver behavior tested directly
- [Verilator Errors and Warnings documentation](https://verilator.org/guide/latest/warnings.html) -- warning categories, suppression methods, waiver files
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide) -- official hooks format, PostToolUse schema, matcher syntax, infinite loop prevention
- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference) -- plugin hooks.json format, `${CLAUDE_PLUGIN_ROOT}`, event-keyed structure
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) -- complete event list, JSON input schema, exit code semantics
- Project `generated/ALU.v` and `generated/TrivialModule.v` -- empirical lint testing

### Secondary (MEDIUM confidence)
- [Verilog Lint with Verilator (Project F)](https://projectf.io/posts/verilog-lint-with-verilator/) -- practical lint guide, `-Wall` usage patterns
- [Verilator Waivers blog post](https://wallento.cs.hm.edu/post/20200612-verilator-waivers/) -- waiver file syntax and best practices
- [LLVM CIRCT discussion on Chisel-generated Verilog lint warnings](https://discourse.llvm.org/t/problems-with-verilator-linting-warning-in-chisel-generated-code/69223) -- confirms UNUSEDSIGNAL for clock/reset is a known Chisel pattern
- [DEV Community article on PostToolUse hook loops](https://dev.to/ji_ai/writing-a-claude-code-book-with-claude-code-when-posttooluse-hooks-loop-25-times-4h46) -- real-world infinite loop case study

### Tertiary (LOW confidence)
- None -- all findings verified through primary or secondary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Verilator 5.008 installed and all flags verified through direct testing
- Architecture: HIGH -- hooks format verified against official Anthropic documentation; lint script pattern verified empirically
- Pitfalls: HIGH -- all pitfalls discovered through direct testing (lint on actual generated Verilog) or verified against official docs
- Auto-fix loop: MEDIUM -- the loop design is sound but actual Verilator-to-Chisel error mapping depends on specific error types encountered at runtime

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (stable -- Verilator 5.008 and Claude Code hooks API are not changing)
