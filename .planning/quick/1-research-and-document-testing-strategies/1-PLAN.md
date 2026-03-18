---
phase: quick-1
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - sim/cpu_test_template.h
  - agents/chisel-generator.md
  - agents/requirement-parser.md
  - skills/generate.md
  - .planning/quick/1-research-and-document-testing-strategies/1-RESEARCH.md
autonomous: true
requirements: [RESEARCH-1, TEMPLATE-1, AGENT-UPDATE-1]

must_haves:
  truths:
    - "CPU testbenches can include cpu_test_template.h and get instruction encoding helpers, reference emulator, and comparison logic"
    - "Complex CPU modules always get debug ports (debug_pc, debug_reg_addr, debug_reg_data) added by chisel-generator"
    - "The generate pipeline Step 5 handles complex/CPU modules differently from simple modules, using reference model testbenches"
    - "The requirement-parser outputs verification metadata (isa, tier, debug ports) for complex specs"
  artifacts:
    - path: "sim/cpu_test_template.h"
      provides: "RV32I instruction encoding helpers, reference emulator, testbench skeleton"
      min_lines: 150
    - path: "agents/chisel-generator.md"
      provides: "Debug port rules for complex CPU modules"
      contains: "debug_pc"
    - path: "agents/requirement-parser.md"
      provides: "Verification section in complex spec JSON"
      contains: "verification"
    - path: "skills/generate.md"
      provides: "Complex module testbench generation path"
      contains: "cpu_test_template"
    - path: ".planning/quick/1-research-and-document-testing-strategies/1-RESEARCH.md"
      provides: "Research summary document"
      min_lines: 50
  key_links:
    - from: "skills/generate.md"
      to: "sim/cpu_test_template.h"
      via: "Step 5 references template for complex CPU modules"
      pattern: "cpu_test_template"
    - from: "agents/chisel-generator.md"
      to: "agents/requirement-parser.md"
      via: "Generator reads debug port requirements from parser's verification section"
      pattern: "debug_pc"
---

<objective>
Implement the decided CPU testing strategy for ChipAgent: create the C++ reference model template, update all three agents/skills to support complex module verification with debug ports and reference-model testbenches, and document the research findings.

Purpose: Enable ChipAgent to verify complex CPU/processor modules using an embedded C++ RV32I reference emulator with per-instruction smoke tests, beyond the simple struct-based testbench pattern used for combinational modules.

Output: One header-only C++ template, three updated agent/skill files, one research document.
</objective>

<execution_context>
@/home/mingzhenjia/.claude/get-shit-done/workflows/execute-plan.md
@/home/mingzhenjia/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@sim/tb_ALU.cpp
@agents/chisel-generator.md
@agents/requirement-parser.md
@skills/generate.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create C++ CPU test template header</name>
  <files>sim/cpu_test_template.h</files>
  <action>
Create a header-only C++ file at `sim/cpu_test_template.h` with three sections:

**Section 1: RV32I Instruction Encoding Helpers (~40 lines)**
- `constexpr uint32_t r_type(uint32_t funct7, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t rd, uint32_t opcode)` -- assembles R-type instruction from fields
- `constexpr uint32_t i_type(uint32_t imm12, uint32_t rs1, uint32_t funct3, uint32_t rd, uint32_t opcode)` -- I-type
- `constexpr uint32_t s_type(uint32_t imm12, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t opcode)` -- S-type (split imm into [11:5] and [4:0])
- `constexpr uint32_t b_type(uint32_t imm13, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t opcode)` -- B-type (split imm into [12|10:5] and [4:1|11])
- `constexpr uint32_t u_type(uint32_t imm20, uint32_t rd, uint32_t opcode)` -- U-type
- `constexpr uint32_t j_type(uint32_t imm21, uint32_t rd, uint32_t opcode)` -- J-type (split imm into [20|10:1|11|19:12])
- Add convenience aliases: `rv_add(rd, rs1, rs2)`, `rv_addi(rd, rs1, imm)`, `rv_sub(rd, rs1, rs2)`, `rv_and(rd, rs1, rs2)`, `rv_or(rd, rs1, rs2)`, `rv_xor(rd, rs1, rs2)`, `rv_slt(rd, rs1, rs2)`, `rv_beq(rs1, rs2, imm)`, `rv_bne(rs1, rs2, imm)`, `rv_lui(rd, imm)`, `rv_jal(rd, imm)`, `rv_lw(rd, rs1, imm)`, `rv_sw(rs2, rs1, imm)`

**Section 2: Minimal RV32I Reference Emulator (~100 lines)**
- `struct RV32IState { uint32_t pc; uint32_t regs[32]; uint8_t mem[4096]; }` -- minimal CPU state
- `void rv32i_init(RV32IState& s)` -- zero all registers, set pc=0, clear memory. Ensure regs[0]=0.
- `void rv32i_step(RV32IState& s)` -- execute one instruction from `*(uint32_t*)(s.mem + s.pc)`:
  - Decode opcode (bits [6:0]), rd, funct3, rs1, rs2, funct7, and all immediate types
  - Switch on opcode:
    - 0x33 (R-type): ADD, SUB, AND, OR, XOR, SLT, SLL, SRL, SRA based on funct3/funct7
    - 0x13 (I-type ALU): ADDI, ANDI, ORI, XORI, SLTI, SLLI, SRLI, SRAI
    - 0x03 (Load): LW (word-aligned load from mem)
    - 0x23 (Store): SW (word-aligned store to mem)
    - 0x63 (Branch): BEQ, BNE, BLT, BGE, BLTU, BGEU
    - 0x37 (LUI): load upper immediate
    - 0x6F (JAL): jump and link
    - 0x67 (JALR): jump and link register
    - 0x17 (AUIPC): add upper immediate to PC
  - After execution, enforce regs[0] = 0 (hardwired zero)
  - Advance pc += 4 unless branch/jump taken

**Section 3: Testbench Comparison Helpers (~30 lines)**
- `struct CpuTestResult { int total; int pass; int fail; }` -- test result accumulator
- `void cpu_test_init(CpuTestResult& r)` -- zero counters
- `bool cpu_check_reg(const char* test_name, int test_num, uint32_t dut_val, uint32_t ref_val, CpuTestResult& r)` -- compare DUT debug output against reference model, print `[TEST N] <name>: dut=X ref=Y | PASS/FAIL`, increment counters
- `void cpu_test_report(const CpuTestResult& r)` -- print `RESULT: PASSED/FAILED X/Y tests`

Use `#pragma once` guard. Include only `<cstdint>`, `<cstdio>`, `<cstring>`. All functions inline or constexpr. No external dependencies.
  </action>
  <verify>
    <automated>cd /home/mingzhenjia/ChipAgent && g++ -std=c++17 -fsyntax-only -x c++ -include sim/cpu_test_template.h /dev/null</automated>
  </verify>
  <done>sim/cpu_test_template.h exists, compiles cleanly with g++ -std=c++17, contains all six instruction encoding helpers (r_type through j_type), RV32IState struct, rv32i_step function with opcode switch, and comparison helpers</done>
</task>

<task type="auto">
  <name>Task 2: Update agents and skill for complex module testing</name>
  <files>agents/chisel-generator.md, agents/requirement-parser.md, skills/generate.md</files>
  <action>
**Update agents/chisel-generator.md:** Add a new section after "## Top Module Template (Complex Specs)" titled "## Debug Ports for Complex CPU Modules". Content:

- When generating a complex module where the spec type is "complex" AND the spec's `verification.isa` field is present (e.g., "RV32I"), the top module MUST include these additional debug output ports in the IO bundle:
  - `val debug_pc = Output(UInt(32.W))` -- current program counter
  - `val debug_reg_addr = Input(UInt(5.W))` -- register address to observe (driven by testbench)
  - `val debug_reg_data = Output(UInt(32.W))` -- value of the register at debug_reg_addr
- These debug ports connect to the internal PC register and register file respectively
- Add a note: "Debug ports are always added for CPU modules. They can be stripped for synthesis by wrapping in `if (debugPorts) { ... }` but are required for verification."
- Add to the Convention Checklist: `- [ ] Complex CPU modules include debug_pc, debug_reg_addr, debug_reg_data ports`

**Update agents/requirement-parser.md:** Add a `verification` object to the complex design schema. After the `topModule` field in the complex schema JSON, add:

```json
"verification": {
  "isa": "RV32I",
  "tier": "reference-model",
  "debugPorts": [
    { "name": "debug_pc", "direction": "output", "type": "UInt", "width": 32 },
    { "name": "debug_reg_addr", "direction": "input", "type": "UInt", "width": 5 },
    { "name": "debug_reg_data", "direction": "output", "type": "UInt", "width": 32 }
  ],
  "testCategories": ["R-type arithmetic", "I-type immediate", "Load/Store", "Branch", "Jump", "Upper immediate"]
}
```

Add field descriptions to the complex schema table:
- `verification` (object, conditional): Present when module is a CPU/processor. Omitted for non-CPU complex designs.
- `verification.isa` (string): Instruction set architecture identifier (e.g., "RV32I")
- `verification.tier` (string): One of "simple-struct", "reference-model"
- `verification.debugPorts` (array): Debug ports that must be added to the top module
- `verification.testCategories` (array): Instruction categories to test

Also update Example 3 (Complex RISC-V CPU) to include the verification section.

Add a new parsing rule under "### Complex Design Rules (additional)":
- Rule 19: "When the design is a CPU or processor implementing a known ISA (RV32I, RV32IM, etc.), add a `verification` section with `isa`, `tier: "reference-model"`, `debugPorts` for PC and register observation, and `testCategories` covering each instruction format."

**Update skills/generate.md:** Modify Step 5 to handle complex CPU modules. Replace the current Step 5 content with a conditional:

Add after the current Step 5 paragraph (before "### Step 6"):

```
**Complex/CPU module testbench generation (when spec.type is "complex" and spec.verification.tier is "reference-model"):**

For CPU modules verified via reference model, generate a testbench that:
1. `#include "cpu_test_template.h"` (the fixed template with encoding helpers, reference emulator, and comparison logic)
2. `#include "V<TopModuleName>.h"` and `"verilated.h"`
3. Load a sequence of RV32I instructions into both the DUT (via reset + instruction memory) and the reference model (via `RV32IState.mem`)
4. For each instruction: clock the DUT one cycle, call `rv32i_step()` on the reference model, then compare `dut->io_debug_pc` and `dut->io_debug_reg_data` against the reference state using `cpu_check_reg()`
5. Cover ~40 test vectors across all RV32I instruction categories (2-3 per instruction type): R-type (ADD, SUB, AND, OR, XOR, SLT, SLL, SRL, SRA), I-type (ADDI, ANDI, ORI, XORI, SLTI, SLLI, SRLI, SRAI), Load/Store (LW, SW), Branch (BEQ, BNE, BLT, BGE), Jump (JAL, JALR), Upper (LUI, AUIPC)
6. Use the instruction encoding helpers (rv_add, rv_addi, etc.) from the template -- do NOT manually encode instruction bit patterns
7. Output follows the same `[TEST N] ... PASS/FAIL` and `RESULT: PASSED/FAILED X/Y tests` format as simple testbenches

The LLM generating the testbench receives the template helpers and only needs to compose test sequences, NOT implement the emulator or encoding logic.
```

Keep the existing simple-module testbench generation path intact, just add the complex path as a conditional branch.
  </action>
  <verify>
    <automated>cd /home/mingzhenjia/ChipAgent && grep -q "debug_pc" agents/chisel-generator.md && grep -q "verification" agents/requirement-parser.md && grep -q "cpu_test_template" skills/generate.md && echo "ALL PATTERNS FOUND"</automated>
  </verify>
  <done>All three files updated: chisel-generator.md has debug port section and checklist item, requirement-parser.md has verification schema with isa/tier/debugPorts/testCategories fields plus updated Example 3, skills/generate.md has conditional Step 5 for complex CPU modules referencing cpu_test_template.h</done>
</task>

<task type="auto">
  <name>Task 3: Write research summary document</name>
  <files>.planning/quick/1-research-and-document-testing-strategies/1-RESEARCH.md</files>
  <action>
Create the research document summarizing all findings and decisions. Structure:

**# CPU Testing Strategy for ChipAgent**

**## Problem Statement**
- ChipAgent's existing testbench pattern (struct-based test vectors, single eval()) works for combinational modules (ALU, decoders) but cannot verify sequential CPU modules that execute instructions over multiple clock cycles
- Need a strategy that: (a) the LLM can reliably generate, (b) catches real bugs, (c) scales to full RV32I instruction set

**## Three-Tier Verification Approach**
| Tier | Module Type | Strategy | Example |
|------|-------------|----------|---------|
| Simple struct | Combinational (ALU, mux) | TestCase struct with expected values, single eval() | Existing tb_ALU.cpp |
| Reference model | CPU/processor | Embedded C++ RV32I emulator, cycle-by-cycle comparison | New cpu_test_template.h |
| Formal (future) | Critical paths | Property-based verification | Not implemented |

**## Strategies Considered**
1. **Hand-written golden vectors** -- Manually encode expected register state after each instruction. Pros: simple. Cons: error-prone at scale, LLM must compute expected values correctly, combinatorial explosion.
2. **ISA simulator comparison** -- Run Spike or RISC-V ISA sim alongside DUT. Pros: gold standard. Cons: requires external tool install, complex integration, not portable.
3. **Embedded reference model (CHOSEN)** -- ~150-line C++ RV32I emulator embedded in testbench. Pros: self-contained, LLM only composes test sequences, reference model catches LLM encoding errors. Cons: reference model must be correct (but it's fixed/audited, not LLM-generated per run).

**## Decision: Embedded C++ Reference Model**
- Rationale: The LLM's job is reduced to composing instruction sequences using provided helper functions. The fixed template handles encoding, emulation, and comparison. This minimizes the surface area for LLM errors.

**## Debug Ports**
- Complex CPU modules always include: `debug_pc` (Output, 32-bit), `debug_reg_addr` (Input, 5-bit), `debug_reg_data` (Output, 32-bit)
- These allow the testbench to observe internal CPU state without modifying the datapath
- Can be stripped for synthesis but are mandatory for verification

**## Instruction Encoding Helpers**
- Fixed `constexpr` functions: r_type(), i_type(), s_type(), b_type(), u_type(), j_type()
- Convenience wrappers: rv_add(), rv_addi(), rv_sub(), etc.
- LLM calls these with register/immediate arguments instead of manually encoding bits
- Eliminates the most common LLM error: incorrect bit-field encoding

**## Test Coverage: Per-Instruction Smoke Tests**
- Target: ~40 tests covering each RV32I instruction type
- 2-3 vectors per instruction: one basic case, one edge case (overflow, zero, negative)
- Categories: R-type arithmetic (9 instructions), I-type immediate (8), Load/Store (2), Branch (6), Jump (2), Upper immediate (2)
- Total: ~29 unique instructions x 1.5 avg vectors = ~43 tests

**## LLM Generation Considerations**
- LLM receives the fixed template (cpu_test_template.h) and only writes the test sequence composition
- Instruction encoding is done via helper calls, not raw hex
- Reference model runs identically to DUT, so expected values are computed, not hand-specified
- If a test fails, it indicates either a DUT bug (Chisel generation issue) or a test sequence issue (fixable by regenerating the test)

**## Files Created/Modified**
| File | Purpose |
|------|---------|
| sim/cpu_test_template.h | Fixed template: encoding helpers + reference emulator + comparison logic |
| agents/chisel-generator.md | Debug port rules for complex CPU modules |
| agents/requirement-parser.md | Verification section in complex spec JSON |
| skills/generate.md | Conditional Step 5 for reference-model testbenches |
  </action>
  <verify>
    <automated>test -f /home/mingzhenjia/ChipAgent/.planning/quick/1-research-and-document-testing-strategies/1-RESEARCH.md && wc -l /home/mingzhenjia/ChipAgent/.planning/quick/1-research-and-document-testing-strategies/1-RESEARCH.md | awk '{if ($1 >= 50) print "OK: " $1 " lines"; else print "TOO SHORT: " $1 " lines"}'</automated>
  </verify>
  <done>Research document exists with 50+ lines covering: three-tier approach, strategy comparison, embedded reference model rationale, debug port requirements, instruction encoding helpers, test coverage plan, and LLM generation considerations</done>
</task>

</tasks>

<verification>
1. `g++ -std=c++17 -fsyntax-only -x c++ -include sim/cpu_test_template.h /dev/null` passes (template compiles)
2. `grep -c "constexpr" sim/cpu_test_template.h` returns >= 6 (all encoding helpers are constexpr)
3. `grep "debug_pc" agents/chisel-generator.md` finds debug port documentation
4. `grep "verification" agents/requirement-parser.md` finds verification schema
5. `grep "cpu_test_template" skills/generate.md` finds template reference in Step 5
6. Research document exists and covers all sections
</verification>

<success_criteria>
- cpu_test_template.h compiles with g++ -std=c++17, contains r_type through j_type encoding helpers, RV32I reference emulator with opcode switch, and test comparison helpers
- chisel-generator.md documents mandatory debug ports for CPU modules
- requirement-parser.md includes verification schema in complex design JSON with isa, tier, debugPorts, and testCategories fields
- skills/generate.md has conditional Step 5 path for complex CPU modules that references cpu_test_template.h
- Research document summarizes the three-tier approach, decision rationale, and all implementation details
</success_criteria>

<output>
After completion, create `.planning/quick/1-research-and-document-testing-strategies/1-SUMMARY.md`
</output>
