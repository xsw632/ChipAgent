import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { findOrfs } from "../tools/check-environment.ts";

function makeTmpDir(): string {
  return mkdtempSync(join(tmpdir(), "check-environment-test-"));
}

describe("findOrfs", () => {
  it("prefers ORFS_DIR when it points to a valid ORFS checkout", () => {
    const tmpDir = makeTmpDir();
    const flowDir = join(tmpDir, "flow");
    mkdirSync(flowDir, { recursive: true });
    writeFileSync(join(flowDir, "Makefile"), "all:\n\ttrue\n");

    const previous = process.env.ORFS_DIR;
    process.env.ORFS_DIR = tmpDir;

    try {
      const result = findOrfs();
      assert.equal(result.installed, true);
      assert.equal(result.path, tmpDir);
      assert.equal(result.flow_path, flowDir);
    } finally {
      if (previous === undefined) {
        delete process.env.ORFS_DIR;
      } else {
        process.env.ORFS_DIR = previous;
      }
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("finds ORFS by walking up from the file location when ORFS_DIR is unset", () => {
    // This test verifies that the upward-walk mechanism works from
    // the source repo. If ORFS is checked out at the expected location,
    // findOrfs() should discover it without needing ORFS_DIR.
    const previous = process.env.ORFS_DIR;
    delete process.env.ORFS_DIR;

    try {
      const result = findOrfs();
      // If ORFS is present in the repo, it should be found
      if (result.installed) {
        assert.ok(result.path!.endsWith("OpenROAD-flow-scripts"));
        assert.ok(result.flow_path!.includes("flow"));
      }
      // If not present, that's fine too (CI without ORFS)
    } finally {
      if (previous !== undefined) {
        process.env.ORFS_DIR = previous;
      }
    }
  });

  it("skips invalid ORFS_DIR and falls back to upward walk", () => {
    const previous = process.env.ORFS_DIR;
    process.env.ORFS_DIR = "/tmp/does-not-exist-chipagent-orfs";

    try {
      const result = findOrfs();
      // An invalid ORFS_DIR should be skipped; if ORFS exists elsewhere
      // on disk (e.g. in the repo), it should still be found. The key
      // assertion is that the result path is NOT the invalid ORFS_DIR.
      if (result.installed) {
        assert.notEqual(result.path, "/tmp/does-not-exist-chipagent-orfs");
      }
    } finally {
      if (previous === undefined) {
        delete process.env.ORFS_DIR;
      } else {
        process.env.ORFS_DIR = previous;
      }
    }
  });
});
