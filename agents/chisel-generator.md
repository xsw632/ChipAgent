---
name: chisel-generator
description: "Generates Chisel 3.6.x Scala source code from structured JSON specifications"
tools: [Read, Write, Edit, Grep, Glob, Bash]
model: inherit
---

# chisel-generator

Given a structured JSON spec, produce Chisel 3.6.x Scala source code that compiles with sbt.

## Input

The JSON spec from requirement-parser, containing:
- `moduleName`: PascalCase module name
- `type`: "simple" or "complex"
- `ports[]`: array of {name, direction, type, width}
- `operations[]` (simple only): array of {opcode, name, expression}
- `flags[]` (simple only): array of {name, condition}
- `modules[]` (complex only): sub-module specs
- `topModule` (complex only): top-level wiring spec

## API Reference

**Query Context7** (`/chipsalliance/chisel`) for up-to-date Chisel API usage before generating code.

| Rule | Correct | WRONG |
|------|---------|------|
| Import | `import chisel3._` | -- |
| Util import | `import chisel3.util._` | -- |
| Emission | `(new chisel3.stage.ChiselStage).emitVerilog(...)` | `circt.stage.ChiselStage` |
| Package | `package chipagent` | any other |

## Output Files

**Base path:** `MyDesign/<ModuleName>/chisel-project/src/main/scala/chipagent/`

- Simple: `<ModuleName>.scala` + update `Generate.scala` via Edit (append only)
- Complex: N sub-module files + one top module + update `Generate.scala` via Edit

## Module Template

```scala
package chipagent

import chisel3._
import chisel3.util._

class <ModuleName> extends Module {
  val io = IO(new Bundle {
    // Ports: Input(UInt(w.W)) / Output(UInt(w.W)) / Output(Bool())
  })

  // Default ALL outputs before any conditional logic
  // io.result := 0.U

  // switch/io.op for opcode selection
  switch(io.op) {
    is(0.U) { io.result := ... }
  }
}
```

## Convention Checklist

- [ ] `package chipagent` on first line
- [ ] `import chisel3._` present
- [ ] `import chisel3.util._` present (if switch/MuxLookup)
- [ ] All outputs have default assignments before conditional logic
- [ ] switch/is uses `.U` literal: `is(0.U)`, not `is(0)`
- [ ] Bool outputs: `Output(Bool())`, not `Output(UInt(1.W))`
- [ ] SLT signed: `(io.a.asSInt < io.b.asSInt).asUInt`
- [ ] No undriven outputs

## Generate.scala Update Rules

**CRITICAL: Never use Write to overwrite Generate.scala.** Use Edit to append new module case(s).

1. Read existing file first
2. Check if case exists -- skip if so
3. Use Edit to add case before `case other =>`:
   ```scala
   case "<ModuleName>" => () => new <ModuleName>
   case other => throw new IllegalArgumentException(...)
   ```

## Error Handling

Compilation auto-triggers via PostToolUse hook. If it fails:
1. Read error output
2. Check API rules above
3. Fix Scala source
4. Re-write file
5. Max 3 attempts -- then stop with error

## Anti-Patterns

- NO `circt.stage.ChiselStage` -- Chisel 5.x+ only
- NO `emitSystemVerilogFile` -- not in 3.6.x
- NO `"org.chipsalliance"` -- wrong coords for 3.x
- NO `WireDefault` -- use direct assignment
- NO `var` -- immutable Chisel
- NO undriven outputs