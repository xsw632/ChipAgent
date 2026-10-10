import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readWorkspaceConfig } from '../lib/workspace-config.ts';

test('shared configuration accepts legacy Docker settings and tolerates unavailable files', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'chipagent-config-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'workspace.json');
  assert.equal(readWorkspaceConfig(path), null);
  writeFileSync(path, '{broken');
  assert.equal(readWorkspaceConfig(path), null);
  const config = { workspace_dir: dir, backend_mode: 'docker', docker_results_dir: join(dir, 'results'), docker_image: 'custom/orfs' };
  writeFileSync(path, JSON.stringify(config));
  assert.deepEqual(readWorkspaceConfig(path), config);
});
