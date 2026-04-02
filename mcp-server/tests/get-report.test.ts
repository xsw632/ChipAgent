import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  parseFinishReport,
  parseSynthStat,
  parseRouteArea,
  parseDrcReport,
} from "../tools/get-report.ts";

describe("parseFinishReport", () => {
  it("extracts WNS and TNS from finish report content", () => {
    const content = `==========================================================================
finish report_tns
--------------------------------------------------------------------------
tns max -0.62

==========================================================================
finish report_wns
--------------------------------------------------------------------------
wns max -0.05
`;
    const result = parseFinishReport(content);
    assert.equal(result.tns, "-0.62");
    assert.equal(result.wns, "-0.05");
  });

  it("returns empty object for unrecognized content", () => {
    const result = parseFinishReport("nothing here");
    assert.deepEqual(result, {});
  });
});

describe("parseSynthStat", () => {
  it("extracts cell count from synth_stat.txt content", () => {
    const content = `
   Number of wires:              412
   Number of wire bits:          756
   Number of cells:                503
`;
    const result = parseSynthStat(content);
    assert.equal(result.cell_count, 503);
  });

  it("returns null cell_count when not found", () => {
    const result = parseSynthStat("no cells here");
    assert.equal(result.cell_count, null);
  });
});

describe("parseRouteArea", () => {
  it("extracts area and utilization from 6_report.log", () => {
    const content = `Design area 912 um^2 79% utilization.
Some other line.
`;
    const result = parseRouteArea(content);
    assert.equal(result.area, 912);
    assert.equal(result.utilization, 79);
  });

  it("returns nulls when pattern not found", () => {
    const result = parseRouteArea("no area info");
    assert.equal(result.area, null);
    assert.equal(result.utilization, null);
  });
});

describe("parseDrcReport", () => {
  it("returns 0 violations for empty content", () => {
    const result = parseDrcReport("");
    assert.equal(result.violations, 0);
  });

  it("counts non-empty lines as violations", () => {
    const content = `violation type: Short
    srcs: net1 net2
violation type: Spacing
    srcs: net3 net4
`;
    const result = parseDrcReport(content);
    assert.equal(result.violations, 2);
  });
});
