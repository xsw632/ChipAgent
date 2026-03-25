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

echo "=== Phase 7: Orchestrator + Initialize Tests ==="
echo ""
echo "--- Orchestrator skill ---"

check "skills/generate/SKILL.md exists" \
  'test -f "$PLUGIN_ROOT/skills/generate/SKILL.md"'

check "generate SKILL.md has name: generate in frontmatter" \
  'grep -q "name: generate" "$PLUGIN_ROOT/skills/generate/SKILL.md"'

check "old skills/generate.md removed" \
  '! test -f "$PLUGIN_ROOT/skills/generate.md"'

check "generate SKILL.md references all pipeline scripts (compile.sh, lint.sh, simulate.sh)" \
  'grep -q "compile.sh" "$PLUGIN_ROOT/skills/generate/SKILL.md" && grep -q "lint.sh" "$PLUGIN_ROOT/skills/generate/SKILL.md" && grep -q "simulate.sh" "$PLUGIN_ROOT/skills/generate/SKILL.md"'

check "generate SKILL.md references all agents (requirement-parser, chisel-generator, testbench-generator)" \
  'grep -q "requirement-parser" "$PLUGIN_ROOT/skills/generate/SKILL.md" && grep -q "chisel-generator" "$PLUGIN_ROOT/skills/generate/SKILL.md" && grep -q "testbench-generator" "$PLUGIN_ROOT/skills/generate/SKILL.md"'

echo ""
echo "--- Initialize skill ---"

check "skills/initialize/SKILL.md exists" \
  'test -f "$PLUGIN_ROOT/skills/initialize/SKILL.md"'

check "initialize SKILL.md has name: initialize in frontmatter" \
  'grep -q "name: initialize" "$PLUGIN_ROOT/skills/initialize/SKILL.md"'

check "scripts/detect-env.sh exists and is executable" \
  'test -x "$PLUGIN_ROOT/scripts/detect-env.sh"'

check "detect-env.sh produces valid JSON output" \
  'bash "$PLUGIN_ROOT/scripts/detect-env.sh" > /dev/null 2>&1 && test -f "$PLUGIN_ROOT/.chipagent/env.json"'

check "env.json has tools object with required keys" \
  'grep -q "\"tools\"" "$PLUGIN_ROOT/.chipagent/env.json" && grep -q "\"java\"" "$PLUGIN_ROOT/.chipagent/env.json" && grep -q "\"sbt\"" "$PLUGIN_ROOT/.chipagent/env.json" && grep -q "\"verilator\"" "$PLUGIN_ROOT/.chipagent/env.json"'

check "env.json has capabilities object" \
  'grep -q "\"capabilities\"" "$PLUGIN_ROOT/.chipagent/env.json" && grep -q "\"can_compile\"" "$PLUGIN_ROOT/.chipagent/env.json" && grep -q "\"can_lint\"" "$PLUGIN_ROOT/.chipagent/env.json" && grep -q "\"can_simulate\"" "$PLUGIN_ROOT/.chipagent/env.json"'

check "initialize SKILL.md mentions CLAUDE.md update" \
  'grep -q "CLAUDE.md" "$PLUGIN_ROOT/skills/initialize/SKILL.md"'

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$FAIL"
