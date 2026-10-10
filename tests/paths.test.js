const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const sourceRoot = path.resolve(__dirname, '..');

test('compile accepts module names, explicit project paths and legacy workspaces', (t) => {
  const project = fs.mkdtempSync(path.join(os.tmpdir(), 'chipagent-paths-'));
  t.after(() => fs.rmSync(project, { recursive: true, force: true }));
  const tools = path.join(project, 'tools');
  fs.mkdirSync(tools);
  fs.mkdirSync(path.join(project, 'chisel-project'));
  fs.mkdirSync(path.join(project, 'MyDesign/ALU'), { recursive: true });
  fs.symlinkSync('../../chisel-project', path.join(project, 'MyDesign/ALU/chisel-project'));
  fs.writeFileSync(path.join(tools, 'sbt'), `#!/usr/bin/env bash
set -euo pipefail
last="\${@: -1}"
target="\${last##*--target-dir }"
mkdir -p "$target"
printf 'module ALU; endmodule\\n' > "$target/ALU.v"
pwd -P > "$target/source-dir.txt"
`, { mode: 0o755 });
  const env = { ...process.env, CLAUDE_PLUGIN_ROOT: project, PATH: `${tools}${path.delimiter}${process.env.PATH}` };
  for (const arg of ['ALU', 'MyDesign/ALU', path.join(project, 'MyDesign/ALU'), 'workspace/ALU', path.join(project, 'workspace/ALU')]) {
    const result = spawnSync('bash', [path.join(sourceRoot, 'scripts/compile.sh'), arg], {
      cwd: project, env, encoding: 'utf8',
    });
    assert.equal(result.status, 0, `${arg}: ${result.stdout}${result.stderr}`);
    const generated = path.join(project, arg.includes('workspace/') ? 'workspace/ALU/generated' : 'MyDesign/ALU/workspace/generated');
    assert.ok(fs.existsSync(path.join(generated, 'ALU.v')), arg);
    assert.equal(fs.readFileSync(path.join(generated, 'source-dir.txt'), 'utf8').trim(), path.join(project, 'chisel-project'));
  }
});

test('compile rejects a missing module instead of selecting a stale example', () => {
  const result = spawnSync('bash', [path.join(sourceRoot, 'scripts/compile.sh')], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Usage:/);
});
