import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  parseFinishReport,
  parseSynthStat,
  parseRouteArea,
  parseDrcReport,
  parsePower,
  parseSynthArea,
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

describe("parsePower", () => {
  it("extracts power metrics from ORFS 6_finish.rpt format", () => {
    const content = `
==========================================================================
 finish power_report

--------------------------------------------------------------------------
Group                  Internal  Switching    Leakage      Total
                          Power      Power      Power      Power (Watts)
----------------------------------------------------------------
Sequential             1.00e-03   2.00e-04   5.00e-06   1.21e-03
Combinational          9.10e-04   1.44e-03   2.05e-05   2.37e-03
Total                  1.91e-03   1.64e-03   2.55e-05   3.57e-03 100.0%
                          53.4%      45.9%       0.7%
`;
    const result = parsePower(content);
    assert.equal(result.total_w, 3.57e-03);
    assert.equal(result.internal_pct, 53.4);
    assert.equal(result.switching_pct, 45.9);
    assert.equal(result.leakage_pct, 0.7);
  });

  it("returns all nulls when power table not found", () => {
    const result = parsePower("no power info here");
    assert.equal(result.total_w, null);
    assert.equal(result.internal_pct, null);
    assert.equal(result.switching_pct, null);
    assert.equal(result.leakage_pct, null);
  });
});

describe("parseSynthArea", () => {
  it("extracts chip area from synth_stat.txt", () => {
    const content = `Chip area for module '\\ALU8': 1234.567890\n`;
    const result = parseSynthArea(content);
    assert.equal(result.synth_area, 1234.56789);
  });

  it("returns null when pattern not found", () => {
    const result = parseSynthArea("no area here");
    assert.equal(result.synth_area, null);
  });
});
