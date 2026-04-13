import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { VALID_STAGES, buildMakeArgs } from "../tools/run-stage.ts";

describe("VALID_STAGES", () => {
  it("contains all 6 ORFS stages", () => {
    assert.deepEqual([...VALID_STAGES], ["synth", "floorplan", "place", "cts", "route", "finish"]);
  });
});

describe("buildMakeArgs", () => {
  it("constructs correct spawn arguments for synth stage", () => {
    const result = buildMakeArgs("synth", "/path/to/config.mk", "/path/to/orfs/flow");
    assert.deepEqual(result.args, ["synth"]);
    assert.equal(result.cwd, "/path/to/orfs/flow");
    assert.equal(result.env.DESIGN_CONFIG, "/path/to/config.mk");
  });

  it("preserves existing process.env in env", () => {
    const result = buildMakeArgs("place", "/cfg.mk", "/flow");
    assert.equal(result.env.DESIGN_CONFIG, "/cfg.mk");
    // PATH should be inherited from process.env
    assert.ok(result.env.PATH !== undefined);
  });

  it("works for all valid stages", () => {
    for (const stage of VALID_STAGES) {
      const result = buildMakeArgs(stage, "/cfg.mk", "/flow");
      assert.deepEqual(result.args, [stage]);
    }
  });
});
