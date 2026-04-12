#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0; TOTAL=0

check() {
  TOTAL=$((TOTAL + 1))
  if eval "$1" >/dev/null 2>&1; then
    echo "  PASS: $2"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $2"
    FAIL=$((FAIL + 1))
  fi
}

# Clean up workspace from prior runs
rm -rf "$PLUGIN_ROOT/workspace/TrivialModule"

echo "=== Phase 5: Workspace Foundation ==="

echo ""
echo "--- Test 1: Backward compatibility (flat compile) ---"
"$SCRIPT_DIR/compile.sh"
check 'test -f "$PLUGIN_ROOT/generated/TrivialModule.v"' "Flat mode: TrivialModule.v exists in generated/"

echo ""
echo "--- Test 2: Workspace mode compile ---"
"$SCRIPT_DIR/compile.sh" workspace/TrivialModule
check 'test -f "$PLUGIN_ROOT/workspace/TrivialModule/generated/TrivialModule.v"' "Workspace mode: TrivialModule.v in workspace/TrivialModule/generated/"
check 'test -d "$PLUGIN_ROOT/workspace/TrivialModule/sim/logs"' "Workspace mode: sim/logs/ dir created"
check 'test -d "$PLUGIN_ROOT/workspace/TrivialModule/generated"' "Workspace mode: generated/ dir created"

echo ""
echo "--- Test 3: Gitignore coverage ---"
check 'grep -q "workspace/" "$PLUGIN_ROOT/.gitignore"' "Gitignore: workspace/ pattern present"
check 'test -z "$(git -C "$PLUGIN_ROOT" status --porcelain workspace/ 2>/dev/null)"' "Gitignore: workspace/ produces no untracked files"

echo ""
echo "--- Test 4: Backward compatibility (flat lint) ---"
"$SCRIPT_DIR/lint.sh"
check 'test $? -eq 0' "Flat mode: lint.sh exits 0"

echo ""
echo "--- Test 5: Workspace mode lint ---"
"$SCRIPT_DIR/lint.sh" workspace/TrivialModule
check 'test $? -eq 0' "Workspace mode: lint.sh exits 0 for workspace/TrivialModule"

echo ""
echo "--- Test 6: Simulate setup (ensure testbench exists) ---"
# TrivialModule needs a testbench for simulation
# Create minimal testbench if not present
TB_FLAT="$PLUGIN_ROOT/sim/tb_TrivialModule.cpp"
if [ ! -f "$TB_FLAT" ]; then
  echo "Creating minimal TrivialModule testbench..."
  cat > "$TB_FLAT" << 'TBEOF'
#include "VTrivialModule.h"
#include "verilated.h"
#include <cstdio>
int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  VTrivialModule* top = new VTrivialModule;
  top->clock = 0;
  top->reset = 0;
  top->io_in = 42;
  top->eval();
  int pass = (top->io_out == 42);
  printf("[TEST 1] PASSTHROUGH: in=42 | expect=42 got=%d | %s\n",
         top->io_out, pass ? "PASS" : "FAIL");
  top->final();
  delete top;
  return pass ? 0 : 1;
}
TBEOF
fi

# For workspace simulate, the testbench must be in workspace/<Module>/sim/
TB_WS="$PLUGIN_ROOT/workspace/TrivialModule/sim/tb_TrivialModule.cpp"
mkdir -p "$(dirname "$TB_WS")"
cp "$TB_FLAT" "$TB_WS"

echo ""
echo "--- Test 7: Backward compatibility (flat simulate) ---"
"$SCRIPT_DIR/simulate.sh" TrivialModule
check 'test $? -eq 0' "Flat mode: simulate.sh TrivialModule exits 0"
check 'test -f "$PLUGIN_ROOT/sim/logs/sim_result.log"' "Flat mode: sim_result.log created"

echo ""
echo "--- Test 8: Workspace mode simulate ---"
"$SCRIPT_DIR/simulate.sh" workspace/TrivialModule
check 'test $? -eq 0' "Workspace mode: simulate.sh exits 0 for workspace/TrivialModule"
check 'test -f "$PLUGIN_ROOT/workspace/TrivialModule/sim/logs/sim_result.log"' "Workspace mode: sim_result.log in workspace"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$FAIL"
