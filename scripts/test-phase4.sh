#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PASS=0
FAIL=0
TOTAL=0

echo "=== Phase 4 Acceptance Tests ==="

check() {
  local desc="$1"
  shift
  TOTAL=$((TOTAL + 1))
  if eval "$@" > /dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# --- TB-01: Testbench file exists with test vectors ---
check "TB-01: C++ testbench exists" "test -f $PLUGIN_ROOT/sim/tb_ALU.cpp"
check "TB-01: Testbench includes test vectors" "grep -q 'TestCase' $PLUGIN_ROOT/sim/tb_ALU.cpp"

# --- TB-02: Clock handling, input driving, output checking ---
check "TB-02: Clock handling present" "grep -q 'dut->clock' $PLUGIN_ROOT/sim/tb_ALU.cpp"
check "TB-02: Input driving present" "grep -q 'dut->io_a' $PLUGIN_ROOT/sim/tb_ALU.cpp"
check "TB-02: Output checking present" "grep -q 'dut->io_result' $PLUGIN_ROOT/sim/tb_ALU.cpp"

# --- TB-03: All 6 operations covered with 10+ test cases ---
check "TB-03: ADD operation tested" "grep -q 'ADD' $PLUGIN_ROOT/sim/tb_ALU.cpp"
check "TB-03: SUB operation tested" "grep -q 'SUB' $PLUGIN_ROOT/sim/tb_ALU.cpp"
check "TB-03: AND operation tested" "grep -q 'AND' $PLUGIN_ROOT/sim/tb_ALU.cpp"
check "TB-03: OR operation tested" "grep -q '\"OR\"' $PLUGIN_ROOT/sim/tb_ALU.cpp"
check "TB-03: XOR operation tested" "grep -q 'XOR' $PLUGIN_ROOT/sim/tb_ALU.cpp"
check "TB-03: SLT operation tested" "grep -q 'SLT' $PLUGIN_ROOT/sim/tb_ALU.cpp"

# --- SIM-01: simulate.sh runs to completion ---
check "SIM-01: simulate.sh exists and is executable" "test -x $PLUGIN_ROOT/scripts/simulate.sh"
echo "  Running simulate.sh ALU (this may take a moment)..."
check "SIM-01: simulate.sh runs successfully" "$PLUGIN_ROOT/scripts/simulate.sh ALU"

# --- SIM-02: sim_result.log exists in prescribed location ---
check "SIM-02: sim_result.log exists" "test -f $PLUGIN_ROOT/sim/logs/sim_result.log"
check "SIM-02: sim_result.log is non-empty" "test -s $PLUGIN_ROOT/sim/logs/sim_result.log"

# --- TB-03 (continued): At least 10 test cases in log ---
check "TB-03: At least 10 test cases" "test \$(grep -c '^\[TEST' $PLUGIN_ROOT/sim/logs/sim_result.log) -ge 10"

# --- TB-04: Log format validation ---
check "TB-04: Per-test format correct" "grep -qE '^\[TEST [0-9]+\] [A-Z]+: a=[0-9]+ b=[0-9]+ \| expect=[0-9]+ got=[0-9]+ \| (PASS|FAIL)$' $PLUGIN_ROOT/sim/logs/sim_result.log"

# --- SIM-03: Final RESULT line format ---
check "SIM-03: Final line has RESULT format" "tail -1 $PLUGIN_ROOT/sim/logs/sim_result.log | grep -qE '^RESULT: (PASSED|FAILED) [0-9]+/[0-9]+ tests$'"
check "SIM-03: Result is PASSED" "tail -1 $PLUGIN_ROOT/sim/logs/sim_result.log | grep -q 'PASSED'"

# --- Pipeline completeness ---
check "Pipeline: All 7 stages Active" "test \$(grep -c 'Active' $PLUGIN_ROOT/skills/generate.md) -ge 7"

echo ""
echo "Phase 4 Acceptance: $PASS/$TOTAL tests passed"
if [ "$FAIL" -gt 0 ]; then
  echo "PHASE 4: FAILED"
  exit 1
else
  echo "PHASE 4: PASSED"
  exit 0
fi
