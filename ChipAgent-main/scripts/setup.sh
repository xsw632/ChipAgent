#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
if [ -n "$_COMMON_INIT_FAILED" ]; then
  echo "ERROR: Could not determine plugin root directory." >&2
  echo "Set CLAUDE_PLUGIN_ROOT or run from the scripts/ directory." >&2
  exit 1
fi

echo "=== ChipAgent Setup ==="
echo ""

# Check prerequisites
MISSING=0

if command -v java >/dev/null 2>&1; then
  JAVA_VER=$(java -version 2>&1 | head -1 | sed 's/.*"\([0-9]*\).*/\1/')
  if [ "$JAVA_VER" -ge 11 ] 2>/dev/null; then
    echo "[OK] Java: $(java -version 2>&1 | head -1)"
  else
    echo "ERROR: Java 11+ required, found version $JAVA_VER."
    MISSING=1
  fi
else
  echo "ERROR: JDK not found. Install JDK 11+ and ensure java is on PATH."
  MISSING=1
fi

if command -v sbt >/dev/null 2>&1; then
  echo "[OK] sbt: $(sbt --version 2>&1 | tail -1)"
else
  echo "ERROR: sbt not found. Install sbt (https://www.scala-sbt.org/download)."
  MISSING=1
fi

if command -v verilator >/dev/null 2>&1; then
  echo "[OK] Verilator: $(verilator --version 2>&1 | head -1)"
else
  echo "WARNING: Verilator not found. Needed for lint and simulation (Phases 3-4)."
fi

if [ "$MISSING" -ne 0 ]; then
  echo ""
  echo "FATAL: Required tools missing. Fix the errors above and re-run."
  exit 1
fi

echo ""

# Create output directories
mkdir -p "$PLUGIN_ROOT/MyDesign"
echo "[OK] MyDesign container created"

echo ""
echo "Setup complete. sbt dependencies will be downloaded on first module compile."
echo "Run /chip-agent:workflow to create and verify a module."
