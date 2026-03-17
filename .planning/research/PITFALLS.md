# Domain Pitfalls

**Domain:** Automated Chisel-to-Verified-Verilog Pipeline (Claude Code Plugin)
**Researched:** 2026-03-16

## Critical Pitfalls

Mistakes that cause rewrites or major issues.

### Pitfall 1: sbt Cold Start Latency

**What goes wrong:** First `sbt runMain` invocation takes 30-120 seconds to download dependencies, resolve firtool, and JIT-compile. Users (or Claude) may interpret this as a hang or failure.

**Why it happens:** sbt/JVM startup cost is inherently high; firtool-resolver downloads the firtool binary on first run; dependency resolution hits Maven Central.

**Consequences:** Pipeline appears broken on first run; timeout in hooks/scripts; users abandon tool.

**Prevention:**
- Run `sbt update` during plugin setup / first-use initialization to pre-download all dependencies
- Set generous timeouts in compile scripts (120s minimum for first run, 30s for subsequent)
- Add progress indicators or status messages to scripts
- Consider a `/chip:setup` skill that initializes the sbt project

**Detection:** First compile takes >60s; error messages about connection timeouts or unresolved dependencies.

### Pitfall 2: Wrong Chisel API (chisel3 vs org.chipsalliance)

**What goes wrong:** Generated Chisel code uses deprecated APIs that don't exist in Chisel 7.x. Common errors: `emitVerilog is not a member of circt.stage.ChiselStage`.

**Why it happens:** LLM training data includes older Chisel 3.x/5.x examples; many online tutorials still use the old artifact name `edu.berkeley.cs::chisel3`.

**Consequences:** Compilation fails immediately; confusing error messages about missing members.

**Prevention:**
- Agent system prompts MUST specify: use `import chisel3._` (this is still correct for the DSL), but the build dependency is `org.chipsalliance::chisel`
- Verilog emission MUST use `circt.stage.ChiselStage.emitSystemVerilog` or `emitSystemVerilogFile`, NOT `emitVerilog`
- Include working code examples in the chisel-generator agent prompt
- Include a reference `Generate.scala` file in the chisel-project template as a known-good example

**Detection:** Compilation errors mentioning "not a member of" or "object chisel3 is not a member of package edu.berkeley.cs".

### Pitfall 3: firtool Version Mismatch

**What goes wrong:** If `CHISEL_FIRTOOL_PATH` is set (or an old firtool is on PATH), it may conflict with the version Chisel expects, producing cryptic FIRRTL compilation errors or segfaults.

**Why it happens:** Chisel 7.x auto-manages firtool, but environment variables or PATH entries can override this. A user who previously installed firtool manually may have a stale version.

**Consequences:** Segfaults during compilation; malformed Verilog output; FIRRTL parse errors.

**Prevention:**
- Do NOT set `CHISEL_FIRTOOL_PATH` unless absolutely necessary
- In compile scripts, explicitly unset the variable: `unset CHISEL_FIRTOOL_PATH`
- Document that Chisel manages firtool automatically
- Verify firtool is NOT in PATH during plugin setup (confirmed not installed on target machine -- this is correct)

**Detection:** Segfaults during sbt run; FIRRTL version mismatch errors; "unsupported annotation" errors.

### Pitfall 4: Verilator Lint Errors That Cannot Be Fixed at Chisel Level

**What goes wrong:** Some Verilator lint warnings/errors originate from firtool's Verilog emission style, not from the Chisel source. The lint-fixer agent loops 3 times changing Chisel code but the Verilog output remains the same.

**Why it happens:** firtool generates Verilog with specific patterns (e.g., `_GEN_*` temporary signals, specific wire naming, always_comb vs always_ff style) that may trigger Verilator warnings. These cannot be changed by modifying Chisel.

**Consequences:** Wasted 3 fix iterations; pipeline reports failure for an unfixable issue; user frustration.

**Prevention:**
- Use firtoolOpts like `-disable-all-randomization` and `-strip-debug-info` to reduce noisy Verilog
- Classify lint messages as "Chisel-fixable" vs "firtool-generated"; suppress the latter with `-Wno-<WARNING>` flags
- Allow passing Verilator warning suppressions: `verilator --lint-only -Wno-UNUSED -Wno-UNDRIVEN`
- The lint-fixer agent should recognize when an error is in generated code it cannot control and skip it
- Distinguish between %Error (blocking) and %Warning (non-blocking)

**Detection:** Same lint error persists across all 3 fix iterations with identical Verilator output.

### Pitfall 5: Hook Event Storms

**What goes wrong:** A PostToolUse hook on Write/Edit triggers compilation, which generates new files, which triggers more hooks, creating an infinite loop.

**Why it happens:** Hooks fire on ANY Write/Edit event matching the pattern. If compilation writes to a directory that matches the hook's file pattern, it re-triggers.

**Consequences:** Infinite loop; system hangs; excessive API usage.

**Prevention:**
- Scope hook matchers narrowly: only match writes to `src/main/scala/**/*.scala`, NOT `generated/` or `reports/`
- Use the matcher field precisely: `"matcher": "Write|Edit"` only, and check the file path in the script
- Better approach: do NOT use PostToolUse hooks for compilation. Instead, have the orchestrating skill explicitly call scripts at the right time. Hooks are best for simple formatting/validation, not pipeline orchestration
- If hooks are used, the script should check the file path from stdin JSON and exit early for non-relevant paths

**Detection:** Claude Code shows rapid repeated hook execution; disk I/O spikes; same files keep being overwritten.

## Moderate Pitfalls

### Pitfall 1: sbt Interactive Mode in Non-Interactive Context

**What goes wrong:** sbt enters interactive shell mode when invoked without `--batch` or a specific task. Claude Code hooks and scripts cannot interact with stdin prompts.

**Prevention:** Always use `sbt --batch "task"` or `sbt "task"` format. Never invoke bare `sbt` without a task argument. Set `SBT_OPTS="-Dsbt.supershell=false"` to disable the fancy progress display.

### Pitfall 2: Verilator Version Limitations

**What goes wrong:** Installed Verilator 5.008 (2023) lacks features or lint rules present in newer versions. Generated code may pass lint on 5.008 but fail on newer Verilator versions, or vice versa.

**Prevention:** Document the target Verilator version. For the course assignment, 5.008 is the testing environment. Do not rely on features added after v5.008. The `--lint-only` and `--cc` workflows are stable across versions.

### Pitfall 3: C++ Testbench Compilation Errors

**What goes wrong:** LLM-generated C++ testbench has compilation errors (missing includes, wrong Verilator API usage, incorrect module port names).

**Prevention:**
- Include a testbench template in the testbench-generator agent context
- Verilator generates `V<ModuleName>.h` -- the testbench must `#include "V<ModuleName>.h"` exactly
- Use `Verilated::commandArgs(argc, argv)` for initialization
- Always include `verilated.h` header
- Port names in the C++ testbench must match the Verilog output exactly (case-sensitive)

### Pitfall 4: Module Port Name Mismatches Between Stages

**What goes wrong:** The module spec uses one port naming convention (e.g., `aluOp`), Chisel generates another (e.g., `io_aluOp`), and the testbench uses a third (e.g., `alu_op`).

**Prevention:**
- Chisel wraps all ports in `io` bundle, so Verilog ports become `io_<portName>`
- The testbench generator must read the generated Verilog (or know the Chisel convention) to use correct port names
- Establish a naming convention in the requirement-parser output that flows through all stages
- Consider using firtoolOpt `--lowering-options=disallowPortDeclSharing` for cleaner port names

### Pitfall 5: File Path Confusion Between Plugin Root and Project Root

**What goes wrong:** Scripts reference relative paths that break depending on whether Claude Code invokes them from the plugin directory or the user's project directory.

**Prevention:**
- Use `${CLAUDE_PLUGIN_ROOT}` in all hook commands
- Scripts should use `cd "$(dirname "$0")/.."` to resolve their own location
- Document clearly: plugin root vs chisel-project root vs user's working directory
- All generated output paths should be absolute or relative to a well-defined root

## Minor Pitfalls

### Pitfall 1: Scala Version Mismatch

**What goes wrong:** System Scala is 2.13.13 but build.sbt specifies 2.13.16. sbt downloads the correct version, but first-time resolution adds latency.

**Prevention:** Accept this as normal sbt behavior. The build.sbt Scala version takes precedence. No action needed beyond patience on first build.

### Pitfall 2: Git-Ignored Artifacts Causing Confusion

**What goes wrong:** obj_dir/, generated/, and sbt target/ directories are large and should not be committed, but developers may wonder where outputs went after a clean clone.

**Prevention:** Include a `.gitignore` with clear entries. Add a `/chip:setup` skill that creates output directories.

### Pitfall 3: Testbench Output Format Drift

**What goes wrong:** sim_result.log format deviates from the prescribed `[TEST N] OP: a=X b=Y | expect=Z got=W | PASS/FAIL` pattern.

**Prevention:** Use printf format strings in the C++ testbench with exact format matching. Include the format specification in the testbench-generator agent prompt.

### Pitfall 4: Verilator WIDTH Warnings on Chisel-Generated Verilog

**What goes wrong:** `%Warning-WIDTH` messages from Verilator on code that is functionally correct.

**Prevention:** Chisel generates Verilog with automatic width inference that Verilator may flag. Use `verilator --lint-only -Wno-WIDTH` if these are false positives, or add `/* verilator lint_off WIDTH */` pragmas in a waiver file.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Plugin scaffolding | Incorrect plugin.json schema or directory layout | Validate with `claude --debug`; follow exact structure from official docs |
| Chisel project setup | First sbt invocation extremely slow (dependency download + firtool) | Pre-download dependencies; set 120s timeout |
| Chisel code generation | LLM uses deprecated API (emitVerilog, chisel3 artifact) | Pin exact import patterns and API calls in agent system prompts |
| FIRRTL compilation | firtool path conflict or version mismatch | Unset CHISEL_FIRTOOL_PATH; let Chisel auto-manage |
| Verilator lint | Unfixable firtool-generated warnings treated as errors | Classify warnings; suppress firtool-style warnings with -Wno flags |
| Auto-fix loop | Infinite retry on unfixable errors | Hard 3-attempt limit; error classification |
| Testbench generation | Port name mismatch between Chisel io_ prefix and testbench | Read generated Verilog ports before testbench generation |
| Simulation | Verilator compile error from C++ testbench | Include template with correct includes and API usage |
| Hook automation | PostToolUse event storms from cascading file writes | Narrow matchers; prefer skill-driven orchestration over hooks for pipeline flow |

## Sources

- [Chisel FAQ](https://www.chisel-lang.org/docs/resources/faqs) -- Common migration issues, API changes
- [Chisel issue #4603](https://github.com/chipsalliance/chisel/issues/4603) -- emitVerilog deprecation
- [Chisel installation docs](https://www.chisel-lang.org/docs/installation) -- firtool auto-management, CHISEL_FIRTOOL_PATH
- [Verilator warnings docs](https://verilator.org/guide/latest/warnings.html) -- Warning suppression flags
- [Claude Code hooks guide](https://code.claude.com/docs/en/hooks-guide) -- Hook event behavior, stdin/exit codes
- [CIRCT firtool segfault discussion](https://discourse.llvm.org/t/firtool-v1-114-1-segmentation-fault-with-chisel-7-0-0-rc1/86237) -- Version mismatch consequences

---
*Domain pitfalls for: ChipAgent -- Automated Chisel-to-Verified-Verilog Pipeline*
*Researched: 2026-03-16*
