import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

interface ConfigMkParams {
  readonly verilogContent: string;
  readonly verilogAbsPath: string;
  readonly sdcAbsPath: string;
  readonly coreUtilization: number;
}

interface SdcParams {
  readonly verilogContent: string;
  readonly clockPort: string;
  readonly clockPeriodNs: number;
}

function extractModuleName(verilogContent: string): string {
  const match = verilogContent.match(/^module\s+(\w+)/m);
  if (!match) {
    throw new Error("Could not extract module name from Verilog content");
  }
  return match[1];
}

function isSequential(verilogContent: string): boolean {
  return /always\s+@\s*\(\s*posedge/.test(verilogContent);
}

export function generateConfigMk(params: ConfigMkParams): string {
  const designName = extractModuleName(params.verilogContent);
  return [
    `export DESIGN_NAME = ${designName}`,
    `export PLATFORM = sky130hd`,
    `export VERILOG_FILES = ${params.verilogAbsPath}`,
    `export SDC_FILE = ${params.sdcAbsPath}`,
    `export CORE_UTILIZATION = ${params.coreUtilization}`,
    `export TNS_END_PERCENT = 100`,
    "",
  ].join("\n");
}

export function generateSdc(params: SdcParams): string {
  const { clockPort, clockPeriodNs, verilogContent } = params;

  if (isSequential(verilogContent)) {
    const designName = extractModuleName(verilogContent);
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
    },
    async (params): Promise<{ content: Array<{ type: "text"; text: string }> }> => {
      const verilogAbsPath = resolve(params.verilog_path);
      const verilogContent = readFileSync(verilogAbsPath, "utf-8");

      const pnrDir = resolve(params.workspace_dir, "pnr");
      mkdirSync(pnrDir, { recursive: true });

      const sdcAbsPath = resolve(pnrDir, "constraint.sdc");
      const configPath = resolve(pnrDir, "config.mk");

      const configMk = generateConfigMk({
        verilogContent,
        verilogAbsPath,
        sdcAbsPath,
        coreUtilization: params.core_utilization,
      });

      const sdc = generateSdc({
        verilogContent,
        clockPort: params.clock_port,
        clockPeriodNs: params.clock_period_ns,
      });

      writeFileSync(configPath, configMk, "utf-8");
      writeFileSync(sdcAbsPath, sdc, "utf-8");

      const result = {
        config_mk: configPath,
        constraint_sdc: sdcAbsPath,
        design_name: extractModuleName(verilogContent),
      };

      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    },
  );
}
