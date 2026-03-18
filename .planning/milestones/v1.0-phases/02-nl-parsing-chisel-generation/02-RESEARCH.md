# Phase 2: NL Parsing + Chisel Generation - Research

**Researched:** 2026-03-17
**Domain:** NL-to-structured-spec parsing, Chisel 3.6.x code generation, Claude Code plugin skills/agents
**Confidence:** HIGH

## Summary

Phase 2 implements two tightly coupled capabilities: (1) parsing natural language hardware descriptions into a structured module specification, and (2) generating valid Chisel 3.6.1 source code from that specification that compiles on first attempt. The core technical challenge is not the parsing itself -- Claude is the parser -- but rather defining the right **intermediate spec format**, writing the right **skill/agent markdown instructions**, and ensuring the generated Chisel code follows the exact API conventions required by this project's Chisel 3.6.x toolchain.

The approach uses Claude Code's plugin architecture: a **requirement-parser agent** (markdown-defined subagent in `agents/`) that extracts structured specs from natural language, and a **Chisel-generator skill** (or agent) that transforms specs into compilable Scala source files. Both are text-in/text-out operations orchestrated by the existing `generate.md` skill. No external NLP libraries or LLMs are needed -- Claude itself performs all parsing and code generation.

**Primary recommendation:** Define a JSON-based intermediate spec format, implement the parser and generator as Claude Code agents in `agents/`, update the `generate.md` skill to orchestrate them in sequence, and modify `Generate.scala` to accept a module class name argument for dynamic emission.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PARSE-01 | User describes a hardware module in NL and gets a structured spec | Agent definition for `requirement-parser` with clear spec format output |
| PARSE-02 | Parser extracts module name, port list, operations, and constraints | JSON spec schema with explicit fields for each element |
| PARSE-03 | Parser handles RV32I ALU descriptions (ADD/SUB/AND/OR/XOR/SLT + zero flag) | ALU-specific examples in agent prompt, RISC-V operation encoding reference |
| GEN-01 | Agent generates valid Chisel 6.x+ Scala source from parsed spec | Chisel 3.6.1 code patterns with correct imports, IO bundles, `switch`/`is` |
| GEN-02 | Generated Chisel follows project conventions (package, imports, IO bundle) | Convention checklist in agent prompt, verified patterns from existing code |
| GEN-03 | Generator creates Verilog emission entry point (Generate.scala with ChiselStage) | Dynamic module selection pattern for `Generate.scala` |
| GEN-04 | Generated code compiles successfully with sbt on first attempt (or auto-fixes) | Compilation verification via `scripts/compile.sh`, error capture for retry |
</phase_requirements>

## Standard Stack

### Core (Already Established in Phase 1)
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Chisel3 | 3.6.1 | Hardware construction DSL | Project-pinned; `edu.berkeley.cs::chisel3` |
| Scala | 2.13.10 | Chisel host language | Required exact match for `chisel3-plugin` CrossVersion.full |
| sbt | 1.10.7 | Build tool | Pinned in `build.properties` |
| chisel3.stage.ChiselStage | 3.6.1 | Verilog emission | `(new ChiselStage).emitVerilog(...)` -- NOT `circt.stage.ChiselStage` |

### Phase 2 New Components
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| Claude Code Agents | built-in | Subagent definitions for parser/generator | `agents/*.md` files with YAML frontmatter |
| Claude Code Skills | built-in | Updated `generate.md` orchestration skill | `skills/generate.md` entry point |
| JSON spec format | custom | Intermediate representation between NL and Chisel | Structured output from parser agent |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Separate parser + generator agents | Single monolithic skill | Split agents are testable independently, allow retry at each stage |
| JSON spec format | YAML or free-form text | JSON is machine-parseable, enables validation, Claude produces it reliably |
| `switch`/`is` for ALU | `MuxLookup` | `switch`/`is` is more readable, debuggable; `MuxLookup` is more compact |

## Architecture Patterns

### Recommended Project Structure (Phase 2 additions)
```
ChipAgent/
  agents/
    requirement-parser.md    # NL-to-spec subagent definition
    chisel-generator.md      # Spec-to-Chisel subagent definition
  skills/
    generate.md              # Updated: orchestrates parser -> generator -> compile
  chisel-project/
    src/main/scala/chipagent/
      Generate.scala          # Modified: accepts module class name via args
      <ModuleName>.scala      # Generated dynamically per user request
  generated/                  # Emitted .v and .sv files
```

### Pattern 1: Structured Spec Format (PARSE-01, PARSE-02)

**What:** A JSON schema defining the intermediate representation between NL input and Chisel generation.

**When to use:** Every time the parser processes user input, output MUST conform to this schema.

**Example spec for the acceptance test ALU:**
```json
{
  "moduleName": "ALU",
  "description": "RV32I ALU supporting ADD, SUB, AND, OR, XOR, SLT with zero flag",
  "bitWidth": 32,
  "ports": [
    { "name": "a", "direction": "input", "type": "UInt", "width": 32 },
    { "name": "b", "direction": "input", "type": "UInt", "width": 32 },
    { "name": "op", "direction": "input", "type": "UInt", "width": 3 },
    { "name": "result", "direction": "output", "type": "UInt", "width": 32 },
    { "name": "zero", "direction": "output", "type": "Bool", "width": 1 }
  ],
  "operations": [
    { "opcode": 0, "name": "ADD", "expression": "a + b" },
    { "opcode": 1, "name": "SUB", "expression": "a - b" },
    { "opcode": 2, "name": "AND", "expression": "a & b" },
    { "opcode": 3, "name": "OR",  "expression": "a | b" },
    { "opcode": 4, "name": "XOR", "expression": "a ^ b" },
    { "opcode": 5, "name": "SLT", "expression": "(a.asSInt < b.asSInt).asUInt" }
  ],
  "flags": [
    { "name": "zero", "condition": "result === 0.U" }
  ],
  "constraints": []
}
```

**Key decisions in the spec format:**
- `op` width is 3 bits (encodes 6 operations, room for 8)
- Operations list uses Chisel expression syntax directly (generator can paste them)
- SLT uses signed comparison via `.asSInt` cast (RISC-V SLT is signed)
- `Bool` type for single-bit flags vs `UInt(1.W)`

### Pattern 2: Agent-Based Pipeline Orchestration (from generate.md)

**What:** The `generate.md` skill orchestrates two subagents in sequence.

**When to use:** Every `/chip-agent:generate` invocation.

**Flow:**
1. User invokes `/chip-agent:generate <NL description>`
2. `generate.md` skill receives the NL text as `$ARGUMENTS`
3. Skill instructs Claude to invoke `requirement-parser` agent with the NL text
4. Parser agent returns structured JSON spec
5. Skill instructs Claude to invoke `chisel-generator` agent with the spec
6. Generator agent writes `.scala` files and updates `Generate.scala`
7. PostToolUse hook triggers `compile.sh` (already configured)
8. If compilation fails, generator agent receives error and retries (GEN-04)

**Important constraint from Claude Code docs:** Subagents cannot spawn other subagents. So the main conversation (driven by `generate.md` skill) must orchestrate each agent call sequentially.

### Pattern 3: Chisel 3.6.x Module Template (GEN-01, GEN-02)

**What:** The standard Chisel module pattern the generator must produce.

**When to use:** Every generated module MUST follow this exact pattern.

**Example -- generated ALU:**
```scala
package chipagent

import chisel3._
import chisel3.util._

class ALU extends Module {
  val io = IO(new Bundle {
    val a      = Input(UInt(32.W))
    val b      = Input(UInt(32.W))
    val op     = Input(UInt(3.W))
    val result = Output(UInt(32.W))
    val zero   = Output(Bool())
  })

  io.result := 0.U  // default

  switch(io.op) {
    is(0.U) { io.result := io.a + io.b }         // ADD
    is(1.U) { io.result := io.a - io.b }         // SUB
    is(2.U) { io.result := io.a & io.b }         // AND
    is(3.U) { io.result := io.a | io.b }         // OR
    is(4.U) { io.result := io.a ^ io.b }         // XOR
    is(5.U) {                                      // SLT
      io.result := (io.a.asSInt < io.b.asSInt).asUInt
    }
  }

  io.zero := io.result === 0.U
}
```

**Critical conventions:**
- `package chipagent` -- all sources must use this package
- `import chisel3._` and `import chisel3.util._` -- standard imports
- `val io = IO(new Bundle { ... })` -- IO wrapping pattern
- `switch`/`is` from `chisel3.util` -- operation selection
- Default assignment before switch (`io.result := 0.U`) -- prevents latch inference
- Port naming: `io_a`, `io_b`, etc. in generated Verilog

### Pattern 4: Dynamic Module Emission (GEN-03)

**What:** `Generate.scala` must be modified to emit whichever module the pipeline just generated, not just `TrivialModule`.

**When to use:** Every time a new module is generated.

**Approach -- modify Generate.scala to accept module name:**
```scala
package chipagent

import chisel3._
import chisel3.stage.ChiselStage

object Generate extends App {
  val targetDir = if (args.contains("--target-dir")) {
    val idx = args.indexOf("--target-dir")
    args(idx + 1)
  } else {
    "../generated"
  }

  val moduleName = if (args.contains("--module")) {
    val idx = args.indexOf("--module")
    args(idx + 1)
  } else {
    "TrivialModule"
  }

  val module: () => Module = moduleName match {
    case "TrivialModule" => () => new TrivialModule
    case "ALU"           => () => new ALU
    // Generator agent adds new cases here
    case other => throw new IllegalArgumentException(s"Unknown module: $other")
  }

  (new ChiselStage).emitVerilog(
    module(),
    Array("--target-dir", targetDir)
  )
}
```

**Alternative approach (recommended):** Instead of a match statement that needs updating, the generator agent can simply **overwrite Generate.scala entirely** each time, importing and instantiating whichever module was just created. Since this file is small and template-driven, this is simpler and avoids stale match arms.

### Anti-Patterns to Avoid

- **Hand-writing Verilog instead of Chisel:** The pipeline MUST produce Chisel source that compiles to Verilog. Never bypass the Chisel stage.
- **Using `circt.stage.ChiselStage`:** This is for Chisel 5.x+. This project uses Chisel 3.6.1 with `chisel3.stage.ChiselStage`.
- **Using `emitSystemVerilogFile`:** Not available in Chisel 3.6.x. Use `(new ChiselStage).emitVerilog(...)`.
- **Using `"org.chipsalliance" %% "chisel"`:** Wrong coordinates for Chisel 3.x. Use `"edu.berkeley.cs" %% "chisel3"`.
- **Hardcoding module in Generate.scala:** Must be dynamic to support any generated module.
- **Nesting agents:** Subagents cannot spawn other subagents in Claude Code. The main skill must orchestrate sequentially.
- **Omitting default wire assignments:** Chisel requires all outputs be driven. Missing defaults cause compilation errors.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NL parsing | Custom NLP pipeline | Claude itself via agent prompt | Claude is the best NL parser available; the agent prompt constrains output format |
| JSON validation | Custom schema validator | Agent prompt with explicit schema | Claude can validate its own output; retry on malformed JSON |
| Chisel code generation | Template engine | Claude agent with Chisel examples | Claude understands Chisel semantics, not just syntax |
| ALU op encoding | Lookup tables from RISC-V spec | Inline constants in spec | Only 6 operations needed; simple integer opcodes suffice |
| Compilation error parsing | Regex-based error extractor | Pass raw sbt output to agent | Claude can interpret Scala compiler errors and fix them |

**Key insight:** Claude IS the NL parser and the code generator. The "agents" are prompt engineering artifacts -- markdown files that constrain Claude's behavior for specific tasks. No external tools or libraries are needed for Phase 2.

## Common Pitfalls

### Pitfall 1: Wrong Chisel Import/API for Version 3.6.x
**What goes wrong:** Generated code uses `circt.stage.ChiselStage` or `emitSystemVerilogFile`, causing compilation failure.
**Why it happens:** Claude's training data contains both Chisel 3.x and 5.x+ patterns. The newer API is more prominent in recent docs.
**How to avoid:** Agent prompt MUST contain explicit version rules: "Use `chisel3.stage.ChiselStage`, NOT `circt.stage.ChiselStage`". Include the exact import line.
**Warning signs:** `object ChiselStage is not a member of package circt.stage`

### Pitfall 2: Missing `import chisel3.util._` for switch/is
**What goes wrong:** `switch` and `is` are not found, compilation fails.
**Why it happens:** They live in `chisel3.util`, not `chisel3`.
**How to avoid:** Generator agent template MUST include `import chisel3.util._` whenever operations use `switch`/`is` or `MuxLookup`.
**Warning signs:** `not found: value switch` or `not found: value is`

### Pitfall 3: SLT Signed Comparison
**What goes wrong:** SLT uses unsigned comparison, producing wrong results for negative numbers.
**Why it happens:** Chisel `<` on UInt is unsigned. RISC-V SLT is signed comparison.
**How to avoid:** Use `io.a.asSInt < io.b.asSInt` for SLT, then cast back with `.asUInt`.
**Warning signs:** SLT test cases with negative numbers fail in simulation (Phase 4).

### Pitfall 4: Undriven Output Wires
**What goes wrong:** Chisel compilation error: "Output io_result is not fully initialized."
**Why it happens:** If `switch` doesn't cover all cases and no default assignment exists.
**How to avoid:** Always assign a default value to every output BEFORE the switch block.
**Warning signs:** `chisel3.core.Binding$ExpectedHardwareException` or FIRRTL error about uninitialized wires.

### Pitfall 5: Generate.scala Not Updated for New Module
**What goes wrong:** `compile.sh` runs but emits `TrivialModule.v` instead of `ALU.v`.
**Why it happens:** Generator writes the new module file but doesn't update `Generate.scala` to instantiate it.
**How to avoid:** Generator agent MUST update `Generate.scala` as part of its output. Verify by checking the file.
**Warning signs:** `generated/TrivialModule.v` exists but not `generated/ALU.v`.

### Pitfall 6: Package Name Mismatch
**What goes wrong:** sbt compilation error: class not found.
**Why it happens:** Generated module uses wrong package or Generate.scala references wrong class.
**How to avoid:** ALL Scala sources MUST use `package chipagent`. Generator agent MUST enforce this.
**Warning signs:** `not found: type ALU` in sbt output.

### Pitfall 7: Agent Prompt Too Vague
**What goes wrong:** Parser produces inconsistent spec formats; generator produces non-compilable code.
**Why it happens:** Agent markdown instructions don't include enough constraints or examples.
**How to avoid:** Include complete working examples in agent prompts. Show the exact JSON format. Show the exact Chisel template.
**Warning signs:** Intermittent compilation failures, inconsistent port naming.

## Code Examples

### Agent Definition: requirement-parser.md
```markdown
---
name: requirement-parser
description: Parses natural language hardware descriptions into structured JSON specifications. Use when processing user hardware module descriptions.
tools: Read, Grep, Glob
model: inherit
---

You are a hardware requirements parser. Given a natural language description
of a digital hardware module, extract a structured JSON specification.

## Output Format

Return a JSON object with this exact schema:

{json schema here -- see Pattern 1 above}

## Rules

1. Module names are PascalCase (e.g., ALU, RegisterFile, Decoder)
2. Port names are camelCase (e.g., inputA, outputResult)
3. All ports must specify direction, type, and width
4. Operations must include opcode (integer), name, and Chisel expression
5. For ALU modules, op width = ceil(log2(num_operations))
6. SLT operation MUST use signed comparison: (a.asSInt < b.asSInt).asUInt
7. Bool outputs use type "Bool" with width 1

## Examples

[Include 2-3 complete NL -> JSON examples]
```

### Agent Definition: chisel-generator.md
```markdown
---
name: chisel-generator
description: Generates Chisel 3.6.x Scala source code from structured JSON specifications. Use after requirement parsing to produce compilable hardware modules.
tools: Read, Write, Edit, Bash, Grep, Glob
model: inherit
---

You are a Chisel code generator. Given a structured JSON specification,
produce valid Chisel 3.6.1 Scala source code that compiles with sbt.

## CRITICAL API Rules (Chisel 3.6.1)

- Import: `import chisel3._` and `import chisel3.util._`
- Emission: `(new chisel3.stage.ChiselStage).emitVerilog(...)`
- Package: ALL files use `package chipagent`
- DO NOT use `circt.stage.ChiselStage` -- that is Chisel 5.x+
- DO NOT use `emitSystemVerilogFile` -- not available in 3.6.x
- DO NOT use `"org.chipsalliance" %% "chisel"` -- wrong coordinates

## Output Files

1. `chisel-project/src/main/scala/chipagent/<ModuleName>.scala` -- the module
2. `chisel-project/src/main/scala/chipagent/Generate.scala` -- updated emission entry point

## Template

[Include the exact Chisel module template and Generate.scala template]
```

### Updated generate.md Skill (orchestration)
```markdown
# chip-agent:generate

Turn a natural language hardware description into simulation-verified Verilog.

## Pipeline

When invoked with a hardware description:

1. **Parse**: Use the requirement-parser agent to extract a structured JSON spec
   from the user's description. Verify the JSON is valid and complete.

2. **Generate**: Use the chisel-generator agent to produce Chisel source files
   from the JSON spec. The agent writes:
   - The module file to chisel-project/src/main/scala/chipagent/
   - An updated Generate.scala that emits the new module

3. **Compile**: The PostToolUse hook on Write/Edit automatically triggers
   scripts/compile.sh. If compilation fails, read the error output and
   have the chisel-generator agent fix the issues (max 3 attempts).

4. **Verify**: Confirm that generated/*.v contains the expected module file.

## Input

$ARGUMENTS
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `edu.berkeley.cs::chisel3` 3.x | `org.chipsalliance::chisel` 5.x+ | Chisel 5.0 (2023) | Different emission API, different imports |
| `chisel3.stage.ChiselStage` | `circt.stage.ChiselStage` | Chisel 5.x+ | This project uses OLD approach (3.6.1) |
| `emitVerilog` returns string | `emitSystemVerilogFile` writes files | Chisel 5.x+ | This project uses `emitVerilog` which both returns string AND writes files |
| Separate FIRRTL compiler | firtool (MLIR-based) auto-managed | Chisel 3.4+ | firtool-resolver handles download automatically |

**Critical:** This project uses Chisel 3.6.1, NOT Chisel 5.x+. All code patterns, imports, and API calls must target the 3.6.x line. The CLAUDE.md and agent prompts must reinforce this to prevent Claude from defaulting to newer API patterns.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Shell-based integration tests (no ScalaTest/ChiselTest) |
| Config file | None -- tests are bash scripts checking compilation output |
| Quick run command | `scripts/compile.sh` |
| Full suite command | `scripts/compile.sh && test -f generated/ALU.v` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PARSE-01 | NL input produces structured JSON spec | manual (agent output) | N/A -- validated by downstream compilation | N/A |
| PARSE-02 | Spec contains module name, ports, operations, constraints | manual (agent output) | N/A -- validated by downstream compilation | N/A |
| PARSE-03 | Handles ALU with ADD/SUB/AND/OR/XOR/SLT + zero flag | integration | `scripts/compile.sh && test -f generated/ALU.v` | No -- Wave 0 |
| GEN-01 | Generated Chisel is valid Scala | integration | `scripts/compile.sh` exits 0 | Yes (compile.sh exists) |
| GEN-02 | Follows conventions (package, imports, IO) | manual + integration | `grep "package chipagent" chisel-project/src/main/scala/chipagent/ALU.scala` | No -- Wave 0 |
| GEN-03 | Generate.scala updated for new module | integration | `grep "ALU" chisel-project/src/main/scala/chipagent/Generate.scala` | Yes (Generate.scala exists) |
| GEN-04 | Compiles on first attempt | integration | `scripts/compile.sh` exits 0 | Yes (compile.sh exists) |

### Sampling Rate
- **Per task commit:** `scripts/compile.sh` (verify Chisel compiles)
- **Per wave merge:** `scripts/compile.sh && test -f generated/ALU.v && grep "package chipagent" chisel-project/src/main/scala/chipagent/ALU.scala`
- **Phase gate:** Full ALU acceptance test -- generate from NL, compile, verify output

### Wave 0 Gaps
- [ ] `scripts/test-phase2.sh` -- end-to-end test: write ALU spec, generate Chisel, compile, verify output files
- [ ] No ScalaTest infrastructure (acceptable -- compilation success IS the test for this phase)

## Open Questions

1. **Agent invocation pattern in generate.md skill**
   - What we know: Skills can reference agents, but the exact invocation pattern (whether to use `context: fork` or inline delegation) affects context management
   - What's unclear: Whether the generate.md skill should use `context: fork` to run each agent in isolation, or keep everything in the main conversation for better error recovery
   - Recommendation: Keep in main conversation. Error recovery from compilation failures needs the full context of the spec and generated code. Use inline delegation ("use the requirement-parser agent to...").

2. **Generate.scala dynamic module registration**
   - What we know: Two approaches -- match statement vs. full file rewrite
   - What's unclear: Whether the match-statement approach scales to future phases
   - Recommendation: Have the generator agent **rewrite Generate.scala entirely** each time. The file is small (~20 lines) and template-driven. This avoids stale entries and merge conflicts.

3. **Spec format extensibility for Phase 4 (testbench generation)**
   - What we know: The spec needs to carry enough information for testbench generation in Phase 4
   - What's unclear: Exact test vector format needed
   - Recommendation: Include `operations` with explicit Chisel expressions now. Phase 4 can derive test vectors from the operation list. No changes needed to the spec format.

## Sources

### Primary (HIGH confidence)
- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference) -- plugin directory structure, agent/skill integration
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents) -- agent frontmatter fields, tool restrictions, invocation patterns
- [Claude Code Skills](https://code.claude.com/docs/en/skills) -- SKILL.md format, `$ARGUMENTS`, `context: fork`, orchestration
- Project `build.sbt` -- verified Chisel 3.6.1, Scala 2.13.10, `edu.berkeley.cs::chisel3`
- Project `Generate.scala` -- verified `chisel3.stage.ChiselStage` emission pattern
- Project `CLAUDE.md` -- Chisel API rules, pipeline overview

### Secondary (MEDIUM confidence)
- [Chisel FAQ](https://www.chisel-lang.org/docs/resources/faqs) -- `emitVerilog` API, `--target-dir` argument pattern
- [schoeberl/chisel-examples ALU](https://github.com/schoeberl/chisel-examples/blob/master/src/main/scala/simple/Alu.scala) -- ALU `switch`/`is` pattern reference
- [Chisel3 MuxLookup API](https://www.chisel-lang.org/api/latest/chisel3/util/MuxLookup$.html) -- alternative to `switch`/`is`
- [Muxes and Input Selection](https://www.chisel-lang.org/docs/explanations/muxes-and-input-selection) -- Chisel mux patterns
- [RISC-V ISA Quick Reference (Cornell CS 3410)](https://www.cs.cornell.edu/courses/cs3410/2025fa/rsrc/riscv-instructions-2.html) -- ALU operation encoding
- [ucb-bar/riscv-mini](https://github.com/ucb-bar/riscv-mini) -- reference RISC-V Chisel implementation

### Tertiary (LOW confidence)
- [emitVerilog feature request (Issue #1715)](https://github.com/chipsalliance/chisel/issues/1715) -- historical context on ChiselStage API evolution

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- verified against existing project `build.sbt`, `Generate.scala`, and `CLAUDE.md`
- Architecture: HIGH -- Claude Code agent/skill patterns verified against official documentation
- Chisel patterns: HIGH -- ALU pattern verified against multiple open-source examples; API confirmed for 3.6.x
- Pitfalls: HIGH -- based on known Chisel 3.x vs 5.x+ API differences and RISC-V signed comparison requirement

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (stable -- Chisel 3.6.1 and Claude Code plugin APIs are not changing)
