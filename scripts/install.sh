#!/usr/bin/env bash
set -euo pipefail

# Resolve source directory from script location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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
