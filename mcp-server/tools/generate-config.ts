import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

interface ConfigMkParams {
  readonly verilogContent: string;
  readonly verilogAbsPath: string;
  readonly sdcAbsPath: string;
  readonly coreUtilization: number;
  readonly placeDensity?: number;
  readonly gplTimingDriven?: boolean;
  readonly gplRoutabilityDriven?: boolean;
  readonly overrideModuleName?: string;
}

interface SdcParams {
  readonly verilogContent: string;
  readonly clockPort: string;
  readonly clockPeriodNs: number;
  readonly overrideModuleName?: string;
}

function resolveModuleName(verilogContent: string, overrideName?: string): string {
  if (overrideName) {
    return overrideName;
  }
  const match = verilogContent.match(/^module\s+(\w+)/m);
  if (!match) {
    throw new Error("Could not extract module name from Verilog content");
  }
  return match[1];
}

function extractModuleName(verilogContent: string): string {
  return resolveModuleName(verilogContent);
}

function isSequential(verilogContent: string): boolean {
  return /always\s+@\s*\(\s*posedge/.test(verilogContent);
}

export function generateConfigMk(params: ConfigMkParams): string {
  const designName = resolveModuleName(params.verilogContent, params.overrideModuleName);
  const lines = [
    `export DESIGN_NAME = ${designName}`,
    `export PLATFORM = sky130hd`,
    `export VERILOG_FILES = ${params.verilogAbsPath}`,
    `export SDC_FILE = ${params.sdcAbsPath}`,
    `export CORE_UTILIZATION = ${params.coreUtilization}`,
    `export TNS_END_PERCENT = 100`,
  ];

  if (params.placeDensity !== undefined) {
    lines.push(`export PLACE_DENSITY = ${params.placeDensity}`);
  }
  if (params.gplTimingDriven !== undefined) {
    lines.push(`export GPL_TIMING_DRIVEN = ${params.gplTimingDriven ? 1 : 0}`);
  }
  if (params.gplRoutabilityDriven !== undefined) {
    lines.push(`export GPL_ROUTABILITY_DRIVEN = ${params.gplRoutabilityDriven ? 1 : 0}`);
  }

  lines.push("");
  return lines.join("\n");
}

export function generateSdc(params: SdcParams): string {
  const { clockPort, clockPeriodNs, verilogContent } = params;

  if (isSequential(verilogContent)) {
    const designName = resolveModuleName(verilogContent, params.overrideModuleName);
    return [
      `current_design ${designName}`,
      `create_clock -name core_clock -period ${clockPeriodNs} [get_ports ${clockPort}]`,
      `set_input_delay -clock core_clock 0 [all_inputs -no_clocks]`,
      `set_output_delay -clock core_clock 0 [all_outputs]`,
      "",
    ].join("\n");
  }

  // Combinational: virtual clock
  return [
    `create_clock -name virtual_clk -period ${clockPeriodNs}`,
    `set_input_delay -clock virtual_clk 0 [all_inputs]`,
    `set_output_delay -clock virtual_clk 0 [all_outputs]`,
    `set_max_delay ${clockPeriodNs} -from [all_inputs] -to [all_outputs]`,
    "",
  ].join("\n");
}

export function registerGenerateConfig(server: McpServer): void {
  server.tool(
    "generate_config",
    "Generate ORFS config.mk and constraint.sdc for a compiled Verilog module",
    {
      module_name: z.string().describe("Module name"),
      verilog_path: z.string().describe("Absolute path to compiled Verilog file"),
      workspace_dir: z.string().describe("Absolute path to module workspace directory"),
      clock_port: z.string().optional().default("clock").describe("Clock port name"),
      clock_period_ns: z.number().optional().default(10).describe("Clock period in nanoseconds"),
      core_utilization: z.number().optional().default(40).describe("Core utilization percentage"),
      place_density: z.number().min(0.2).max(0.95).optional().describe("Placement density override (0.0-1.0)"),
      gpl_timing_driven: z.boolean().optional().describe("Enable timing-driven placement"),
      gpl_routability_driven: z.boolean().optional().describe("Enable routability-driven placement"),
    },
    async (params): Promise<{ content: Array<{ type: "text"; text: string }> }> => {
      const verilogAbsPath = resolve(params.verilog_path);
      const verilogContent = readFileSync(verilogAbsPath, "utf-8");

      const pnrDir = resolve(params.workspace_dir);
      mkdirSync(pnrDir, { recursive: true });

      const sdcAbsPath = resolve(pnrDir, "constraint.sdc");
      const configPath = resolve(pnrDir, "config.mk");

      const configMk = generateConfigMk({
        verilogContent,
        verilogAbsPath,
        sdcAbsPath,
        coreUtilization: params.core_utilization,
        placeDensity: params.place_density,
        gplTimingDriven: params.gpl_timing_driven,
        gplRoutabilityDriven: params.gpl_routability_driven,
        overrideModuleName: params.module_name,
      });

      const sdc = generateSdc({
        verilogContent,
        clockPort: params.clock_port,
        clockPeriodNs: params.clock_period_ns,
        overrideModuleName: params.module_name,
      });

      writeFileSync(configPath, configMk, "utf-8");
      writeFileSync(sdcAbsPath, sdc, "utf-8");

      const result = {
        config_mk: configPath,
        constraint_sdc: sdcAbsPath,
        design_name: resolveModuleName(verilogContent, params.module_name),
      };

      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    },
  );
}
