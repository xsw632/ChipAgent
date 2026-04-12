#!/usr/bin/env bash
set -euo pipefail

# Resolve source directory from script location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Convert MSYS/Cygwin paths to mixed-mode (C:/...) for Windows compatibility
if command -v cygpath >/dev/null 2>&1; then
  SCRIPT_DIR="$(cygpath -m "$SCRIPT_DIR")"
  SOURCE_DIR="$(cygpath -m "$SOURCE_DIR")"
fi
if [ -z "$SOURCE_DIR" ]; then
  echo "ERROR: Could not determine source directory." >&2
  exit 1
fi

# Target installation directory
DEST="$HOME/.claude/plugins/chip-agent"

# Create target directory
mkdir -p "$DEST"

# Copy plugin directories and files
for item in .claude-plugin skills agents hooks scripts CLAUDE.md; do
  if [ -e "$SOURCE_DIR/$item" ]; then
    cp -r "$SOURCE_DIR/$item" "$DEST/"
  fi
done

# Make scripts executable
if [ -d "$DEST/scripts" ]; then
  chmod +x "$DEST"/scripts/*.sh
fi

echo "chip-agent installed to $DEST"
