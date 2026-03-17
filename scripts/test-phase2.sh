#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_DIR="$PLUGIN_ROOT/chisel-project"
OUTPUT_DIR="$PLUGIN_ROOT/generated"
PASS=0
FAIL=0

echo "=== Phase 2 Integration Tests ==="

# Test 1: Default compilation (TrivialModule) still works
echo -n "Test 1: Default compile (TrivialModule)... "
cd "$PROJECT_DIR"
if timeout 120 sbt --batch "runMain chipagent.Generate --target-dir $OUTPUT_DIR" > /dev/null 2>&1; then
  echo "PASS"; PASS=$((PASS+1))
else
  echo "FAIL"; FAIL=$((FAIL+1))
fi

# Test 2: ALU compilation via --module flag
echo -n "Test 2: ALU compile (--module ALU)... "
if timeout 120 sbt --batch "runMain chipagent.Generate --target-dir $OUTPUT_DIR --module ALU" > /dev/null 2>&1; then
  echo "PASS"; PASS=$((PASS+1))
else
  echo "FAIL"; FAIL=$((FAIL+1))
fi

# Test 3: ALU Verilog output exists
echo -n "Test 3: ALU Verilog output exists... "
if ls "$OUTPUT_DIR"/ALU.* > /dev/null 2>&1; then
  echo "PASS"; PASS=$((PASS+1))
else
  echo "FAIL"; FAIL=$((FAIL+1))
fi

# Test 4: ALU.scala follows package convention
echo -n "Test 4: ALU.scala has package chipagent... "
if grep -q "package chipagent" "$PROJECT_DIR/src/main/scala/chipagent/ALU.scala"; then
  echo "PASS"; PASS=$((PASS+1))
else
  echo "FAIL"; FAIL=$((FAIL+1))
fi

# Test 5: ALU.scala has all 6 operations
echo -n "Test 5: ALU.scala has 6 switch cases... "
COUNT=$(grep -c "is(" "$PROJECT_DIR/src/main/scala/chipagent/ALU.scala" || true)
if [ "$COUNT" -ge 6 ]; then
  echo "PASS ($COUNT cases)"; PASS=$((PASS+1))
else
  echo "FAIL ($COUNT cases, expected >= 6)"; FAIL=$((FAIL+1))
fi

# Test 6: ALU.scala uses signed comparison for SLT
echo -n "Test 6: SLT uses asSInt... "
if grep -q "asSInt" "$PROJECT_DIR/src/main/scala/chipagent/ALU.scala"; then
  echo "PASS"; PASS=$((PASS+1))
else
  echo "FAIL"; FAIL=$((FAIL+1))
fi

# Test 7: Generate.scala accepts --module argument
echo -n "Test 7: Generate.scala has --module support... "
if grep -q "\-\-module" "$PROJECT_DIR/src/main/scala/chipagent/Generate.scala"; then
  echo "PASS"; PASS=$((PASS+1))
else
  echo "FAIL"; FAIL=$((FAIL+1))
fi

# Test 8: Agent definition files exist
echo -n "Test 8: Agent files exist... "
if [ -f "$PLUGIN_ROOT/agents/requirement-parser.md" ] && [ -f "$PLUGIN_ROOT/agents/chisel-generator.md" ]; then
  echo "PASS"; PASS=$((PASS+1))
else
  echo "FAIL"; FAIL=$((FAIL+1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
