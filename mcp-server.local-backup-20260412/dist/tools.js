import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { generateConfigFiles } from "./config.js";
import { diagnoseFailure } from "./diagnosis.js";
import { getReport } from "./reports.js";
import { clearHistory, saveRun, loadRuns, recommendRun, } from "./qor.js";
// Resolve PLUGIN_ROOT from env var or walk up from cwd
function resolvePluginRoot() {
    if (process.env.PLUGIN_ROOT) {
        return process.env.PLUGIN_ROOT;
    }
    // Walk up from dist/ -> mcp-server/ -> project root
    let dir = resolve(import.meta.dirname, "..", "..");
    if (existsSync(join(dir, ".claude-plugin", "plugin.json"))) {
        return dir;
    }
    throw new Error("Cannot determine PLUGIN_ROOT. Set PLUGIN_ROOT env var.");
}
const PLUGIN_ROOT = resolvePluginRoot();
function execCommand(cmd, args, timeoutMs) {
    return new Promise((resolve) => {
        execFile(cmd, args, { timeout: timeoutMs, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
            resolve({
                stdout: stdout ?? "",
                stderr: stderr ?? "",
                exitCode: err && "code" in err ? err.code : err ? 1 : 0,
            });
        });
    });
}
// Tool: check_environment
export async function checkEnvironment() {
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
export async function generateConfig(input) {
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
export async function runStage(input) {
    const timeoutMs = input.stage === "synth" ? 600_000 : 300_000;
    const result = await execCommand("make", [
        "-C", input.orfs_flow_path,
        `DESIGN_CONFIG=${input.config_mk_path}`,
        input.stage,
    ], timeoutMs);
    return {
        success: result.exitCode === 0,
        stdout: result.stdout,
        stderr: result.stderr,
    };
}
// Tool: get_report (delegates to reports.ts)
export async function getReportTool(input) {
    return getReport(input.design_name, input.stage, input.orfs_flow_path);
}
// Tool: clean_design
export async function cleanDesign(input) {
    const result = await execCommand("make", [
        "-C", input.orfs_flow_path,
        `DESIGN_CONFIG=${input.config_mk_path}`,
        "clean_all",
    ], 60_000);
    return { success: result.exitCode === 0 };
}
// Tool: diagnose_failure
export async function diagnoseFailureTool(input) {
    return diagnoseFailure(input);
}
// Tool: compare_runs
export async function compareRuns(input) {
    switch (input.action) {
        case "clear":
            return clearHistory(input.workspace_dir);
        case "save": {
            if (!input.run)
                throw new Error("Missing 'run' for save action");
            const run = {
                round: input.run.round,
                config: input.run.config,
                metrics: {
                    wns: input.run.metrics.wns ?? null,
                    tns: input.run.metrics.tns ?? null,
                    area: input.run.metrics.area ?? null,
                    total_power_w: input.run.metrics.total_power_w ?? null,
                    drc_violations: input.run.metrics.drc_violations ?? null,
                    cell_count: input.run.metrics.cell_count ?? null,
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
//# sourceMappingURL=tools.js.map