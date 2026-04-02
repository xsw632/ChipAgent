import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildCleanArgs } from "../tools/clean-design.ts";

describe("buildCleanArgs", () => {
  it("returns args with clean_all target", () => {
    const result = buildCleanArgs("/path/to/config.mk", "/path/to/orfs/flow");
    assert.deepEqual(result.args, ["clean_all"]);
  });

  it("sets cwd to orfsFlowPath", () => {
    const result = buildCleanArgs("/path/to/config.mk", "/path/to/orfs/flow");
    assert.equal(result.cwd, "/path/to/orfs/flow");
  });

  it("sets DESIGN_CONFIG in env", () => {
    const result = buildCleanArgs("/path/to/config.mk", "/path/to/orfs/flow");
    assert.equal(result.env.DESIGN_CONFIG, "/path/to/config.mk");
  });

  it("preserves process.env PATH in env", () => {
    const result = buildCleanArgs("/cfg.mk", "/flow");
    assert.ok(result.env.PATH !== undefined);
  });
});
