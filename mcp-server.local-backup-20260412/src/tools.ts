import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
import { generateConfigFiles } from "./config.js";
import { diagnoseFailure } from "./diagnosis.js";
import { getReport } from "./reports.js";
import {
  clearHistory,
  saveRun,
  loadRuns,
  recommendRun,
  type QorRun,
} from "./qor.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Resolve PLUGIN_ROOT from env var or walk up from dist/ -> mcp-server/ -> project root
function resolvePluginRoot(): string {
  if (process.env.PLUGIN_ROOT) {
    return process.env.PLUGIN_ROOT;
  }
  let dir = resolve(__dirname, "..", "..");
  if (existsSync(join(dir, ".claude-plugin", "plugin.json"))) {
    return dir;
  }
  throw new Error("Cannot determine PLUGIN_ROOT. Set PLUGIN_ROOT env var.");
}

const PLUGIN_ROOT = resolvePluginRoot();

function execCommand(
  cmd: string,
  args: string[],
  timeoutMs: number,
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  return new Promise((res) => {
    execFile(
      cmd,
      args,
      { timeout: timeoutMs, maxBuffer: 10 * 1024 * 1024 },
      (err: Error | null, stdout: string | undefined, stderr: string | undefined) => {
        res({
          stdout: stdout ?? "",
          stderr: stderr ?? "",
          exitCode: err && "code" in err ? (err.code as number) : err ? 1 : 0,
        });
      },
    );
  });
}

// Tool: check_environment
export async function checkEnvironment(): Promise<{
  orfs: { installed: boolean; flow_path: string };
  sky130hd: { installed: boolean };
}> {
  const flowPath = join(PLUGIN_ROOT, "OpenROAD-flow-scripts", "flow");
  const makefilePath = join(flowPath, "Makefile");
  const platformPath = join(flowPath, "platforms", "sky130hd");

  return {
    orfs: {
      installed: existsSync(makefilePath),
      flow_path: flowPath,
    },
    sky130hd: {
      installed: existsSync(platformPath),
    },
  };
}

// Tool: generate_config
export async function generateConfig(input: {
  module_name: string;
  verilog_path: string;
  workspace_dir: string;
  clock_port: string;
  clock_period_ns: number;
  core_utilization?: number;
  place_density?: number;
  gpl_timing_driven?: boolean;
  gpl_routability_driven?: boolean;
}): Promise<{ config_mk: string; design_name: string }> {
  return generateConfigFiles({
    moduleName: input.module_name,
    verilogPath: input.verilog_path,
    workspaceDir: input.workspace_dir,
    clockPort: input.clock_port,
    clockPeriodNs: input.clock_period_ns,
    coreUtilization: input.core_utilization,
    placeDensity: input.place_density,
    gplTimingDriven: input.gpl_timing_driven,
    gplRoutabilityDriven: input.gpl_routability_driven,
  });
}

// Tool: run_stage
export async function runStage(input: {
  stage: string;
  config_mk_path: string;
  orfs_flow_path: string;
}): Promise<{ success: boolean; stdout: string; stderr: string }> {
  const timeoutMs = input.stage === "synth" ? 600_000 : 300_000;

  const result = await execCommand(
    "make",
    [
      "-C", input.orfs_flow_path,
      `DESIGN_CONFIG=${input.config_mk_path}`,
      input.stage,
    ],
    timeoutMs,
  );

  return {
    success: result.exitCode === 0,
    stdout: result.stdout,
    stderr: result.stderr,
  };
}

// Tool: get_report (delegates to reports.ts)
export async function getReportTool(input: {
  design_name: string;
  stage: string;
  orfs_flow_path: string;
}): Promise<Record<string, unknown>> {
  return getReport(input.design_name, input.stage, input.orfs_flow_path);
}

// Tool: clean_design
export async function cleanDesign(input: {
  config_mk_path: string;
  orfs_flow_path: string;
}): Promise<{ success: boolean }> {
  const result = await execCommand(
    "make",
    [
      "-C", input.orfs_flow_path,
      `DESIGN_CONFIG=${input.config_mk_path}`,
      "clean_all",
    ],
    60_000,
  );

  return { success: result.exitCode === 0 };
}

// Tool: diagnose_failure
export async function diagnoseFailureTool(input: {
  stage: string;
  success: boolean;
  stderr: string;
  finish_report_content?: string;
  drc_report_content?: string;
  sdc_content?: string;
  current_clock_period_ns?: number;
  current_place_density?: number;
  current_core_utilization?: number;
}) {
  return diagnoseFailure(input);
}

// Tool: compare_runs
export async function compareRuns(input: {
  action: "clear" | "save" | "load" | "recommend";
  workspace_dir: string;
  run?: {
    round: number;
    config: Record<string, unknown>;
    metrics: Record<string, unknown>;
    status: "pass" | "fail";
    error_type?: string;
  };
}) {
  switch (input.action) {
    case "clear":
      return clearHistory(input.workspace_dir);

    case "save": {
      if (!input.run) throw new Error("Missing 'run' for save action");
      const run: QorRun = {
        round: input.run.round,
        config: input.run.config,
        metrics: {
          wns: (input.run.metrics.wns as number) ?? null,
          tns: (input.run.metrics.tns as number) ?? null,
          area: (input.run.metrics.area as number) ?? null,
          total_power_w: (input.run.metrics.total_power_w as number) ?? null,
          drc_violations: (input.run.metrics.drc_violations as number) ?? null,
          cell_count: (input.run.metrics.cell_count as number) ?? null,
        },
        status: input.run.status,
        error_type: input.run.error_type,
      };
      return saveRun(input.workspace_dir, run);
    }

    case "load":
      return loadRuns(input.workspace_dir);

    case "recommend":
      return recommendRun(input.workspace_dir);

    default:
      throw new Error(`Unknown action: ${input.action}`);
  }
}
