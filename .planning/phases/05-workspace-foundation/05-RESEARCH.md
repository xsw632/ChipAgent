# Phase 5: Workspace Foundation - Research

**Researched:** 2026-03-20
**Domain:** Bash script parameterization, directory structure, Chisel output targeting, .gitignore patterns
**Confidence:** HIGH

## Summary

Phase 5 introduces per-module workspace isolation so each module's artifacts (spec, generated Verilog, testbenches, simulation logs) live in `workspace/<ModuleName>/` subdirectories. The current v1.0 layout uses flat directories (`generated/`, `sim/`, `sim/logs/`) shared across all modules. The workspace pattern replaces this with `workspace/<Module>/generated/`, `workspace/<Module>/sim/`, and `workspace/<Module>/sim/logs/` while keeping the flat layout as the default when no workspace argument is provided.

This is a pure shell-scripting and directory-management task. No new libraries are needed. The core work is: (1) define the workspace subdirectory structure, (2) modify `scripts/compile.sh`, `scripts/lint.sh`, and `scripts/simulate.sh` to accept an optional workspace path argument while defaulting to v1.0 behavior, (3) modify `Generate.scala` to accept module name + target-dir from the script, and (4) update `.gitignore` to cover `workspace/` and per-module `obj_dir/` directories.

**Primary recommendation:** Add a single optional positional argument (`$1`) to each script. When present, it is treated as a workspace root (e.g., `workspace/Foo`). All output paths (GENERATED_DIR, SIM_DIR, LOG_DIR, OBJ_DIR) are derived from that root instead of the flat defaults. When absent, behavior is unchanged from v1.0.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| WKSP-01 | Each generated module gets its own `workspace/<ModuleName>/` directory containing spec, generated Verilog, and simulation artifacts | Workspace directory structure pattern (see Architecture Patterns); mkdir -p in scripts; spec.json placeholder subdirectory |
| WKSP-02 | Scripts (compile.sh, lint.sh, simulate.sh) accept optional workspace path arguments while defaulting to v1.0 flat directory layout | Script parameterization pattern (see Architecture Patterns); backward-compatible `$1` argument handling |
| WKSP-03 | `workspace/` directory and per-module `obj_dir/` artifacts are gitignored | Gitignore update pattern (see Architecture Patterns); two new lines in `.gitignore` |
</phase_requirements>

## Standard Stack

### Core

No new libraries. This phase modifies existing bash scripts and one Scala file.

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 5.x | Script parameterization | Already used for all scripts |
| sbt | 1.10.7 | Build tool (unchanged) | Pinned in build.properties |
| Chisel | 3.6.1 | `--target-dir` argument | Already supports output redirection |

### Supporting

None needed. This phase is pure refactoring of existing scripts and directory layout.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Positional arg `$1` for workspace path | `--workspace` flag with getopt | Overkill for a single optional argument; positional is simpler and matches existing `simulate.sh` pattern (already takes `$1` as module name) |
| Per-module obj_dir inside workspace | Shared obj_dir with module prefixes | Per-module obj_dir is cleaner; Verilator `--Mdir` already supports custom paths |
| Symlinks from flat dirs to workspace | Actual directory creation | Symlinks add fragility and cross-platform issues; direct mkdir is simpler |

## Architecture Patterns

### Workspace Directory Structure

Each module gets an isolated workspace directory with subdirectories mirroring the v1.0 flat layout:

```
workspace/
  Foo/
    spec.json              # Structured spec (written by Phase 6 requirement-parser)
    generated/             # Chisel -> Verilog output
      Foo.v
      Foo.fir
      Foo.anno.json
      chisel-warnings.vlt  # Copied or generated per-module
      lint-warnings.log
    sim/
      tb_Foo.cpp           # C++ testbench
      obj_dir/             # Verilator build artifacts (per-module)
        VFoo               # Simulation binary
      logs/
        sim_result.log     # Simulation results
  Bar/
    ...                    # Same structure for another module
```

Key design points:
- `spec.json` lives at workspace root (not in a subdirectory) for easy access by Phase 6 agents
- `obj_dir/` is inside `sim/` (matching v1.0 pattern) but scoped per-module
- `chisel-warnings.vlt` waiver file may need to be copied into each module's generated/ dir, OR scripts reference the global one. Recommendation: reference the global `$PLUGIN_ROOT/generated/chisel-warnings.vlt` as fallback, but check for per-module waiver first.

### Pattern 1: Script Parameterization (Backward-Compatible)

**What:** Each script accepts an optional first argument that redirects all output paths to a workspace directory.
**When to use:** Every script modification in this phase.

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if command -v cygpath >/dev/null 2>&1; then
  PLUGIN_ROOT="$(cygpath -m "$PLUGIN_ROOT")"
fi

# --- Workspace-aware path resolution ---
WORKSPACE_DIR="${1:-}"

if [ -n "$WORKSPACE_DIR" ]; then
  # Resolve to absolute path if relative
  case "$WORKSPACE_DIR" in
    /*) ;;  # Already absolute
    *)  WORKSPACE_DIR="$PLUGIN_ROOT/$WORKSPACE_DIR" ;;
  esac
  GENERATED_DIR="$WORKSPACE_DIR/generated"
  SIM_DIR="$WORKSPACE_DIR/sim"
  LOG_DIR="$WORKSPACE_DIR/sim/logs"
  OBJ_DIR="$WORKSPACE_DIR/sim/obj_dir"
else
  # v1.0 flat defaults
  GENERATED_DIR="$PLUGIN_ROOT/generated"
  SIM_DIR="$PLUGIN_ROOT/sim"
  LOG_DIR="$SIM_DIR/logs"
  OBJ_DIR="$SIM_DIR/obj_dir"
fi

mkdir -p "$GENERATED_DIR" "$SIM_DIR" "$LOG_DIR"
```

### Pattern 2: compile.sh Workspace Mode

**What:** compile.sh passes workspace-derived `--target-dir` to sbt/Generate.scala.
**When to use:** The core compile.sh modification.

When invoked as `scripts/compile.sh workspace/Foo`:
1. GENERATED_DIR becomes `$PLUGIN_ROOT/workspace/Foo/generated`
2. sbt command becomes: `sbt --batch "runMain chipagent.Generate --target-dir $GENERATED_DIR"`
3. Module name must also be passed. Two options:
   - **Option A (recommended):** Extract module name from workspace path basename: `MODULE=$(basename "$WORKSPACE_DIR")`
   - **Option B:** Require a second argument for module name

Recommendation: Option A. The workspace directory name IS the module name by convention. This is enforced at the directory creation level.

```bash
# In compile.sh, after workspace resolution:
if [ -n "$WORKSPACE_DIR" ]; then
  MODULE=$(basename "$WORKSPACE_DIR")
  $TIMEOUT_CMD sbt --batch "runMain chipagent.Generate --module $MODULE --target-dir $GENERATED_DIR" > "$LOG" 2>&1 || EXIT_CODE=$?
else
  # v1.0 default: compile all modules to flat generated/
  $TIMEOUT_CMD sbt --batch "runMain chipagent.Generate --target-dir $OUTPUT_DIR" > "$LOG" 2>&1 || EXIT_CODE=$?
fi
```

### Pattern 3: simulate.sh Workspace Mode

**What:** simulate.sh places obj_dir and logs inside workspace.
**When to use:** The simulate.sh modification.

Current simulate.sh takes `$1` as MODULE name. With workspace, the calling convention changes:
- `scripts/simulate.sh ALU` -- v1.0 mode (flat dirs)
- `scripts/simulate.sh workspace/Foo` -- workspace mode (isolated dirs)

Detection: if `$1` contains a `/`, treat as workspace path; otherwise treat as module name (v1.0 mode).

```bash
ARG="${1:-}"
if [[ "$ARG" == */* ]]; then
  # Workspace mode
  WORKSPACE_DIR="$ARG"
  case "$WORKSPACE_DIR" in
    /*) ;;
    *)  WORKSPACE_DIR="$PLUGIN_ROOT/$WORKSPACE_DIR" ;;
  esac
  MODULE=$(basename "$WORKSPACE_DIR")
  GENERATED_DIR="$WORKSPACE_DIR/generated"
  SIM_DIR="$WORKSPACE_DIR/sim"
  LOG_DIR="$WORKSPACE_DIR/sim/logs"
  OBJ_DIR="$WORKSPACE_DIR/sim/obj_dir"
else
  # v1.0 mode
  MODULE="${ARG:-ALU}"
  GENERATED_DIR="$PLUGIN_ROOT/generated"
  SIM_DIR="$PLUGIN_ROOT/sim"
  LOG_DIR="$SIM_DIR/logs"
  OBJ_DIR="$SIM_DIR/obj_dir"
fi
```

### Pattern 4: Workspace Creation Helper

**What:** A small function or script snippet that creates the full workspace directory tree for a module.
**When to use:** Before any pipeline stage that writes to workspace.

```bash
# Create workspace structure for a module
create_workspace() {
  local ws="$1"
  mkdir -p "$ws/generated" "$ws/sim/logs"
}
```

This could live in each script's preamble or be factored into a shared function. Given there are only 3 scripts, inline `mkdir -p` is simpler than a shared include file.

### Anti-Patterns to Avoid

- **Moving Scala sources into workspace/**: sbt requires sources in `chisel-project/src/`. This is an explicit out-of-scope decision (see REQUIREMENTS.md). Only outputs go to workspace.
- **Per-module sbt projects**: sbt startup cost is 5-10 seconds. Multiplying that per module is wasteful. All modules share the same sbt project.
- **Hardcoding workspace path in Generate.scala**: The `--target-dir` argument already handles this via CLI. Do not add workspace awareness to Scala code.
- **Breaking the flat layout**: The v1.0 flat layout must keep working. Scripts without arguments must produce the same behavior as before.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Output directory targeting | Custom file-copy logic | Chisel `--target-dir` CLI argument | Already supported by `emitVerilog`; just pass the right path |
| Per-module Verilator build isolation | Shared obj_dir with naming prefixes | Verilator `--Mdir` flag | Already supported; cleanly separates build artifacts per module |
| Path resolution (relative/absolute) | Custom path parser | Bash `case` on leading `/` + `$PLUGIN_ROOT` prefix | Standard shell pattern; no library needed |
| Workspace detection (is arg a workspace?) | Regex or flag parsing | Check if `$1` contains `/` | Simple heuristic that distinguishes `ALU` from `workspace/ALU` |

**Key insight:** All the tools already support directory redirection via CLI flags. The task is purely wiring those flags to a new calling convention.

## Common Pitfalls

### Pitfall 1: sbt Working Directory vs Target Directory

**What goes wrong:** `Generate.scala` uses a relative `--target-dir` like `../generated`. If the script changes the working directory, the relative path resolves differently.
**Why it happens:** `cd "$PROJECT_DIR"` in compile.sh changes cwd before running sbt. Relative paths are resolved from sbt's working directory (which is `chisel-project/`).
**How to avoid:** Always pass absolute paths to `--target-dir`. The script should resolve `$GENERATED_DIR` to an absolute path before passing it to sbt.
**Warning signs:** Files appearing in unexpected directories; "no .v files found" error after seemingly successful compilation.

### Pitfall 2: simulate.sh Argument Collision

**What goes wrong:** Current `simulate.sh` takes `$1` as module name (e.g., `ALU`). Adding workspace support on `$1` changes the calling convention.
**Why it happens:** The argument now has dual meaning: a bare name vs. a workspace path.
**How to avoid:** Use the `/` detection heuristic: if `$1` contains `/`, it's a workspace path; otherwise it's a v1.0 module name. This is robust because module names are PascalCase identifiers (no slashes).
**Warning signs:** Passing `workspace/Foo` and having it treated as module name "workspace/Foo".

### Pitfall 3: Chisel Waiver File Not Found in Workspace

**What goes wrong:** `lint.sh` looks for `chisel-warnings.vlt` in `$GENERATED_DIR`. In workspace mode, this file doesn't exist yet because Chisel only creates it in the first compilation target.
**Why it happens:** The waiver file is Chisel-version-specific, not module-specific. It gets created in whichever `--target-dir` is used for the first compilation.
**How to avoid:** Check for waiver file in workspace's generated/ first, then fall back to `$PLUGIN_ROOT/generated/chisel-warnings.vlt`. The waiver file content is the same regardless of module.
**Warning signs:** Lint warnings about Chisel-internal signals that were previously suppressed.

### Pitfall 4: Testbench Source Location

**What goes wrong:** Testbench `.cpp` files currently live in `sim/` (flat). With workspace mode, they move to `workspace/<Module>/sim/`. But the Verilator `--exe` flag needs the correct path.
**Why it happens:** simulate.sh hardcodes `$SIM_DIR/tb_$MODULE.cpp` which works in flat mode but needs updating for workspace mode.
**How to avoid:** Let the workspace path resolution handle this naturally. `SIM_DIR` becomes `$WORKSPACE_DIR/sim` in workspace mode, so `$SIM_DIR/tb_$MODULE.cpp` resolves correctly.
**Warning signs:** "file not found" errors during Verilator compilation.

### Pitfall 5: .gitignore Glob Depth

**What goes wrong:** Adding `workspace/` to .gitignore may be too broad (ignoring the directory entry itself) or too narrow (missing nested artifacts).
**Why it happens:** Git's gitignore patterns have specific semantics. `workspace/` ignores the entire directory tree. But if we want to track `workspace/.gitkeep` or any structural files, a blanket ignore won't work.
**How to avoid:** Use `workspace/` to ignore everything inside. Since workspace contents are all generated (reproducible by running scripts), nothing inside needs tracking. Add a comment explaining this.
**Warning signs:** `git status` showing untracked files under `workspace/`.

## Code Examples

### compile.sh with Workspace Support

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if command -v cygpath >/dev/null 2>&1; then
  PLUGIN_ROOT="$(cygpath -m "$PLUGIN_ROOT")"
fi
if [ -z "$PLUGIN_ROOT" ]; then
  echo "ERROR: Could not determine plugin root directory." >&2
  exit 1
fi
PROJECT_DIR="$PLUGIN_ROOT/chisel-project"

# --- Workspace-aware path resolution ---
WORKSPACE_ARG="${1:-}"
if [ -n "$WORKSPACE_ARG" ]; then
  case "$WORKSPACE_ARG" in
    /*) WORKSPACE_DIR="$WORKSPACE_ARG" ;;
    *)  WORKSPACE_DIR="$PLUGIN_ROOT/$WORKSPACE_ARG" ;;
  esac
  MODULE=$(basename "$WORKSPACE_DIR")
  OUTPUT_DIR="$WORKSPACE_DIR/generated"
else
  OUTPUT_DIR="$PLUGIN_ROOT/generated"
  MODULE=""
fi

export SBT_OPTS="-Dsbt.supershell=false"
mkdir -p "$OUTPUT_DIR"

LOG=$(mktemp 2>/dev/null || echo "${TEMP:-/tmp}/chipagent-compile-$$.log")
trap "rm -f \"$LOG\"" EXIT

echo "Compiling Chisel to Verilog..."
cd "$PROJECT_DIR"

EXIT_CODE=0
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout 120"
elif timeout --version >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout 120"
else
  TIMEOUT_CMD=""
fi

if [ -n "$MODULE" ]; then
  $TIMEOUT_CMD sbt --batch "runMain chipagent.Generate --module $MODULE --target-dir $OUTPUT_DIR" > "$LOG" 2>&1 || EXIT_CODE=$?
else
  $TIMEOUT_CMD sbt --batch "runMain chipagent.Generate --target-dir $OUTPUT_DIR" > "$LOG" 2>&1 || EXIT_CODE=$?
fi

if [ "$EXIT_CODE" -eq 0 ]; then
  SV_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.sv" -o -name "*.v" \) 2>/dev/null | wc -l)
  if [ "$SV_COUNT" -gt 0 ]; then
    echo "Compilation successful:"
    ls "$OUTPUT_DIR"/*.sv "$OUTPUT_DIR"/*.v 2>/dev/null
  else
    echo "WARNING: sbt exited 0 but no .v files found in $OUTPUT_DIR"
    cat "$LOG"
    exit 1
  fi
else
  echo "BUILD ERROR: $(date -Iseconds)"
  echo "---"
  cat "$LOG"
  echo "---"
  exit 1
fi
```

### .gitignore Additions

```gitignore
# Per-module workspace directories (all generated, reproducible)
workspace/
```

Note: `obj_dir/` is already covered by the existing `sim/obj_dir/` entry, but in workspace mode the path changes. The `workspace/` blanket ignore handles this. The existing `obj_dir/` line should also be kept for backward compatibility.

### Generate.scala Already Supports Module + Target-Dir

The current Generate.scala already handles `--module` and `--target-dir` arguments. No changes needed to the Scala code for basic workspace support. The script just needs to pass the right arguments.

## State of the Art

| Old Approach (v1.0) | Current Approach (v1.1) | Impact |
|---------------------|-------------------------|--------|
| Flat `generated/` shared by all modules | Per-module `workspace/<Mod>/generated/` | Modules no longer clobber each other's artifacts |
| Flat `sim/` with shared obj_dir | Per-module `workspace/<Mod>/sim/obj_dir/` | Verilator builds don't conflict |
| No module isolation | Full artifact isolation | Enables Phase 6 skills to operate on specific modules |
| Script arguments: none (compile) or module name (simulate) | Optional workspace path argument | Backward compatible; future skills pass workspace paths |

## Open Questions

1. **Waiver file strategy**
   - What we know: `chisel-warnings.vlt` is a Chisel-version-specific waiver file, not module-specific. It suppresses known Chisel-emitted lint warnings.
   - What's unclear: Should each workspace get a copy, or should scripts always reference the global one?
   - Recommendation: Reference the global `$PLUGIN_ROOT/generated/chisel-warnings.vlt` from lint.sh regardless of workspace mode. If a per-module waiver exists in `$GENERATED_DIR/chisel-warnings.vlt`, prefer it. This handles both cases.

2. **cpu_test_template.h location**
   - What we know: `sim/cpu_test_template.h` is a shared header for CPU-type testbenches. Testbench .cpp files include it.
   - What's unclear: In workspace mode, should testbenches reference this via absolute path or should it be copied?
   - Recommendation: Testbenches should use an absolute include path (`-I$PLUGIN_ROOT/sim` passed as a CFLAGS to Verilator). This avoids copying the header into every workspace.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash scripts (manual verification) |
| Config file | none -- shell script tests |
| Quick run command | `scripts/compile.sh workspace/TrivialModule && ls workspace/TrivialModule/generated/` |
| Full suite command | `scripts/compile.sh workspace/TrivialModule && scripts/lint.sh workspace/TrivialModule && scripts/simulate.sh workspace/TrivialModule` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| WKSP-01 | Module workspace contains spec dir, generated/, sim/logs/ | smoke | `scripts/compile.sh workspace/TrivialModule && test -d workspace/TrivialModule/generated && test -d workspace/TrivialModule/sim/logs` | No -- Wave 0 |
| WKSP-02 | Scripts accept workspace arg and default to flat layout | smoke | `scripts/compile.sh workspace/TrivialModule && scripts/compile.sh` (both must succeed) | No -- Wave 0 |
| WKSP-03 | workspace/ and per-module obj_dir in .gitignore | unit | `grep -q 'workspace/' .gitignore` | No -- Wave 0 |

### Sampling Rate

- **Per task commit:** `scripts/compile.sh workspace/TrivialModule && ls workspace/TrivialModule/generated/TrivialModule.v`
- **Per wave merge:** Full suite: compile + lint + simulate in both workspace and flat modes
- **Phase gate:** All three scripts work in workspace mode AND flat mode; `git status` shows no untracked workspace files

### Wave 0 Gaps

- [ ] `scripts/test-phase5.sh` -- verification script that tests workspace creation, backward compatibility, and gitignore coverage
- [ ] No framework install needed -- bash is the test tool

## Sources

### Primary (HIGH confidence)

- **Codebase inspection** -- Read all 4 scripts (`compile.sh`, `lint.sh`, `simulate.sh`, `setup.sh`), `Generate.scala`, `build.sbt`, `.gitignore`, and all 3 Chisel modules. This is the authoritative source for current behavior.
- **REQUIREMENTS.md** -- WKSP-01, WKSP-02, WKSP-03 definitions
- **ROADMAP.md** -- Phase 5 success criteria (4 items)
- **PROJECT.md** -- Locked decision: "Chisel sources stay in chisel-project/src/; only outputs go to workspace/"
- **CLAUDE.md** -- `emitVerilog` API rules, `--target-dir` usage, sbt `--batch` requirement

### Secondary (MEDIUM confidence)

- **Chisel `--target-dir` behavior** -- Verified from existing `Generate.scala` code that passes `Array("--target-dir", targetDir)` to `emitVerilog`. Files are emitted directly into the specified directory. Confidence is MEDIUM because exact set of emitted files (`.v`, `.fir`, `.anno.json`, `.sv`) varies by Chisel/firtool version.

### Tertiary (LOW confidence)

- None. All findings are based on direct codebase inspection.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new tools, pure bash refactoring of existing scripts
- Architecture: HIGH -- workspace pattern is straightforward directory isolation; all tools already support output path redirection
- Pitfalls: HIGH -- identified from direct analysis of existing code paths and argument handling

**Research date:** 2026-03-20
**Valid until:** indefinite -- this phase depends on project internals, not external library versions
