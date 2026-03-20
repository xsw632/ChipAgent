#!/usr/bin/env node
"use strict";

const { cpSync, mkdirSync, existsSync, chmodSync, readdirSync } = require("fs");
const { join, resolve } = require("path");

const SOURCE = resolve(__dirname, "..");
const HOME = process.env.HOME;

// Install skills as slash commands (like gsd, ccg)
const COMMANDS_DEST = join(HOME, ".claude", "commands", "chip-agent");

// Install supporting files (scripts, CLAUDE.md) alongside
const SUPPORT_DEST = join(HOME, ".claude", "plugins", "chip-agent");

// 1. Copy skills/*.md -> ~/.claude/commands/chip-agent/
const skillsDir = join(SOURCE, "skills");
if (!existsSync(skillsDir)) {
  console.error("ERROR: No skills/ directory found at " + SOURCE);
  process.exit(1);
}

mkdirSync(COMMANDS_DEST, { recursive: true });
let skillCount = 0;
for (const entry of readdirSync(skillsDir, { withFileTypes: true })) {
  if (entry.isDirectory()) {
    const skillFile = join(skillsDir, entry.name, "SKILL.md");
    if (existsSync(skillFile)) {
      cpSync(skillFile, join(COMMANDS_DEST, entry.name + ".md"));
      skillCount++;
    }
  } else if (entry.name.endsWith(".md")) {
    cpSync(join(skillsDir, entry.name), join(COMMANDS_DEST, entry.name));
    skillCount++;
  }
}

// 2. Copy supporting files to plugins dir
const SUPPORT_ITEMS = ["scripts", "hooks", "agents", ".claude-plugin", "CLAUDE.md"];
mkdirSync(SUPPORT_DEST, { recursive: true });

for (const item of SUPPORT_ITEMS) {
  const src = join(SOURCE, item);
  if (!existsSync(src)) continue;
  cpSync(src, join(SUPPORT_DEST, item), { recursive: true });
}

// Make scripts executable
const scriptsDir = join(SUPPORT_DEST, "scripts");
if (existsSync(scriptsDir)) {
  for (const f of readdirSync(scriptsDir)) {
    if (f.endsWith(".sh")) {
      chmodSync(join(scriptsDir, f), 0o755);
    }
  }
}

if (skillCount === 0) {
  console.error("ERROR: No .md skill files found in " + skillsDir);
  process.exit(1);
}

console.log(`\nchip-agent installed successfully!`);
console.log(`  ${skillCount} command(s) -> ${COMMANDS_DEST}`);
console.log(`  Support files -> ${SUPPORT_DEST}`);
console.log(`\nRestart Claude Code, then type /chip-agent:generate to use.`);
