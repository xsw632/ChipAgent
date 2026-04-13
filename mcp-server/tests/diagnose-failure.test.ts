import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  classifyError,
  suggestParams,
  type DiagnosisResult,
} from "../tools/diagnose-failure.ts";

describe("classifyError", () => {
  it("returns synthesis_error when stage=synth and success=false", () => {
    const result = classifyError({ stage: "synth", success: false, stderr: "Error during synthesis" });
    assert.equal(result.error_type, "synthesis_error");
    assert.equal(result.severity, "critical");
  });

  it("returns placement_overflow when stderr matches placement patterns", () => {
    const result = classifyError({ stage: "place", success: false, stderr: "placement overflow detected" });
    assert.equal(result.error_type, "placement_overflow");
    assert.equal(result.severity, "recoverable");
  });

  it("returns placement_overflow for 'not enough sites' pattern", () => {
    const result = classifyError({ stage: "place", success: false, stderr: "not enough sites for cells" });
    assert.equal(result.error_type, "placement_overflow");
  });

  it("returns congestion when stderr matches GRT-0119", () => {
    const result = classifyError({ stage: "route", success: false, stderr: "[GRT-0119] Routing congestion too high" });
    assert.equal(result.error_type, "congestion");
    assert.equal(result.severity, "recoverable");
  });

  it("returns congestion for Total overflow pattern", () => {
    const result = classifyError({ stage: "route", success: false, stderr: "Total overflow: 5" });
    assert.equal(result.error_type, "congestion");
  });

  it("returns drc when drc_violations > 0", () => {
    const result = classifyError({ stage: "route", success: false, stderr: "", drc_violations: 3 });
    assert.equal(result.error_type, "drc");
    assert.equal(result.severity, "recoverable");
  });

  it("returns timing_violation for silent timing (success=true, wns < 0)", () => {
    const result = classifyError({ stage: "finish", success: true, stderr: "", finish_wns: -0.05 });
    assert.equal(result.error_type, "timing_violation");
  });

  it("returns recoverable severity for sequential timing (SDC has get_ports)", () => {
    const result = classifyError({
      stage: "finish", success: true, stderr: "", finish_wns: -0.1,
      sdc_content: "create_clock -period 10 [get_ports clk]",
    });
    assert.equal(result.error_type, "timing_violation");
    assert.equal(result.severity, "recoverable");
  });

  it("returns critical severity for combinational timing (SDC has virtual_clk)", () => {
    const result = classifyError({
      stage: "finish", success: true, stderr: "", finish_wns: -0.1,
      sdc_content: "create_clock -name virtual_clk -period 10",
    });
    assert.equal(result.error_type, "timing_violation");
    assert.equal(result.severity, "critical");
  });

  it("returns unknown when no patterns match", () => {
    const result = classifyError({ stage: "route", success: false, stderr: "something weird happened" });
    assert.equal(result.error_type, "unknown");
    assert.equal(result.severity, "critical");
  });
});

describe("suggestParams", () => {
  it("returns clock_period *= 1.5 for timing_violation", () => {
    const result = suggestParams("timing_violation", { clock_period_ns: 10 });
    assert.equal(result.clock_period_ns, 15);
  });

  it("clamps clock_period to max 100.0", () => {
    const result = suggestParams("timing_violation", { clock_period_ns: 80 });
    assert.equal(result.clock_period_ns, 100.0);
  });

  it("clamps clock_period to min 1.0", () => {
    const result = suggestParams("timing_violation", { clock_period_ns: 0.5 });
    assert.equal(result.clock_period_ns, 1.0);
  });

  it("returns place_density -= 0.1 for congestion", () => {
    const result = suggestParams("congestion", { place_density: 0.6 });
    assert.deepEqual(result, { place_density: 0.5 });
  });

  it("clamps place_density to min 0.30 for congestion", () => {
    const result = suggestParams("congestion", { place_density: 0.35 });
    assert.equal(result.place_density, 0.30);
  });

  it("returns place_density -= 0.05 for drc", () => {
    const result = suggestParams("drc", { place_density: 0.6 });
    assert.deepEqual(result, { place_density: 0.55 });
  });

  it("clamps place_density to min 0.30 for drc", () => {
    const result = suggestParams("drc", { place_density: 0.32 });
    assert.equal(result.place_density, 0.30);
  });

  it("returns core_utilization -= 15 for placement_overflow", () => {
    const result = suggestParams("placement_overflow", { core_utilization: 40 });
    assert.deepEqual(result, { core_utilization: 25 });
  });

  it("clamps core_utilization to min 20", () => {
    const result = suggestParams("placement_overflow", { core_utilization: 30 });
    assert.equal(result.core_utilization, 20);
  });

  it("returns empty object for synthesis_error", () => {
    const result = suggestParams("synthesis_error", {});
    assert.deepEqual(result, {});
  });

  it("returns empty object for unknown", () => {
    const result = suggestParams("unknown", {});
    assert.deepEqual(result, {});
  });
});

describe("restart_from", () => {
  it("is synth for timing_violation", () => {
    const result = classifyError({ stage: "finish", success: true, stderr: "", finish_wns: -0.1 });
    assert.equal(result.restart_from, "synth");
  });

  it("is place for congestion", () => {
    const result = classifyError({ stage: "route", success: false, stderr: "GRT-0119 overflow" });
    assert.equal(result.restart_from, "place");
  });

  it("is place for drc", () => {
    const result = classifyError({ stage: "route", success: false, stderr: "", drc_violations: 1 });
    assert.equal(result.restart_from, "place");
  });

  it("is floorplan for placement_overflow", () => {
    const result = classifyError({ stage: "place", success: false, stderr: "Cannot place instance" });
    assert.equal(result.restart_from, "floorplan");
  });

  it("is synth for synthesis_error", () => {
    const result = classifyError({ stage: "synth", success: false, stderr: "fail" });
    assert.equal(result.restart_from, "synth");
  });
});
