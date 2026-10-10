const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');

const sourceRoot = path.resolve(__dirname, '..');

function fixture(t) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'chipagent install '));
  t.after(() => fs.rmSync(base, { recursive: true, force: true }));
  const source = path.join(base, 'source');
  const project = path.join(base, 'design');
  const home = path.join(base, 'home');
  for (const dir of [source, project, home]) fs.mkdirSync(dir, { recursive: true });
  const files = {
    'bin/install.js': fs.readFileSync(path.join(sourceRoot, 'bin/install.js')),
    'skills/generate/SKILL.md': '# Generate\n',
    'skills/explore/SKILL.md': 'Read `references/guide.md`.\n',
    'skills/explore/references/guide.md': 'Reference\n',
    'agents/generator.md': '# Agent\n',
    'scripts/compile.sh': '#!/bin/bash\n',
    'scripts/install.sh': '#!/bin/bash\n',
    'chisel-project/build.sbt': 'template\n',
    'chisel-project/target/stale.class': 'cache\n',
    'mcp-server/index.ts': '// server\n',
    'mcp-server/node_modules/stale/index.js': '// dependency\n',
    'mcp-server-python/server.py': '# local backend\n',
    'mcp-server-docker-python/server.py': '# docker backend\n',
    'mcp-server-docker-python/requirements.txt': 'mcp>=1,<2\n',
    'mcp-server-docker-python/__pycache__/stale.pyc': 'cache\n',
    'templates/CLAUDE.md': '# Project template\n',
  };
  for (const [name, content] of Object.entries(files)) {
    const dest = path.join(source, name);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, content);
  }
  const npmStub = path.join(base, 'npm-stub.js');
  fs.writeFileSync(npmStub, 'process.exit(0);\n');
  const env = { ...process.env, HOME: home, USERPROFILE: home, npm_execpath: npmStub };
  function install(args, cwd = project) {
    const result = spawnSync(process.execPath, [path.join(source, 'bin/install.js'), ...args], {
      cwd, env, encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    return result;
  }
  return { source, project, home, install };
}

for (const mode of ['local', 'global']) {
  test(`${mode} installation isolates source from caches and preserves user instructions`, (t) => {
    const { project, home, install } = fixture(t);
    const instructions = '# Existing project rules\n';
    fs.writeFileSync(path.join(project, 'CLAUDE.md'), instructions);
    const configPath = mode === 'local'
      ? path.join(project, '.mcp.json')
      : path.join(home, '.claude.json');
    fs.writeFileSync(configPath, JSON.stringify({ theme: 'keep', mcpServers: { existing: { command: 'keep' } } }));
    install(mode === 'local' ? ['--local', project] : ['--global']);
    const support = path.join(mode === 'local' ? project : home, '.claude');
    for (const entry of ['commands/chip-agent/generate.md', 'agents/generator.md', 'mcp-server/index.ts',
      'mcp-server-python/server.py', 'mcp-server-docker-python/server.py',
      'skills/explore/references/guide.md']) {
      assert.ok(fs.existsSync(path.join(support, entry)), entry);
    }
    const installed = fs.readFileSync(path.join(support, 'commands/chip-agent/explore.md'), 'utf8');
    assert.ok(installed.includes(path.join(support, 'skills/explore/references/guide.md')));
    assert.ok(fs.existsSync(path.join(project, 'scripts/compile.sh')));
    assert.equal(fs.existsSync(path.join(project, 'scripts/install.sh')), false);
    assert.ok(fs.existsSync(path.join(project, 'chisel-project/build.sbt')));
    assert.equal(fs.existsSync(path.join(project, 'chisel-project/target')), false);
    assert.equal(fs.existsSync(path.join(support, 'mcp-server/node_modules/stale')), false);
    assert.equal(fs.existsSync(path.join(support, 'mcp-server-docker-python/__pycache__')), false);
    assert.equal(fs.readFileSync(path.join(project, 'CLAUDE.md'), 'utf8'), instructions);
    assert.equal(fs.existsSync(path.join(home, 'CLAUDE.md')), false);
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    assert.equal(config.theme, 'keep');
    assert.equal(config.mcpServers.existing.command, 'keep');
    assert.equal(config.mcpServers['chipagent-backend'].args[1], path.join(support, 'mcp-server/index.ts'));
  });
}

test('installing into the source project avoids self-copy and seeds missing project instructions', (t) => {
  const { source, install } = fixture(t);
  install(['--local', source]);
  assert.equal(fs.readFileSync(path.join(source, 'CLAUDE.md'), 'utf8'), '# Project template\n');
  assert.equal(fs.readFileSync(path.join(source, 'chisel-project/build.sbt'), 'utf8'), 'template\n');
});

test('npm package contains every runtime backend and excludes build artifacts', () => {
  const result = spawnSync('npm', ['pack', '--dry-run', '--json', '--ignore-scripts'], {
    cwd: sourceRoot, encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  const files = JSON.parse(result.stdout)[0].files.map((entry) => entry.path);
  for (const entry of ['bin/install.js', 'templates/CLAUDE.md', 'mcp-server/index.ts',
    'mcp-server/lib/workspace-config.ts', 'mcp-server-python/server.py',
    'mcp-server-docker-python/server.py', 'mcp-server-docker-python/orfs_metrics.py',
    'mcp-server-docker-python/casebook.py', 'mcp-server-docker-python/requirements.txt',
    'chisel-project/project/build.properties', '.claude-plugin/plugin.json']) {
    assert.ok(files.includes(entry), entry);
  }
  assert.equal(files.some((entry) => /(^|\/)(node_modules|target|__pycache__|MyDesign|generated)\//.test(entry)), false);
  assert.equal(files.some((entry) => entry.includes('test-phase')), false);
});
