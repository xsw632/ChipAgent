#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

check() {
  TOTAL=$((TOTAL + 1))
  if eval "$2" >/dev/null 2>&1; then
    echo "  [PASS] Check $TOTAL: $1"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] Check $TOTAL: $1"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Phase 6: Skill Decomposition Tests ==="
echo ""
echo "--- Script-wrapper skills ---"

check "skills/compile/SKILL.md exists" \
  'test -f "$PLUGIN_ROOT/skills/compile/SKILL.md"'

check "skills/lint/SKILL.md exists" \
  'test -f "$PLUGIN_ROOT/skills/lint/SKILL.md"'

check "skills/simulate/SKILL.md exists" \
  'test -f "$PLUGIN_ROOT/skills/simulate/SKILL.md"'

check "compile SKILL.md has name: compile and allowed-tools with Bash" \
  'grep -q "name: compile" "$PLUGIN_ROOT/skills/compile/SKILL.md" && grep -q "Bash" "$PLUGIN_ROOT/skills/compile/SKILL.md"'

check "lint SKILL.md has name: lint and allowed-tools with Bash" \
  'grep -q "name: lint" "$PLUGIN_ROOT/skills/lint/SKILL.md" && grep -q "Bash" "$PLUGIN_ROOT/skills/lint/SKILL.md"'

check "simulate SKILL.md has name: simulate and allowed-tools with Bash" \
  'grep -q "name: simulate" "$PLUGIN_ROOT/skills/simulate/SKILL.md" && grep -q "Bash" "$PLUGIN_ROOT/skills/simulate/SKILL.md"'

# --- Agent-backed skills (Plan 02) ---

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$FAIL"
