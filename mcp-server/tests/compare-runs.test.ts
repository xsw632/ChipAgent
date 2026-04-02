import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { loadHistory, saveRun, recommendBest } from "../tools/compare-runs.ts";

function makeTmpDir(): string {
  return mkdtempSync(join(tmpdir(), "compare-runs-test-"));
}

function makeRun(overrides: Record<string, unknown> = {}): {
  readonly round: number;
  readonly config: Record<string, unknown>;
  readonly metrics: Record<string, unknown>;
  readonly status: "pass" | "fail";
  readonly error_type?: string;
  readonly timestamp: string;
} {
  return {
    round: 1,
    config: { clock_period_ns: 10, core_utilization: 40 },
    metrics: { wns: 0.5, tns: 0, area: 1200, drc_violations: 0 },
    status: "pass" as const,
    timestamp: "2026-04-02T00:00:00Z",
    ...overrides,
  };
}

describe("loadHistory", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = makeTmpDir();
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it("returns empty array for nonexistent file", () => {
    const result = loadHistory(join(tmpDir, "qor_history.json"));
    assert.deepEqual(result, []);
  });
});

describe("saveRun", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = makeTmpDir();
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it("creates file and appends entry on new history", () => {
    const historyPath = join(tmpDir, "qor_history.json");
    const run = makeRun();
    const result = saveRun(historyPath, run);

    assert.equal(result.length, 1);
    assert.deepEqual(result[0], run);
    assert.ok(existsSync(historyPath));
  });

  it("appends without overwriting existing history", () => {
    const historyPath = join(tmpDir, "qor_history.json");
    const run1 = makeRun({ round: 1 });
    const run2 = makeRun({ round: 2, config: { clock_period_ns: 15, core_utilization: 40 } });

    saveRun(historyPath, run1);
    const result = saveRun(historyPath, run2);

    assert.equal(result.length, 2);
    assert.deepEqual(result[0], run1);
    assert.deepEqual(result[1], run2);
  });

  it("creates parent directories if missing", () => {
    const historyPath = join(tmpDir, "deep", "nested", "qor_history.json");
    const run = makeRun();
    const result = saveRun(historyPath, run);

    assert.equal(result.length, 1);
    assert.ok(existsSync(historyPath));
  });
});

describe("recommendBest", () => {
  it("returns null with no passing runs", () => {
    const runs = [
      makeRun({ status: "fail" as const }),
      makeRun({ round: 2, status: "fail" as const }),
    ];
    const result = recommendBest(runs);
    assert.equal(result, null);
  });

  it("returns null for empty array", () => {
    assert.equal(recommendBest([]), null);
  });

  it("picks tightest clock_period_ns among passing runs with wns>=0 and drc=0", () => {
    const runs = [
      makeRun({
        round: 1,
        config: { clock_period_ns: 15, core_utilization: 40 },
        metrics: { wns: 0.3, tns: 0, area: 1400, drc_violations: 0 },
      }),
      makeRun({
        round: 2,
        config: { clock_period_ns: 10, core_utilization: 40 },
        metrics: { wns: 0.1, tns: 0, area: 1200, drc_violations: 0 },
      }),
    ];
    const best = recommendBest(runs);
    assert.equal(best?.round, 2);
  });

  it("breaks ties by smallest area", () => {
    const runs = [
      makeRun({
        round: 1,
        config: { clock_period_ns: 10, core_utilization: 40 },
        metrics: { wns: 0.5, tns: 0, area: 1500, drc_violations: 0 },
      }),
      makeRun({
        round: 2,
        config: { clock_period_ns: 10, core_utilization: 40 },
        metrics: { wns: 0.3, tns: 0, area: 1200, drc_violations: 0 },
      }),
    ];
    const best = recommendBest(runs);
    assert.equal(best?.round, 2);
  });

  it("ignores runs with wns < 0", () => {
    const runs = [
      makeRun({
        round: 1,
        config: { clock_period_ns: 5, core_utilization: 40 },
        metrics: { wns: -2.5, tns: -15, area: 1000, drc_violations: 0 },
      }),
      makeRun({
        round: 2,
        config: { clock_period_ns: 15, core_utilization: 40 },
        metrics: { wns: 0.3, tns: 0, area: 1400, drc_violations: 0 },
      }),
    ];
    const best = recommendBest(runs);
    assert.equal(best?.round, 2);
  });

  it("ignores runs with drc_violations > 0", () => {
    const runs = [
      makeRun({
        round: 1,
        config: { clock_period_ns: 5, core_utilization: 40 },
        metrics: { wns: 0.5, tns: 0, area: 1000, drc_violations: 3 },
      }),
      makeRun({
        round: 2,
        config: { clock_period_ns: 15, core_utilization: 40 },
        metrics: { wns: 0.3, tns: 0, area: 1400, drc_violations: 0 },
      }),
    ];
    const best = recommendBest(runs);
    assert.equal(best?.round, 2);
  });

  it("returns null when all passing runs have wns < 0", () => {
    const runs = [
      makeRun({
        round: 1,
        metrics: { wns: -1, tns: -5, area: 1000, drc_violations: 0 },
      }),
    ];
    const result = recommendBest(runs);
    assert.equal(result, null);
  });
});
