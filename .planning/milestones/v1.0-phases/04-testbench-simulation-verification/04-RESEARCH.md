# Phase 4 Research: Testbench, Simulation + Verification

## Requirements to Address

| ID | Description | Key Constraint |
|----|-------------|----------------|
| TB-01 | C++ testbench with test vectors matching module operations | Must be C++ (not SystemVerilog TB) |
| TB-02 | Testbench includes clock handling, input driving, output checking | Verilator eval() pattern |
| TB-03 | ALU testbench covers all 6 ops with 10+ test cases | ADD/SUB/AND/OR/XOR/SLT |
| TB-04 | Formatted log: `[TEST N] OP: a=X b=Y \| expect=Z got=W \| PASS/FAIL` | Exact format prescribed |
| SIM-01 | `scripts/simulate.sh` compiles testbench with Verilator and runs sim | Bash script wrapper |
| SIM-02 | Simulation produces `sim/logs/sim_result.log` in prescribed format | File path is fixed |
| SIM-03 | Final line: `RESULT: PASSED X/Y tests` or `RESULT: FAILED` | Exact format prescribed |

## Existing Infrastructure

### ALU Verilog Interface (generated/ALU.v)

```verilog
module ALU(
  input         clock,
  input         reset,
  input  [31:0] io_a,
  input  [31:0] io_b,
  input  [2:0]  io_op,
  output [31:0] io_result,
  output        io_zero
);
```

**Operation encoding** (from Chisel switch statement):
- `io_op = 0` → ADD (`io_a + io_b`)
- `io_op = 1` → SUB (`io_a - io_b`)
- `io_op = 2` → AND (`io_a & io_b`)
- `io_op = 3` → OR  (`io_a | io_b`)
- `io_op = 4` → XOR (`io_a ^ io_b`)
- `io_op = 5` → SLT (`signed(io_a) < signed(io_b) ? 1 : 0`)

**Critical note:** The ALU is purely combinational. `clock` and `reset` are emitted by Chisel but unused. The waiver file (`chisel-warnings.vlt`) already suppresses lint warnings for these.

### Directory Structure

- `generated/` — contains ALU.v, TrivialModule.v, waiver file, filelist.f
- `sim/logs/` — exists but empty (target for sim_result.log)
- `scripts/` — compile.sh, lint.sh, setup.sh exist; simulate.sh is missing (to be created)

### Existing Script Patterns

Both `compile.sh` and `lint.sh` follow the same pattern:
1. `set -euo pipefail`
2. `PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"`
3. Derive paths from `PLUGIN_ROOT`
4. Execute tool with captured exit code
5. Report success/failure with structured output

### Skill Pipeline (generate.md)

Steps 5-7 are currently "Planned" status. This phase implements:
- Step 5: Generate Testbench
- Step 6: Simulate
- Step 7: Report

## Verilator Simulation Technical Details

### Environment

- **Verilator version:** 5.008 (2023-03-04)
- **API style:** Verilator 5.x with `VerilatedContext` (modern API)

### C++ Testbench Architecture

**Verilator compilation flow:**
1. `verilator --cc <module>.v --exe tb_<module>.cpp` — verilates design + links testbench
2. `make -C obj_dir -f V<Module>.mk` — builds the simulation binary
3. `./obj_dir/V<Module>` — runs the simulation

**Key includes:**
- `#include "verilated.h"` — core Verilator runtime
- `#include "V<Module>.h"` — generated model header (e.g., `VALU.h`)

**Port access pattern:**
- Inputs: `dut->io_a = value;` (writable)
- Outputs: `dut->io_result` (read-only)
- Clock: `dut->clock = 0; dut->eval(); dut->clock = 1; dut->eval();`

**Eval semantics:**
- `dut->eval()` settles all combinational logic
- For combinational-only modules (like ALU), a single `eval()` after setting inputs suffices
- Clock toggling is only needed for sequential logic, but we should still drive clock for Chisel compatibility

### Testbench Template (ALU-specific)

```cpp
#include "VALU.h"
#include "verilated.h"
#include <cstdio>

struct TestCase {
    int op;
    uint32_t a, b, expected;
    const char* op_name;
};

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    VALU* dut = new VALU{ctx};

    TestCase tests[] = { /* ... */ };

    int pass = 0, total = sizeof(tests)/sizeof(tests[0]);
    for (int i = 0; i < total; i++) {
        dut->io_op = tests[i].op;
        dut->io_a = tests[i].a;
        dut->io_b = tests[i].b;
        dut->eval();
        uint32_t got = dut->io_result;
        bool ok = (got == tests[i].expected);
        if (ok) pass++;
        printf("[TEST %d] %s: a=%u b=%u | expect=%u got=%u | %s\n",
               i+1, tests[i].op_name, tests[i].a, tests[i].b,
               tests[i].expected, got, ok ? "PASS" : "FAIL");
    }
    printf("RESULT: %s %d/%d tests\n", (pass == total) ? "PASSED" : "FAILED", pass, total);

    dut->final();
    delete dut;
    delete ctx;
    return (pass == total) ? 0 : 1;
}
```

### simulate.sh Script Design

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
GENERATED_DIR="$PLUGIN_ROOT/generated"
SIM_DIR="$PLUGIN_ROOT/sim"
LOG_DIR="$SIM_DIR/logs"
MODULE="${1:-ALU}"  # Default to ALU

# 1. Verilate: --cc to generate C++ model
verilator --cc "$GENERATED_DIR/$MODULE.v" \
  --exe "$SIM_DIR/tb_$MODULE.cpp" \
  --Mdir "$SIM_DIR/obj_dir" \
  -CFLAGS "-std=c++17"

# 2. Build
make -C "$SIM_DIR/obj_dir" -f "V$MODULE.mk"

# 3. Run, capturing output to log
mkdir -p "$LOG_DIR"
"$SIM_DIR/obj_dir/V$MODULE" > "$LOG_DIR/sim_result.log" 2>&1
EXIT_CODE=$?

cat "$LOG_DIR/sim_result.log"
exit $EXIT_CODE
```

## Key Design Decisions

1. **Testbench location:** `sim/tb_ALU.cpp` (alongside sim infrastructure, not in generated/)
2. **obj_dir location:** `sim/obj_dir/` (keep build artifacts in sim/, gitignored)
3. **Log location:** `sim/logs/sim_result.log` (prescribed by requirements)
4. **Module parameterization:** simulate.sh takes module name as argument (default: ALU)
5. **ALU is combinational:** No clock cycling needed for correctness, but drive clock for Chisel compatibility
6. **Output format:** Exact format from TB-04 and SIM-03 requirements

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Verilator 5.008 API differences from latest docs | Build failure | Use basic VerilatedContext API (stable since 5.x) |
| Chisel port naming (io_ prefix) | Wrong port access in testbench | Confirmed from ALU.v: all ports are `io_<name>` |
| SLT signed comparison edge cases | Wrong expected values in tests | Use C++ signed cast: `(int32_t)a < (int32_t)b` |
| Testbench C++ compilation errors | simulate.sh fails | Use `-std=c++17` flag, minimal includes |
| sim/obj_dir not gitignored | Repo bloat | Add to .gitignore |

## Skill Pipeline Integration

The `generate.md` skill needs Steps 5-7 updated from "Planned" to "Active" with implementation instructions matching the lint auto-fix loop pattern (max 3 attempts on simulation failure).
