# Feature Landscape

**Domain:** Modular slash commands, workspace isolation, and environment detection for a Claude Code EDA plugin
**Researched:** 2026-03-19
**Milestone:** v1.1 (Refine -- decompose monolithic pipeline into modular commands)

## Context

v1.0 shipped a monolithic `/chip-agent:generate` pipeline that runs all 7 stages sequentially in a single conversation turn. v1.1 decomposes this into standalone slash commands, adds per-module workspace isolation, and introduces environment detection. This feature landscape covers ONLY the new v1.1 features -- v1.0 capabilities (NL parsing, Chisel generation, compilation, lint, testbench, simulation, reporting) are already built and working.

## Table Stakes

Features users expect from a multi-command plugin with per-module workspace isolation. Missing = the refactoring feels incomplete or the UX regresses from v1.0.

| Feature | Why Expected | Complexity | Depends On (existing) | Notes |
|---------|--------------|------------|----------------------|-------|
| Standalone slash commands for each pipeline stage | The entire point of v1.1. Users must be able to run `/chip-agent:lint` or `/chip-agent:simulate` independently without invoking the full pipeline. | Med | Existing agents, scripts | Each of the 7 pipeline stages (parse, generate-chisel, compile, lint, testbench, simulate, report) becomes its own skill. Not all need their own agent -- lint, compile, simulate are thin wrappers around existing scripts. |
| Refactored `/chip-agent:generate` as orchestrator | The existing end-to-end flow must keep working unchanged from a user perspective. Internally, `generate` delegates to sub-skills rather than inlining all logic. | Med | All standalone commands | Generate skill becomes a sequencer that invokes sub-skills in order. Must preserve the 3-attempt auto-fix retry logic for both lint and simulation stages. |
| `/chip-agent:initialize` environment detection | First-run experience. Users need to know whether their system can run the pipeline before wasting time on a module that will fail at compile. Existing `setup.sh` does parts of this but only runs at install time and also downloads dependencies. | Low | None (greenfield) | Detects Java, sbt, Scala, Verilator, Make, g++ versions and paths. Reports missing or incompatible tools with install guidance. Should be idempotent and fast (no side effects -- detection only, not installation). |
| Per-module workspace isolation | When generating multiple modules (ALU, RegFile, Decoder), their artifacts must not collide. The current flat `generated/` and `sim/` directories cannot handle sequential multi-module work without manual cleanup. | High | compile.sh, lint.sh, simulate.sh | Requires `workspace/<ModuleName>/` structure with spec, generated, sim subdirectories. All scripts must accept workspace path parameters or environment variables. This is the highest-complexity table-stakes item because it touches every script. |
| Spec file as inter-stage contract (Hybrid Option C) | Pipeline stages need to communicate structured data (module name, ports, operations). Currently this data lives only in conversation context, which breaks when running commands standalone. PROJECT.md specifies "Hybrid spec-file communication" as a target. | Med | Workspace isolation, requirement-parser agent | JSON spec file written to `workspace/<ModuleName>/spec.json`. Downstream stages (generate-chisel, testbench, debug) read it from disk rather than depending on conversation history. Simple stages (compile, lint, simulate) do not need the spec -- they work on files directly. |
| Help and command discoverability | Users must know what commands are available and what arguments they accept. | Low | Skill frontmatter | Claude Code provides this natively via `/` autocomplete when skills have good `description` and `argument-hint` frontmatter fields. No custom help command needed -- the platform handles discovery. Each skill's description should be clear enough that Claude can also invoke it automatically when relevant. |
| Consistent error reporting across commands | Each standalone command must produce clear, structured error output that a user (or the orchestrator generate skill) can act on. When lint fails, the output must be parseable to determine what to fix. | Low | All commands | Standardize on: exit code 0 = pass, non-zero = fail. Stdout contains structured results. Already partially done in v1.0 scripts. Formalize the convention across all skills and scripts. |
| Backward-compatible workspace layout | The existing flat `generated/` and `sim/` directories must still work for users who invoke the old-style pipeline without explicitly naming a workspace. | Low | Workspace isolation | Default workspace for unnamed modules falls back to the legacy flat structure. A `--workspace` argument or module name triggers the per-module isolation. Ensures v1.0 muscle memory still works. |

## Differentiators

Features that set the plugin apart from manual EDA workflows. Not expected, but valuable.

| Feature | Value Proposition | Complexity | Depends On | Notes |
|---------|-------------------|------------|------------|-------|
| Intelligent module name routing | When a user says `/chip-agent:lint ALU`, the plugin automatically resolves the module name to its workspace path, finds the Verilog files, and runs lint. No explicit path arguments needed. | Med | Workspace isolation, spec file | Scan `workspace/*/spec.json` to resolve module names. Fall back to asking if ambiguous (multiple workspaces or no match). |
| Spec-aware failure recovery | When lint or simulation fails, the orchestrator re-reads the spec from disk and only re-invokes the failing stage plus its downstream stages, rather than restarting from NL parsing. | Med | Spec file contract | The testbench-generator agent reads `spec.json` from the workspace. The orchestrator tracks which stages succeeded and resumes from the first failure. |
| Machine-readable environment capability output | `/chip-agent:initialize` writes an `env.json` with structured tool versions and boolean capabilities (can_compile, can_lint, can_simulate). Other commands can read it to gracefully degrade (e.g., skip lint if Verilator is not found, with a warning). | Low | Initialize command | JSON file at project root (`.chipagent/env.json` or `workspace/env.json`). Simple schema: tool name, version, path, satisfies-minimum boolean. |
| Incremental build skip | Skip sbt compilation entirely if the Chisel source file has not changed since the last successful build (comparing file modification times). sbt already does incremental compilation internally, but the JVM startup alone takes 5-10 seconds -- skipping the entire invocation saves real time. | Med | Workspace isolation | Compare `.scala` source mtime against `generated/*.v` mtime. If Verilog is newer, skip `compile.sh`. This is a script-level optimization, not application-level caching. |
| Module registry listing | `/chip-agent:list` scans workspaces and shows all modules with their current verification status (parsed, compiled, lint-passed, sim-passed) based on which artifacts exist on disk. | Low | Workspace isolation | Filesystem presence IS the status: `spec.json` = parsed, `*.v` = compiled, `lint-warnings.log` = lint-ran, `sim_result.log` = simulated. No database or state file needed. |
| Debug failure analysis | `/chip-agent:debug <ModuleName>` reads simulation failure logs and cross-references them with the spec and Chisel source to suggest targeted fixes, linking Verilator error output back to the original specification. | Med | Workspace isolation, simulation logs | New agent that reads `workspace/<Module>/sim/logs/sim_result.log`, the spec, and the Chisel source. Produces a diagnosis with specific fix suggestions. |
| Parallel multi-module linting | When the workspace contains multiple completed modules, lint all of them concurrently rather than sequentially. | Low | Workspace isolation, lint command | Each module's Verilog is in its own `workspace/<Module>/generated/` directory. Lint runs are independent and can execute in parallel. |

## Anti-Features

Features to explicitly NOT build in v1.1. These are tempting but counterproductive.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Custom help command | Claude Code already provides `/` autocomplete, skill descriptions, and argument hints. Building a custom `/chip-agent:help` duplicates platform functionality and adds maintenance burden. | Write clear `description` and `argument-hint` frontmatter for each skill. Let Claude Code's native discovery handle the rest. |
| GUI or web dashboard | Out of scope per PROJECT.md constraints. CLI-only through Claude Code. A dashboard adds enormous complexity without matching the conversational workflow. | Use structured terminal output with clear formatting. The report stage already produces a clean text summary. |
| Cross-module dependency graph | Tracking inter-module dependencies ("RegFile depends on ALU") across workspaces is build-system territory (FuseSoC, Chipyard). ChipAgent generates modules; sbt handles Scala-level compilation dependencies. | Let sbt resolve Scala compilation dependencies naturally. Top modules pull in sub-modules via Chisel's `Module(new SubModule)` syntax. Document this rather than reimplementing it. |
| Persistent state machine across sessions | Tracking "ALU is at lint stage, RegFile is at simulate stage" introduces cross-session state management. Claude Code conversations are stateless between sessions. Persisted state creates synchronization problems. | Use filesystem presence as implicit state: `spec.json` exists = parsed, `*.v` exists = compiled, `sim_result.log` exists = simulated. The filesystem IS the state machine. No database, no state file, no synchronization bugs. |
| Interactive step-by-step pipeline mode | Pausing at every stage for confirmation (beyond the existing Step 1.5 spec confirmation) adds friction without value. The 3-attempt auto-fix already handles most failures automatically. | Keep the confirm-once-then-run-to-completion pattern from v1.0. Standalone commands provide manual control when users want to inspect intermediate results. |
| Plugin self-update mechanism | npm handles updates via `npm update chip-agent`. Building custom update logic reinvents package management. | Bump `version` in `plugin.json` and `package.json`. npm distribution handles the rest. |
| File watch / auto-re-run mode | Automatically re-running pipeline stages when source files change sounds useful but creates infinite loops with the existing PostToolUse hook (this nearly happened in v1.0 with the compile hook). | Keep explicit invocation via slash commands. The existing PostToolUse hook on Write/Edit for compile.sh is the right level of automation -- it triggers on agent-written files, not on all file changes. |
| Sophisticated caching (hash-based, content-addressable) | sbt already has incremental compilation. Verilator compilation is fast (seconds). Adding a hash-based cache layer adds complexity far exceeding the time savings. | Use simple file mtime comparison for skip-if-unchanged checks. If the output file exists and is newer than the input, skip the stage. No cache invalidation logic needed. |
| Agent teams / parallel pipeline stages | Claude Code supports agent teams, but the pipeline stages are inherently sequential (compile before lint, lint before simulate). Parallelizing independent modules is simple shell-level parallelism, not agent-team orchestration. | For multi-module parallelism, use simple script-level `&` or `parallel`. Save agent teams for genuinely independent analytical tasks. |

## Feature Dependencies

```
/chip-agent:initialize  (no dependencies -- runs independently, writes env.json)

Workspace Isolation Convention (directory structure + script parameter changes)
  |
  +-- Spec File Contract (spec.json as inter-stage communication)
  |     |
  |     +-- /chip-agent:parse  (NL input -> spec.json in workspace)
  |     |     |
  |     |     +-- /chip-agent:generate-chisel  (spec.json -> .scala source)
  |     |           |
  |     |           +-- /chip-agent:compile  (.scala -> .v in workspace/generated/)
  |     |                 |
  |     |                 +-- /chip-agent:lint  (.v files -> lint pass/fail)
  |     |                 |
  |     |                 +-- /chip-agent:testbench  (spec.json + .v -> .cpp testbench)
  |     |                       |
  |     |                       +-- /chip-agent:simulate  (.v + .cpp -> sim_result.log)
  |     |                             |
  |     |                             +-- /chip-agent:report  (sim_result.log -> formatted output)
  |     |
  |     +-- /chip-agent:debug  (spec.json + sim_result.log -> diagnosis)
  |
  +-- /chip-agent:list  (scans workspace directories -> module status table)

/chip-agent:generate  (orchestrator -- invokes the full chain above sequentially)
  Depends on: ALL standalone commands
  Preserves: Step 1.5 user confirmation, 3-attempt auto-fix for lint and sim
```

Critical path for implementation: Workspace Isolation -> Spec File Contract -> Script Parameterization -> Standalone Skills -> Orchestrator Refactor.

## Workspace Directory Structure

Based on research of EDA workspace isolation patterns (FuseSoC build trees with separate `work_root`, Chipyard per-generator directory layout, Verilator `--Mdir` for per-module build isolation):

```
workspace/
  <ModuleName>/                    # Per-module isolation boundary
    spec.json                      # Inter-stage contract (JSON from parser)
    generated/                     # Verilog output (--target-dir per module)
      <ModuleName>.v
      <ModuleName>.sv
      chisel-warnings.vlt          # Verilator waiver file if needed
      lint-warnings.log
    sim/                           # Simulation artifacts
      tb_<ModuleName>.cpp          # C++ testbench
      obj_dir/                     # Verilator build (isolated via --Mdir)
        V<ModuleName>              # Simulation binary
        V<ModuleName>.mk
      logs/
        sim_result.log             # Verification results
```

Key design decisions:
- **Chisel source stays in `chisel-project/src/main/scala/chipagent/`** because sbt compilation requires a single project root with a single `build.sbt`. Cannot split Scala sources across workspace directories. The workspace is for outputs and metadata, not Scala source.
- **`generated/` uses `--target-dir workspace/<Module>/generated/`** to isolate Verilog output per module, overriding the default flat `generated/` directory.
- **`sim/obj_dir/` uses `--Mdir workspace/<Module>/sim/obj_dir/`** to isolate Verilator build artifacts per module, preventing `V<ModuleName>.mk` collisions.
- **Cleanup is `rm -rf workspace/<ModuleName>/`** -- simple and complete. No partial cleanup needed.
- **Legacy compatibility**: When no module name is specified, fall back to the existing flat `generated/` and `sim/` directories. This preserves v1.0 behavior for simple single-module workflows.

## Slash Command Naming

Based on Claude Code plugin conventions (kebab-case names, `plugin-name:command-name` namespacing for plugins, skills as directories with `SKILL.md`):

| Command | Skill Path | Purpose | Needs Agent | disable-model-invocation |
|---------|-----------|---------|-------------|--------------------------|
| `/chip-agent:initialize` | `skills/initialize/SKILL.md` | Environment detection and validation | No | true (manual only) |
| `/chip-agent:parse` | `skills/parse/SKILL.md` | NL description to JSON spec | Yes (requirement-parser) | true |
| `/chip-agent:generate-chisel` | `skills/generate-chisel/SKILL.md` | JSON spec to Chisel source | Yes (chisel-generator) | true |
| `/chip-agent:compile` | `skills/compile/SKILL.md` | Chisel to Verilog via sbt | No (script wrapper) | true |
| `/chip-agent:lint` | `skills/lint/SKILL.md` | Verilator lint check | No (script wrapper) | true |
| `/chip-agent:testbench` | `skills/testbench/SKILL.md` | Generate C++ testbench | Yes (testbench-generator) | true |
| `/chip-agent:simulate` | `skills/simulate/SKILL.md` | Run Verilator simulation | No (script wrapper) | true |
| `/chip-agent:report` | `skills/report/SKILL.md` | Format verification report | No (text formatting) | true |
| `/chip-agent:generate` | `skills/generate/SKILL.md` | Full pipeline orchestrator | Yes (delegates to above) | true |
| `/chip-agent:debug` | `skills/debug/SKILL.md` | Analyze simulation failures | Yes (new debug agent) | true |
| `/chip-agent:list` | `skills/list/SKILL.md` | Show workspace modules | No (filesystem scan) | true |

All commands use `disable-model-invocation: true` because they have side effects (running builds, writing files) and should only be invoked explicitly by the user or by the orchestrator skill. Claude should not autonomously decide to compile or simulate.

Migration note: The existing `skills/generate.md` (flat file in the legacy commands format) should migrate to `skills/generate/SKILL.md` (directory with SKILL.md) to follow the recommended skills format and support future addition of supporting files (e.g., pipeline stage templates, reference documentation).

## Environment Detection Feature Spec

`/chip-agent:initialize` detects and reports system readiness without installing anything.

| Check | Detection Method | Required For | Minimum Version |
|-------|-----------------|-------------|-----------------|
| Java JDK | `java -version 2>&1` | Compilation | 11+ |
| sbt | `sbt --version 2>&1` or read `project/build.properties` | Compilation | 1.10+ |
| Scala | Read `build.sbt` scalaVersion setting (managed by sbt) | Compilation | 2.13.10 exactly |
| Verilator | `verilator --version 2>&1` | Lint + simulation | 5.008+ |
| Make | `make --version 2>&1` | Simulation (builds Verilator model) | Any |
| g++ / C++ compiler | `g++ --version 2>&1` or `c++ --version 2>&1` | Simulation (compiles testbench) | C++17 support |
| firtool | Auto-managed by Chisel 3.6.x firtool-resolver | Informational only | N/A |

Output: Human-readable summary to stdout AND structured JSON to `.chipagent/env.json`:

```json
{
  "timestamp": "2026-03-19T12:00:00Z",
  "tools": {
    "java":      { "found": true, "version": "17.0.2", "path": "/usr/bin/java",      "satisfies": true },
    "sbt":       { "found": true, "version": "1.10.7", "path": "/usr/bin/sbt",       "satisfies": true },
    "scala":     { "found": true, "version": "2.13.10", "source": "build.sbt",       "satisfies": true },
    "verilator": { "found": true, "version": "5.024",  "path": "/usr/bin/verilator", "satisfies": true },
    "make":      { "found": true, "version": "4.3",    "path": "/usr/bin/make",      "satisfies": true },
    "gpp":       { "found": true, "version": "11.4.0", "path": "/usr/bin/g++",       "satisfies": true }
  },
  "capabilities": {
    "can_compile": true,
    "can_lint": true,
    "can_simulate": true
  },
  "overall": "ready"
}
```

Compared to the existing `setup.sh`: initialize is detection-only (no `sbt update`, no dependency download). It runs in seconds, not minutes. `setup.sh` remains available for actual first-time installation but is separate from detection.

## MVP Recommendation

Prioritize for v1.1 in this order (based on dependency chain):

1. **Workspace isolation directory structure + script parameterization** -- Foundation for everything else. Without per-module isolation, standalone commands have nowhere to read/write without collisions. Update `compile.sh`, `lint.sh`, `simulate.sh` to accept workspace path arguments.
2. **Spec file as inter-stage contract** -- Required for standalone commands to work without conversation context. The parser writes `spec.json`; the generator and testbench agents read it.
3. **Standalone slash commands (script-wrappers first)** -- Start with compile, lint, simulate, report (thin wrappers around parameterized scripts). Then add parse, generate-chisel, testbench (agent-backed, more complex).
4. **Refactored `/chip-agent:generate` orchestrator** -- Once standalone commands work individually, refactor the generate skill to delegate to them in sequence. Verify the full pipeline still passes the ALU acceptance test.
5. **`/chip-agent:initialize` environment detection** -- Low complexity, high first-run value. Can be built independently and in parallel with items 1-4.

Defer to v1.2+:
- **`/chip-agent:list` module registry**: Nice-to-have, not critical for pipeline function. Simple filesystem scan.
- **`/chip-agent:debug` failure analysis**: Valuable but requires significant prompt engineering for root-cause mapping.
- **Incremental build skip**: sbt already handles incremental compilation internally. The wrapper optimization saves 5-10 seconds of JVM startup -- a polish item.
- **Intelligent module name routing**: Requires workspace scanning conventions to stabilize first.
- **Workspace archival**: Useful for CI integration but not for the primary interactive workflow.

## Sources

- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference) -- Official plugin directory structure, skill format, namespacing with `plugin-name:command-name`, `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}` environment variables, hook event types (HIGH confidence)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) -- Skill frontmatter (`disable-model-invocation`, `allowed-tools`, `argument-hint`, `context: fork`), naming conventions (kebab-case), supporting files in skill directories, `$ARGUMENTS` substitution (HIGH confidence)
- [Command Line Interface Guidelines](https://clig.dev/) -- CLI subcommand design best practices: verb-noun structure, consistent flags, discoverability (HIGH confidence)
- [FuseSoC Documentation](https://fusesoc.readthedocs.io/en/stable/user/overview.html) -- EDA workspace isolation via build trees copied to separate directories, EDAM metadata as tool-agnostic interface between stages (HIGH confidence)
- [Verilator Documentation -- Verilating](https://verilator.org/guide/latest/verilating.html) -- `--Mdir` for per-module build isolation, `--prefix` for naming control, `--binary`/`--exe` build modes (HIGH confidence)
- [Chipyard Documentation](https://chipyard.readthedocs.io/en/stable/Customization/Incorporating-Verilog-Blocks.html) -- Per-generator project directory layout with separate `build.sbt` and source trees (MEDIUM confidence)
- [Edalize EDA Tool Abstraction](https://github.com/olofk/edalize) -- `work_root` workspace isolation pattern, setup/build/run stage separation (MEDIUM confidence)
- [Enforcing JVM Version in SBT](https://www.baeldung.com/scala/sbt-enforcing-jvm-version) -- Java version detection via `sys.props`, build-level enforcement patterns (MEDIUM confidence)
- [Claude Code Customization Guide](https://alexop.dev/posts/claude-code-customization-guide-claudemd-skills-subagents/) -- Community patterns for organizing skills, agents, and hooks in plugins (MEDIUM confidence)

---
*Feature landscape for: ChipAgent v1.1 -- Modular Slash Commands, Workspace Isolation, Environment Detection*
*Researched: 2026-03-19*
*Supersedes: v1.0 feature landscape from 2026-03-16*
