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
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$FAIL"
