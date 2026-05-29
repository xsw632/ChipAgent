---
name: sync-back
description: "Sync modified files from a ChipAgent local project (e.g. ChipAgent-Test) back to the ChipAgent source repo. Scans all mapped directories, diffs each file, presents a summary table, and asks user which items to copy back."
tools: [Read, Bash, Grep, Glob]
---

# Sync Back to ChipAgent Source

Compare files in a ChipAgent local project against the ChipAgent source repository, present differences, and selectively sync changes back.

## Arguments

- `$SOURCE` — ChipAgent source repo path (default: `~/ChipAgent`)
- `$TARGET` — ChipAgent local project path (default: current working directory, must contain `.claude/`)

## Directory Mapping

| Source (ChipAgent/) | Target (ChipAgent-Test/) | Direction |
|---|---|---|
| `skills/{name}/SKILL.md` | `.claude/commands/chip-agent/{name}.md` | skills→commands (name mapping) |
| `agents/` | `.claude/agents/` | direct 1:1 |
| `mcp-server/` | `.claude/mcp-server/` | direct 1:1 |
| `scripts/` | `scripts/` | direct 1:1 |
| `chisel-project/` | `chisel-project/` | direct 1:1 |
| `hooks/` | `.claude/hooks/` | direct 1:1 |
| `CLAUDE-For-Test.md` | `CLAUDE.md` | renamed |
| (none) | `.claude/mcp-server-docker/` | target-only |
| (none) | `.claude/mcp-server-docker-python/` | target-only |
| (none) | `.claude/mcp-server-python/` | target-only |

## Execution Steps

### Step 1: Validate Paths

Verify `$SOURCE` exists and has `skills/`, `agents/`, `mcp-server/` directories.
Verify `$TARGET` exists and has `.claude/` directory.

If `$TARGET` not given, use the current working directory. If it doesn't look like a ChipAgent project (no `.claude/commands/chip-agent/`), error out.

### Step 2: Scan All Mappings

For each mapping, run `diff -rq` between source and target paths. Exclude `node_modules`, `target`, `.bloop`, `.metals` directories.

Collect results into categories:
- **CHANGED** — file exists on both sides but differs
- **SOURCE-ONLY** — file exists only in source (not relevant for sync-back, but note it)
- **TARGET-ONLY** — file exists only in target (new files to sync)

For CHANGED files, also collect a brief `diff --stat` or first few lines of diff to show what changed.

### Step 3: Present Summary Table

Output a table like:

```
| # | Category | Source Path | Target Path | Change Summary |
|---|----------|-------------|-------------|----------------|
| 1 | CHANGED | skills/foo/SKILL.md | .claude/commands/chip-agent/foo.md | 3 lines changed |
| 2 | TARGET-ONLY | (none) | .claude/mcp-server-python/server.py | new file |
```

Group by mapping category (skills, agents, mcp-server, scripts, etc).

### Step 4: Ask User

Use AskUserQuestion to ask the user which items to sync. Present all CHANGED and TARGET-ONLY items as selectable options. Group related items together when appropriate (e.g. all changed skills as one group).

Options per item:
- **同步** — copy from target back to source
- **跳过** — don't sync this item

### Step 5: Execute Sync

For each item user chose to sync:

**Skills:** `cp "$TARGET/.claude/commands/chip-agent/{name}.md" "$SOURCE/skills/{name}/SKILL.md"`

**Agents:** `cp "$TARGET/.claude/agents/{name}" "$SOURCE/agents/{name}"`

**MCP Server:** `cp "$TARGET/.claude/mcp-server/{path}" "$SOURCE/mcp-server/{path}"` (use `cp -r` for directories)

**Scripts:** `cp "$TARGET/scripts/{name}" "$SOURCE/scripts/{name}"`

**Chisel-project:** `cp -r "$TARGET/chisel-project/{path}" "$SOURCE/chisel-project/{path}"`

**CLAUDE.md:** `cp "$TARGET/CLAUDE.md" "$SOURCE/CLAUDE-For-Test.md"`

**Target-only dirs (mcp-server-docker-python, mcp-server-python):**
`cp -r "$TARGET/.claude/{dirname}" "$SOURCE/{dirname}"`

### Step 6: Verify

Run `diff -rq` again on synced items to confirm they now match. Report success count and any failures.

## Important Notes

- **One-way only:** This skill syncs Target → Source. It never copies Source → Target (use `install.js` for that).
- **No git operations:** This skill only copies files. It does not commit, push, or create branches.
- **node_modules excluded:** Always exclude `node_modules` from comparisons and copies.
- **Backup awareness:** If a `.bak` file exists alongside a changed file, mention it to the user.
