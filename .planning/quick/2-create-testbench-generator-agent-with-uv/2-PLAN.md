---
phase: quick-2
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - agents/testbench-generator.md
  - skills/generate.md
autonomous: true
requirements: [TB-AGENT-01, TB-AGENT-02]
must_haves:
  truths:
    - "testbench-generator agent exists and follows the same frontmatter/structure pattern as chisel-generator and requirement-parser agents"
    - "Agent documents UVM-inspired C++ architecture mapping (Transaction, Generator, Driver, Monitor, Scoreboard, Reporter)"
    - "Agent provides complete simple mode template for combinational modules"
    - "Agent provides complete reference model mode template for CPU modules"
    - "skills/generate.md Step 5 delegates testbench generation to the testbench-generator agent"
  artifacts:
    - path: "agents/testbench-generator.md"
      provides: "Testbench generator agent definition"
      min_lines: 200
    - path: "skills/generate.md"
      provides: "Updated pipeline with agent delegation in Step 5"
      contains: "testbench-generator"
  key_links:
    - from: "skills/generate.md"
      to: "agents/testbench-generator.md"
      via: "Step 5 agent delegation"
      pattern: "testbench-generator"
---

<objective>
Create a dedicated testbench-generator agent that generates UVM-inspired C++ Verilator testbenches, and wire it into the generate pipeline.

Purpose: Centralize testbench generation logic in a reusable agent (matching existing agent patterns) instead of inline instructions in the skill file.
Output: `agents/testbench-generator.md` agent definition + updated `skills/generate.md` Step 5
</objective>

<execution_context>
@/home/mingzhenjia/.claude/get-shit-done/workflows/execute-plan.md
@/home/mingzhenjia/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@agents/chisel-generator.md
@agents/requirement-parser.md
@skills/generate.md
@sim/tb_ALU.cpp
@sim/cpu_test_template.h
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create testbench-generator agent</name>
  <files>agents/testbench-generator.md</files>
  <action>
Create `agents/testbench-generator.md` following the exact frontmatter pattern of `agents/chisel-generator.md`:

```yaml
---
name: testbench-generator
description: "Generates C++ Verilator testbenches from JSON hardware specifications"
tools: [Read, Write, Edit, Bash, Grep, Glob]
model: inherit
---
```

**Structure the agent document with these sections:**

1. **Role** -- Single paragraph: "You are a C++ testbench generator for Verilator simulation. Given a JSON hardware specification and module name, produce a complete C++ testbench file at `sim/tb_<ModuleName>.cpp`."

2. **UVM-Inspired C++ Architecture** -- A mapping table showing how UVM concepts translate to C++ constructs:
   - Transaction -> `TestCase` struct (fields match module ports: inputs + expected output)
   - Stimulus Generator -> Function/array that creates test vectors (exhaustive for <=8-bit inputs, boundary+random for larger)
   - Driver -> Signal driving logic (simple: assign + `eval()`; sequential: `tick()` function with clock toggle + `eval()`)
   - Monitor -> Output capture (read `dut->io_<portName>` after eval)
   - Scoreboard -> Expected vs actual comparison (`got == expected`)
   - Reporter -> Standardized output format: `[TEST N] OP: inputs | expect=X got=Y | PASS/FAIL` and final `RESULT: PASSED/FAILED X/Y tests`

3. **Testbench Mode Selection** -- Decision tree:
   - If `spec.type == "simple"` -> Simple mode
   - If `spec.type == "complex"` AND `spec.verification.tier == "reference-model"` -> Reference model mode
   - If `spec.type == "complex"` WITHOUT verification section -> Simple mode targeting top module

4. **Simple Mode Template** -- Complete C++ template with:
   - `#include "V<ModuleName>.h"` and `"verilated.h"` and `<cstdio>`
   - `VerilatedContext` and DUT instantiation pattern (copy from `sim/tb_ALU.cpp`)
   - `TestCase` struct definition with fields derived from spec ports
   - Test vector array populated from spec operations (2 vectors per operation: normal + boundary)
   - Evaluation loop: assign inputs -> `dut->eval()` -> compare output -> print result
   - Final `RESULT:` line and cleanup (dut->final(), delete dut, delete ctx)
   - Return `(pass == total) ? 0 : 1`

5. **Complete ALU Example** -- Show the EXACT expected output for an ALU spec, which should match `sim/tb_ALU.cpp` closely. Include the full generated code so the agent has a concrete reference.

6. **Reference Model Mode Template** -- Complete C++ template with:
   - `#include "cpu_test_template.h"`, `"V<TopModuleName>.h"`, `"verilated.h"`
   - `VerilatedContext` + DUT instantiation
   - `RV32IState` initialization via `rv32i_init()`
   - `tick()` helper function: toggle clock high -> eval -> toggle low -> eval
   - Reset sequence: assert reset for 5 cycles, deassert
   - Instruction loading: store encoded instructions into both `ref.mem[]` and DUT instruction memory
   - Per-instruction loop: set `dut->io_instruction` from ref.mem at ref.pc, call `tick()`, call `rv32i_step()`, compare via `cpu_check_reg()`
   - Use encoding helpers from cpu_test_template.h (rv_add, rv_addi, rv_lui, rv_beq, etc.) -- do NOT manually encode bit patterns
   - Cover instruction categories: R-type, I-type, Load/Store, Branch, Jump, Upper immediate (2-3 vectors each, ~40 total)
   - `cpu_test_report()` for final output

7. **Complete CPU Testbench Skeleton** -- Show a skeleton for a SimpleRISCV CPU testbench demonstrating reference model integration, instruction sequencing, and comparison flow.

8. **Output Conventions** -- Rules the agent MUST follow:
   - Output file: `sim/tb_<ModuleName>.cpp` (PascalCase module name)
   - Verilog port naming: all ports prefixed with `io_` (Chisel convention)
   - Test output format: `[TEST N] <context>: <inputs> | expect=X got=Y | PASS/FAIL`
   - Final line: `RESULT: PASSED/FAILED X/Y tests`
   - Exit code: 0 on all pass, 1 on any fail
   - Include `dut->final()` cleanup before exit

9. **Test Vector Generation Rules**:
   - For operations with opcode selection: 2 test vectors per operation (normal case + edge/boundary)
   - For boolean flags: test both true and false conditions
   - For arithmetic: include overflow, underflow, zero cases
   - For signed operations: include negative numbers (e.g., 0xFFFFFFFF = -1)
   - For CPU instructions: use encoding helpers, never manual bit patterns

10. **Anti-Patterns** -- Common mistakes to avoid:
    - DO NOT use `Verilated::commandArgs()` -- use `VerilatedContext` pattern
    - DO NOT forget `dut->eval()` after assigning inputs (combinational) or after clock toggle (sequential)
    - DO NOT hardcode expected values without explaining derivation in comments
    - DO NOT edit generated Verilog files -- only edit the testbench
    - DO NOT use `dut->clock = 1; dut->eval(); dut->clock = 0; dut->eval();` inline -- wrap in a `tick()` helper for sequential modules
    - DO NOT forget `dut->final()` and `delete` cleanup
    - DO NOT manually encode RV32I instructions -- use the helpers from cpu_test_template.h

11. **Error Handling** -- Same as chisel-generator: max 3 fix attempts, read simulation errors, fix testbench (NOT generated Verilog).
  </action>
  <verify>
Test that the file exists and has the required frontmatter and sections:
```
test -f agents/testbench-generator.md && head -6 agents/testbench-generator.md | grep -q "name: testbench-generator" && grep -c "##" agents/testbench-generator.md
```
File exists, frontmatter has correct name, and has multiple section headers.
  </verify>
  <done>
agents/testbench-generator.md exists with:
- Correct frontmatter (name, description, tools, model)
- UVM-inspired architecture mapping table
- Complete simple mode template with ALU example
- Complete reference model mode template with CPU skeleton
- Output conventions, test vector rules, anti-patterns
- At least 200 lines of substantive agent instructions
  </done>
</task>

<task type="auto">
  <name>Task 2: Update skills/generate.md Step 5 to delegate to testbench-generator agent</name>
  <files>skills/generate.md</files>
  <action>
Edit `skills/generate.md` Step 5 ("Generate Testbench") to delegate to the testbench-generator agent, following the same delegation pattern used in Step 1 (requirement-parser) and Step 2 (chisel-generator).

Replace the current Step 5 content with:

```
### Step 5 -- Generate Testbench

After lint passes (Step 4), generate a C++ testbench for the module.

1. Determine the testbench path: `sim/tb_<ModuleName>.cpp`
2. If the testbench already exists, skip generation and proceed to Step 6
3. If the testbench does not exist, use the testbench-generator agent with:
   - The JSON spec from Step 1
   - The module name (for simple: `spec.moduleName`, for complex: `spec.topModule.name`)
   - The agent determines the testbench mode (simple vs reference-model) from the spec

The agent produces `sim/tb_<ModuleName>.cpp` following UVM-inspired C++ architecture with standardized PASS/FAIL output format.
```

Keep the existing complex/CPU testbench description below as supplementary context (the agent has the full details, but the skill should mention what to expect). Remove the inline implementation details that are now in the agent (the detailed bullet points about TestCase struct, output format, etc.) since those are the agent's responsibility now.

Preserve Steps 1-4 and Steps 6-7 exactly as they are. Only modify Step 5.
  </action>
  <verify>
```
grep -q "testbench-generator" skills/generate.md && grep -q "Step 5" skills/generate.md && grep -q "Step 6" skills/generate.md
```
Step 5 references the testbench-generator agent, and Steps 5 and 6 both still exist.
  </verify>
  <done>
skills/generate.md Step 5 delegates testbench generation to the testbench-generator agent, matching the delegation pattern of Steps 1 and 2. All other steps remain unchanged.
  </done>
</task>

</tasks>

<verification>
1. `agents/testbench-generator.md` exists with correct frontmatter and comprehensive content
2. `skills/generate.md` Step 5 references the testbench-generator agent
3. All other pipeline steps in generate.md remain unchanged
4. Agent follows the same structural pattern as chisel-generator.md and requirement-parser.md
</verification>

<success_criteria>
- agents/testbench-generator.md is a complete, self-contained agent definition (200+ lines)
- The agent covers both simple (combinational) and reference-model (CPU) testbench modes
- skills/generate.md Step 5 delegates to the agent instead of containing inline generation logic
- The delegation pattern matches Steps 1 and 2 in generate.md
</success_criteria>

<output>
After completion, create `.planning/quick/2-create-testbench-generator-agent-with-uv/2-SUMMARY.md`
</output>
