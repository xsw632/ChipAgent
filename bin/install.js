#!/usr/bin/env node
"use strict";

const {
  cpSync,
  mkdirSync,
  existsSync,
  chmodSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} = require("fs");
const { join, resolve } = require("path");
const { spawnSync } = require("child_process");
const { homedir } = require("os");

const SOURCE = resolve(__dirname, "..");
const USER_HOME = homedir();
const NODE_EXECUTABLE = process.execPath;
const NPM_EXEC_PATH = process.env.npm_execpath;

if (!USER_HOME) {
  console.error("ERROR: Could not determine the user home directory.");
  process.exit(1);
}

const args = process.argv.slice(2);
const localIndex = args.indexOf("--local");
const isLocal = localIndex !== -1;
const showHelp = args.includes("--help") || args.includes("-h");

if (showHelp) {
  console.log("Usage: chip-agent [OPTIONS]");
  console.log("  --global          Install to user-level ~/.claude/ (default)");
  console.log("  --local [DIR]     Install to project-level .claude/");
  console.log("                    DIR defaults to current directory");
  console.log("  -h, --help        Show this help message");
  process.exit(0);
}

const localTarget = isLocal ? args[localIndex + 1] : null;
const PROJECT_ROOT = (localTarget && !localTarget.startsWith("-"))
  ? resolve(localTarget)
  : process.cwd();
const CLAUDE_DIR = isLocal ? join(PROJECT_ROOT, ".claude") : join(USER_HOME, ".claude");
const COMMANDS_DEST = join(CLAUDE_DIR, "commands", "chip-agent");
const SKILLS_DEST = join(CLAUDE_DIR, "skills");
const AGENTS_DEST = join(CLAUDE_DIR, "agents");
const SUPPORT_DEST = CLAUDE_DIR;
const MCP_SERVER_DEST = join(SUPPORT_DEST, "mcp-server");
const MCP_ENTRYPOINT = join(MCP_SERVER_DEST, "index.ts");

function runCommand(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: "pipe",
    encoding: "utf8",
    ...options,
  });

  if (result.error) {
    throw result.error;
  }

  return result;
}

function ensureNodeSupportsStripTypes() {
  const result = runCommand(NODE_EXECUTABLE, [
    "--experimental-strip-types",
    "--input-type=module",
    "--eval",
    "await Promise.resolve()",
  ]);

  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || "Unknown error").trim();
    console.error("ERROR: Installed Node.js does not support --experimental-strip-types.");
    console.error(detail);
    process.exit(1);
  }
}

function installMcpDependencies() {
  const npmCommand = NPM_EXEC_PATH ? NODE_EXECUTABLE : "npm";
  const npmArgs = NPM_EXEC_PATH ? [NPM_EXEC_PATH, "install", "--omit=dev"] : ["install", "--omit=dev"];
  const result = runCommand(npmCommand, npmArgs, { cwd: MCP_SERVER_DEST });

  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || "Unknown error").trim();
    console.error("ERROR: Failed to install chipagent-backend dependencies.");
    console.error(detail);
    console.error(`Retry with: cd "${MCP_SERVER_DEST}" && npm install --omit=dev`);
    process.exit(1);
  }
}

function readJsonFile(filePath) {
  if (!existsSync(filePath)) {
    return {};
  }
  return JSON.parse(readFileSync(filePath, "utf8"));
}

function writeJsonFile(filePath, data) {
  writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`, "utf8");
}

function upsertMcpConfig() {
  if (isLocal) {
    const localConfigPath = join(PROJECT_ROOT, ".mcp.json");
    const config = readJsonFile(localConfigPath);

    writeJsonFile(localConfigPath, {
      ...config,
      mcpServers: {
        ...(config.mcpServers || {}),
        "chipagent-backend": {
          type: "stdio",
          command: "node",
          args: ["--experimental-strip-types", MCP_ENTRYPOINT],
        },
      },
    });
    return localConfigPath;
  }

  const globalConfigPaths = [join(USER_HOME, ".claude.json"), join(CLAUDE_DIR, "settings.json")];
  const entry = {
    type: "stdio",
    command: "node",
    args: ["--experimental-strip-types", MCP_ENTRYPOINT],
  };

  for (const configPath of globalConfigPaths) {
    if (!existsSync(configPath)) continue;

    let config;
    try {
      config = readJsonFile(configPath);
    } catch (error) {
      console.error(`ERROR: Could not parse existing Claude config at ${configPath}.`);
      console.error(String(error));
      process.exit(1);
    }

    writeJsonFile(configPath, {
      ...config,
      mcpServers: {
        ...(config.mcpServers || {}),
        "chipagent-backend": entry,
      },
    });
    return configPath;
  }

  const configPath = globalConfigPaths[0];
  writeJsonFile(configPath, {
    mcpServers: {
      "chipagent-backend": entry,
    },
  });
  return configPath;
}

const skillsDir = join(SOURCE, "skills");
if (!existsSync(skillsDir)) {
  console.error("ERROR: No skills/ directory found at " + SOURCE);
  process.exit(1);
}

ensureNodeSupportsStripTypes();

function skillHasExtraFiles(skillDir) {
  return readdirSync(skillDir).some((name) => name !== "SKILL.md");
}

function installSkillDirectory(skillDir, skillName) {
  const dest = join(SKILLS_DEST, skillName);
  mkdirSync(dest, { recursive: true });
  cpSync(skillDir, dest, { recursive: true });
  return dest;
}

function rewriteSkillRelativePaths(commandContent, installedSkillDir) {
  // SKILL.md refers to companion files with paths relative to the skill
  // directory (e.g. `references/foo.md`). The command copy runs from the
  // user's project cwd, so point those paths at the installed skill dir.
  return commandContent.split("`references/").join(`\`${installedSkillDir}/references/`);
}

mkdirSync(COMMANDS_DEST, { recursive: true });
let skillCount = 0;
for (const entry of readdirSync(skillsDir, { withFileTypes: true })) {
  if (entry.isDirectory()) {
    const skillDir = join(skillsDir, entry.name);
    const skillFile = join(skillDir, "SKILL.md");
    if (existsSync(skillFile)) {
      let commandContent = readFileSync(skillFile, "utf8");
      if (skillHasExtraFiles(skillDir)) {
        const installedSkillDir = installSkillDirectory(skillDir, entry.name);
        commandContent = rewriteSkillRelativePaths(commandContent, installedSkillDir);
      }
      writeFileSync(join(COMMANDS_DEST, entry.name + ".md"), commandContent, "utf8");
      skillCount++;
    }
  } else if (entry.name.endsWith(".md")) {
    cpSync(join(skillsDir, entry.name), join(COMMANDS_DEST, entry.name));
    skillCount++;
  }
}

// Install source only; local dependencies and build outputs are reproducible.
const COPY_EXCLUDES = new Set(["node_modules", "target", "__pycache__", ".bloop", ".metals"]);
function copySource(src, dest, extraExcludes = []) {
  if (resolve(src) === resolve(dest)) return;
  const excludes = new Set([...COPY_EXCLUDES, ...extraExcludes]);
  cpSync(src, dest, {
    recursive: true,
    filter: (path) => !excludes.has(path.split(/[\\/]/).pop()),
  });
}

const SUPPORT_ITEMS = ["mcp-server", "mcp-server-python", "mcp-server-docker-python"];
mkdirSync(SUPPORT_DEST, { recursive: true });

for (const item of SUPPORT_ITEMS) {
  const src = join(SOURCE, item);
  if (!existsSync(src)) continue;
  copySource(src, join(SUPPORT_DEST, item));
}

// Project toolchain files always live beside MyDesign, in both install modes.
const scriptsSrc = join(SOURCE, "scripts");
if (existsSync(scriptsSrc)) {
  const scriptsDest = join(PROJECT_ROOT, "scripts");
  copySource(scriptsSrc, scriptsDest, ["install.sh"]);
}

// MyDesign/<Module>/chisel-project links to this shared project.
const chiselSrc = join(SOURCE, "chisel-project");
if (existsSync(chiselSrc)) {
  copySource(chiselSrc, join(PROJECT_ROOT, "chisel-project"));
}

// Agents go to .claude/agents/ for Claude Code auto-discovery.
const agentsSrc = join(SOURCE, "agents");
if (existsSync(agentsSrc)) {
  mkdirSync(AGENTS_DEST, { recursive: true });
  cpSync(agentsSrc, AGENTS_DEST, { recursive: true });
}

// Seed project instructions without replacing the user's existing CLAUDE.md.
const claudeTestSrc = join(SOURCE, "templates", "CLAUDE.md");
let claudeTestDest = null;
if (existsSync(claudeTestSrc) && !existsSync(join(PROJECT_ROOT, "CLAUDE.md"))) {
  claudeTestDest = join(PROJECT_ROOT, "CLAUDE.md");
  cpSync(claudeTestSrc, claudeTestDest);
}

if (!existsSync(MCP_ENTRYPOINT)) {
  console.error(`ERROR: MCP server entrypoint not found at ${MCP_ENTRYPOINT}`);
  process.exit(1);
}

installMcpDependencies();
const mcpConfigPath = upsertMcpConfig();

const scriptsDir = join(PROJECT_ROOT, "scripts");
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

console.log(`\nchip-agent installed (${isLocal ? "local" : "global"}) successfully!`);
if (isLocal) {
  console.log(`  Project root -> ${PROJECT_ROOT}`);
}
console.log(`  ${skillCount} command(s) -> ${COMMANDS_DEST}`);
console.log(`  Skill resources -> ${SKILLS_DEST}`);
console.log(`  Agents -> ${AGENTS_DEST}`);
console.log(`  Scripts -> ${join(PROJECT_ROOT, "scripts")}`);
console.log(`  Support files -> ${SUPPORT_DEST}`);
if (claudeTestDest) {
  console.log(`  CLAUDE.md -> ${claudeTestDest}`);
}
console.log(`  MCP backend -> ${MCP_ENTRYPOINT}`);
console.log(`  MCP config -> ${mcpConfigPath}`);
console.log("\nRestart Claude Code, then use /chip-agent:generate or /chip-agent:pnr.");
