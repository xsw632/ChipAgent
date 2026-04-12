#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# Convert MSYS/Cygwin paths to mixed-mode (C:/...) for JVM compatibility on Windows
if command -v cygpath >/dev/null 2>&1; then
  PLUGIN_ROOT="$(cygpath -m "$PLUGIN_ROOT")"
fi
if [ -z "$PLUGIN_ROOT" ]; then
  echo "ERROR: Could not determine plugin root directory." >&2
  echo "Set CLAUDE_PLUGIN_ROOT or run from the scripts/ directory." >&2
  exit 1
fi
PASS=0
FAIL=0
TOTAL=7

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Phase 3 Integration Tests ==="
echo ""

# Ensure .v files exist
echo "Compiling Chisel sources..."
"$PLUGIN_ROOT/scripts/compile.sh" > /dev/null 2>&1

# Test 1: lint.sh exists and is executable
if [ -x "$PLUGIN_ROOT/scripts/lint.sh" ]; then
  pass "scripts/lint.sh exists and is executable"
else
  fail "scripts/lint.sh exists and is executable"
fi

# Test 2: chisel-warnings.vlt exists and contains verilator_config
if [ -f "$PLUGIN_ROOT/generated/chisel-warnings.vlt" ] && grep -q "verilator_config" "$PLUGIN_ROOT/generated/chisel-warnings.vlt"; then
  pass "chisel-warnings.vlt exists and contains verilator_config"
else
  fail "chisel-warnings.vlt exists and contains verilator_config"
fi

# Test 3: lint.sh exits 0
LINT_OUTPUT=$("$PLUGIN_ROOT/scripts/lint.sh" 2>&1) && LINT_EXIT=0 || LINT_EXIT=$?
if [ "$LINT_EXIT" -eq 0 ]; then
  pass "lint.sh exits 0 (lint-clean)"
else
  fail "lint.sh exits 0 (lint-clean) -- got exit $LINT_EXIT"
fi

# Test 4: lint-warnings.log exists after lint.sh run
if [ -f "$PLUGIN_ROOT/generated/lint-warnings.log" ]; then
  pass "lint-warnings.log exists after lint run"
else
  fail "lint-warnings.log exists after lint run"
fi

# Test 5: verilator --lint-only on ALU.v directly
if verilator --lint-only "$PLUGIN_ROOT/generated/ALU.v" > /dev/null 2>&1; then
  pass "verilator --lint-only ALU.v exits 0"
else
  fail "verilator --lint-only ALU.v exits 0"
fi

# Test 6: lint.sh output contains LINT PASSED
if echo "$LINT_OUTPUT" | grep -q "LINT PASSED"; then
  pass "lint.sh output contains 'LINT PASSED'"
else
  fail "lint.sh output contains 'LINT PASSED'"
fi

# Test 7: hooks/hooks.json exists and has PostToolUse key
if [ -f "$PLUGIN_ROOT/hooks/hooks.json" ] && grep -q "PostToolUse" "$PLUGIN_ROOT/hooks/hooks.json"; then
  pass "hooks/hooks.json exists with PostToolUse key"
else
  fail "hooks/hooks.json exists with PostToolUse key"
fi

echo ""
echo "Phase 3 tests: $PASS/$TOTAL passed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
