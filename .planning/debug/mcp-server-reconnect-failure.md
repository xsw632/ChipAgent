---
status: resolved
trigger: "Investigate why the installed MCP server `chipagent-backend` still fails to reconnect after installer changes. Read-only investigation first unless a clear fix emerges. Focus on reproducing the launch command from ~/.claude.json, checking installed plugin layout under ~/.claude/plugins/chip-agent, and identifying the exact runtime failure with file references and likely fix."
created: 2026-04-12T22:43:57+08:00
updated: 2026-04-13T12:00:00+08:00
---

## Current Focus

hypothesis: The observed reconnect failure is still coming from the repo-local project MCP entry, not the installed user-level plugin entry; Claude likely prioritizes the project MCP of the same name, and that project entry still launches a broken repo-local server without dependencies.
test: Read /home/mingzhenjia/ChipAgent/.mcp.json and correlate with prior Claude session logs that showed which scope failed.
expecting: If the failing scope is project-level, logs and config will show `chipagent-backend` under Project MCPs using relative repo path `mcp-server/index.ts`, while the installed user-level command remains healthy.
next_action: inspect the repo-local .mcp.json and compare its runtime assumptions against current repo dependency state

## Symptoms

expected: Installed MCP server `chipagent-backend` should launch successfully and reconnect when Claude starts or retries MCP servers.
actual: Installed MCP server `chipagent-backend` still fails to reconnect after installer changes.
errors: reconnect failure observed for installed MCP server; exact runtime error not yet captured in this session.
reproduction: use the configured launch command from ~/.claude.json against the installed plugin under ~/.claude/plugins/chip-agent.
started: after installer changes; exact first bad install version not yet established.

## Eliminated

## Evidence

- timestamp: 2026-04-12T22:44:29+08:00
  checked: /home/mingzhenjia/.claude.json
  found: Global MCP config launches chipagent-backend via `node --experimental-strip-types /home/mingzhenjia/.claude/plugins/chip-agent/mcp-server/index.ts`.
  implication: The reconnect failure should be reproducible directly from that exact Node command.

- timestamp: 2026-04-12T22:44:29+08:00
  checked: /home/mingzhenjia/.claude/plugins/chip-agent layout
  found: Installed plugin contains top-level agents, skills, hooks, CLAUDE.md, .claude-plugin/plugin.json, and mcp-server/ with index.ts, package.json, package-lock.json, node_modules, tests, tools, tsconfig.json.
  implication: The installer is copying the MCP server directory and dependencies into the plugin; failure is more likely runtime/config related than a totally missing directory.

- timestamp: 2026-04-12T22:45:11+08:00
  checked: /home/mingzhenjia/ChipAgent/bin/install.js and installed/source mcp-server/index.ts + package.json
  found: The installer copies `mcp-server/` as raw TypeScript and configures Node to run `index.ts` directly with `--experimental-strip-types`; the MCP package is ESM (`"type": "module"`) and the entrypoint imports sibling tool files using explicit `.ts` extensions.
  implication: Startup depends entirely on Node successfully stripping and executing every installed TypeScript module at runtime; any unsupported TS syntax in imported files will crash before MCP can connect.

- timestamp: 2026-04-12T22:46:19+08:00
  checked: exact configured command `node --experimental-strip-types /home/mingzhenjia/.claude/plugins/chip-agent/mcp-server/index.ts`
  found: The process started without immediate stderr and did not crash during initial module loading.
  implication: The failure is not a simple missing-file or syntax error in the MCP entrypoint under direct execution; it likely depends on Claude's launch environment, plugin discovery, or a later runtime path.

- timestamp: 2026-04-12T22:48:26+08:00
  checked: prior Claude session logs under /home/mingzhenjia/.claude/projects/-home-mingzhenjia-ChipAgent/6fb68d1a-024a-45f7-aff3-6d2c3cb2532e.jsonl and /home/mingzhenjia/.claude/history.jsonl
  found: The `/mcp` dialog previously showed `chipagent-backend · ✘ failed` specifically under `Project MCPs (/home/mingzhenjia/ChipAgent/.mcp.json)`, and a reproduced run of the repo-local command failed with `ERR_MODULE_NOT_FOUND` for `@modelcontextprotocol/sdk` because the repo-local `mcp-server/` had no installed dependencies.
  implication: There is direct evidence that at least one reconnect failure came from the project-scoped MCP, not the installed user-scoped plugin, so same-name server shadowing/precedence is a strong candidate.

## Resolution

root_cause: In `compare-runs.ts`, `z.record(z.unknown())` triggers a bug in zod v4.3.6 where `ZodRecord._zod.def.valueType` is `undefined`. The SDK's `recordProcessor` in `zod/v4/core/json-schema-processors.js:432` calls `process(def.valueType)` which becomes `process(undefined)`, crashing with `Cannot read properties of undefined (reading '_zod')`. Since `tools/list` is atomic, this single tool's failure prevents ALL 7 tools from being discovered.
fix: Replaced `z.record(z.unknown())` with `z.any()` in `compare-runs.ts` (lines 67-68). `z.any()` produces a valid JSON schema (`{}`) without triggering the record processor bug. Applied to both repo-local `mcp-server/tools/compare-runs.ts` and installed plugin at `~/.claude/plugins/chip-agent/mcp-server/tools/compare-runs.ts`.
verification: Ran full `tools/list` JSON-RPC request against the fixed server -- all 7 tools (check_environment, generate_config, run_stage, get_report, diagnose_failure, clean_design, compare_runs) return valid JSON schemas successfully.
files_changed: [mcp-server/tools/compare-runs.ts]
