import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { generateConfigMk, generateSdc } from "../tools/generate-config.ts";

const SEQUENTIAL_VERILOG = `
module Counter(
  input clock,
  input reset,
  output [7:0] io_count
);
  reg [7:0] count;
  always @(posedge clock) begin
    if (reset) count <= 8'h0;
    else count <= count + 8'h1;
  end
  assign io_count = count;
endmodule
`;

const COMBINATIONAL_VERILOG = `
module Adder(
  input [7:0] io_a,
  input [7:0] io_b,
  output [8:0] io_sum
);
  assign io_sum = io_a + io_b;
endmodule
`;

describe("generateConfigMk", () => {
  it("contains DESIGN_NAME from module declaration", () => {
    const config = generateConfigMk({
      verilogContent: SEQUENTIAL_VERILOG,
      verilogAbsPath: "/home/user/MyDesign/Counter/workspace/generated/Counter.v",
      sdcAbsPath: "/home/user/MyDesign/Counter/workspace/pnr/constraint.sdc",
      coreUtilization: 40,
    });
    assert.ok(config.includes("DESIGN_NAME = Counter"));
  });

  it("contains PLATFORM=sky130hd", () => {
    const config = generateConfigMk({
      verilogContent: SEQUENTIAL_VERILOG,
      verilogAbsPath: "/tmp/Counter.v",
      sdcAbsPath: "/tmp/constraint.sdc",
      coreUtilization: 40,
    });
    assert.ok(config.includes("PLATFORM = sky130hd"));
  });

  it("contains absolute VERILOG_FILES path", () => {
    const absPath = "/home/user/MyDesign/Counter/workspace/generated/Counter.v";
    const config = generateConfigMk({
      verilogContent: SEQUENTIAL_VERILOG,
      verilogAbsPath: absPath,
      sdcAbsPath: "/tmp/constraint.sdc",
      coreUtilization: 40,
    });
    assert.ok(config.includes(`VERILOG_FILES = ${absPath}`));
  });

  it("contains absolute SDC_FILE path", () => {
    const sdcPath = "/home/user/MyDesign/Counter/workspace/pnr/constraint.sdc";
    const config = generateConfigMk({
      verilogContent: SEQUENTIAL_VERILOG,
      verilogAbsPath: "/tmp/Counter.v",
      sdcAbsPath: sdcPath,
      coreUtilization: 40,
    });
    assert.ok(config.includes(`SDC_FILE = ${sdcPath}`));
  });

  it("contains CORE_UTILIZATION and TNS_END_PERCENT", () => {
    const config = generateConfigMk({
      verilogContent: SEQUENTIAL_VERILOG,
      verilogAbsPath: "/tmp/Counter.v",
      sdcAbsPath: "/tmp/constraint.sdc",
      coreUtilization: 40,
    });
    assert.ok(config.includes("CORE_UTILIZATION = 40"));
    assert.ok(config.includes("TNS_END_PERCENT = 100"));
  });

  it("uses custom core_utilization", () => {
    const config = generateConfigMk({
      verilogContent: SEQUENTIAL_VERILOG,
      verilogAbsPath: "/tmp/Counter.v",
      sdcAbsPath: "/tmp/constraint.sdc",
      coreUtilization: 60,
    });
    assert.ok(config.includes("CORE_UTILIZATION = 60"));
  });
});

describe("generateSdc", () => {
  it("produces real clock for sequential modules", () => {
    const sdc = generateSdc({
      verilogContent: SEQUENTIAL_VERILOG,
      clockPort: "clock",
      clockPeriodNs: 10,
    });
    assert.ok(sdc.includes("create_clock -name core_clock -period 10"));
    assert.ok(sdc.includes("[get_ports clock]"));
    assert.ok(sdc.includes("[all_inputs -no_clocks]"));
  });

  it("produces virtual clock for combinational modules", () => {
    const sdc = generateSdc({
      verilogContent: COMBINATIONAL_VERILOG,
      clockPort: "clock",
      clockPeriodNs: 10,
    });
    assert.ok(sdc.includes("create_clock -name virtual_clk -period 10"));
    assert.ok(sdc.includes("set_max_delay"));
    // Should NOT have get_ports clock
    assert.ok(!sdc.includes("[get_ports clock]"));
  });

  it("uses custom clock_period_ns", () => {
    const sdc = generateSdc({
      verilogContent: SEQUENTIAL_VERILOG,
      clockPort: "clock",
      clockPeriodNs: 5,
    });
    assert.ok(sdc.includes("-period 5"));
  });

  it("uses custom clock_port", () => {
    const sdc = generateSdc({
      verilogContent: SEQUENTIAL_VERILOG,
      clockPort: "clk",
      clockPeriodNs: 10,
    });
    assert.ok(sdc.includes("[get_ports clk]"));
  });
<<<<<<< HEAD
=======

  it("uses overrideModuleName in current_design", () => {
    const sdc = generateSdc({
      verilogContent: SEQUENTIAL_VERILOG,
      clockPort: "clock",
      clockPeriodNs: 10,
      overrideModuleName: "ChipTop",
    });
    assert.ok(sdc.includes("current_design ChipTop"));
  });

  it("falls back to extracted name in current_design when no override", () => {
    const sdc = generateSdc({
      verilogContent: SEQUENTIAL_VERILOG,
      clockPort: "clock",
      clockPeriodNs: 10,
      overrideModuleName: undefined,
    });
    assert.ok(sdc.includes("current_design Counter"));
  });
>>>>>>> main
});

const BASE_PARAMS = {
  verilogContent: SEQUENTIAL_VERILOG,
  verilogAbsPath: "/tmp/Counter.v",
  sdcAbsPath: "/tmp/constraint.sdc",
  coreUtilization: 40,
} as const;

describe("generateConfigMk tuning parameters", () => {
  it("includes PLACE_DENSITY when placeDensity provided", () => {
    const config = generateConfigMk({ ...BASE_PARAMS, placeDensity: 0.7 });
    assert.ok(config.includes("PLACE_DENSITY = 0.7"));
  });

  it("includes GPL_TIMING_DRIVEN = 1 when gplTimingDriven is true", () => {
    const config = generateConfigMk({ ...BASE_PARAMS, gplTimingDriven: true });
    assert.ok(config.includes("GPL_TIMING_DRIVEN = 1"));
  });

  it("includes GPL_TIMING_DRIVEN = 0 when gplTimingDriven is false", () => {
    const config = generateConfigMk({ ...BASE_PARAMS, gplTimingDriven: false });
    assert.ok(config.includes("GPL_TIMING_DRIVEN = 0"));
  });

  it("includes GPL_ROUTABILITY_DRIVEN = 1 when gplRoutabilityDriven is true", () => {
    const config = generateConfigMk({ ...BASE_PARAMS, gplRoutabilityDriven: true });
    assert.ok(config.includes("GPL_ROUTABILITY_DRIVEN = 1"));
  });

  it("omits optional lines when params not provided (backward compat)", () => {
    const config = generateConfigMk(BASE_PARAMS);
    assert.ok(!config.includes("PLACE_DENSITY"));
    assert.ok(!config.includes("GPL_TIMING_DRIVEN"));
    assert.ok(!config.includes("GPL_ROUTABILITY_DRIVEN"));
  });

<<<<<<< HEAD
=======
  it("uses overrideModuleName when provided", () => {
    const config = generateConfigMk({
      ...BASE_PARAMS,
      overrideModuleName: "ChipTop",
    });
    assert.ok(config.includes("DESIGN_NAME = ChipTop"));
  });

  it("falls back to extracted name when overrideModuleName is undefined", () => {
    const config = generateConfigMk({
      ...BASE_PARAMS,
      overrideModuleName: undefined,
    });
    assert.ok(config.includes("DESIGN_NAME = Counter"));
  });

>>>>>>> main
  it("includes all three optional lines when all params provided", () => {
    const config = generateConfigMk({
      ...BASE_PARAMS,
      placeDensity: 0.5,
      gplTimingDriven: true,
      gplRoutabilityDriven: true,
    });
    assert.ok(config.includes("PLACE_DENSITY = 0.5"));
    assert.ok(config.includes("GPL_TIMING_DRIVEN = 1"));
    assert.ok(config.includes("GPL_ROUTABILITY_DRIVEN = 1"));
  });
});
