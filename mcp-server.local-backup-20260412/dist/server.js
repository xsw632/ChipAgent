import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { checkEnvironment, generateConfig, runStage, getReportTool, cleanDesign, diagnoseFailureTool, compareRuns, } from "./tools.js";
const server = new McpServer({
    name: "chipagent-backend",
    version: "0.1.0",
});
// 1. check_environment
server.tool("check_environment", "Check if ORFS and sky130hd PDK are installed", {}, async () => {
    const result = await checkEnvironment();
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
});
// 2. generate_config
server.tool("generate_config", "Generate ORFS config.mk and constraint.sdc for a module", {
    module_name: z.string().describe("Module name (PascalCase)"),
    verilog_path: z.string().describe("Absolute path to compiled Verilog"),
    workspace_dir: z.string().describe("Absolute path to module workspace"),
    clock_port: z.string().default("clock").describe("Clock port name"),
    clock_period_ns: z.number().default(10).describe("Clock period in nanoseconds"),
    core_utilization: z.number().optional().describe("Core utilization percentage"),
    place_density: z.number().optional().describe("Placement density"),
    gpl_timing_driven: z.boolean().optional().describe("Enable timing-driven global placement"),
    gpl_routability_driven: z.boolean().optional().describe("Enable routability-driven global placement"),
}, async (params) => {
    const result = await generateConfig(params);
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
});
// 3. run_stage
server.tool("run_stage", "Run an ORFS make stage (synth/floorplan/place/cts/route/finish)", {
    stage: z.string().describe("Stage name"),
    config_mk_path: z.string().describe("Path to config.mk"),
    orfs_flow_path: z.string().describe("Path to ORFS flow directory"),
}, async (params) => {
    const result = await runStage(params);
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
});
// 4. get_report
server.tool("get_report", "Parse ORFS report for a stage and return metrics", {
    design_name: z.string().describe("Design name"),
    stage: z.string().describe("Stage name"),
    orfs_flow_path: z.string().describe("Path to ORFS flow directory"),
}, async (params) => {
    const result = await getReportTool(params);
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
});
// 5. diagnose_failure
server.tool("diagnose_failure", "Diagnose PnR failure and suggest parameter adjustments", {
    stage: z.string().describe("Failed stage name"),
    success: z.boolean().describe("Whether the stage reported success"),
    stderr: z.string().default("").describe("Stderr from failed stage"),
    finish_report_content: z.string().optional().describe("Raw finish report text"),
    drc_report_content: z.string().optional().describe("Raw DRC report text"),
    sdc_content: z.string().optional().describe("SDC constraint file content"),
    current_clock_period_ns: z.number().optional().describe("Current clock period"),
    current_place_density: z.number().optional().describe("Current place density"),
    current_core_utilization: z.number().optional().describe("Current core utilization"),
}, async (params) => {
    const result = await diagnoseFailureTool(params);
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
});
// 6. clean_design
server.tool("clean_design", "Clean all ORFS build artifacts for a design", {
    config_mk_path: z.string().describe("Path to config.mk"),
    orfs_flow_path: z.string().describe("Path to ORFS flow directory"),
}, async (params) => {
    const result = await cleanDesign(params);
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
});
// 7. compare_runs
server.tool("compare_runs", "Manage QoR history: clear, save, load, or recommend best run", {
    action: z.enum(["clear", "save", "load", "recommend"]).describe("Action to perform"),
    workspace_dir: z.string().describe("Absolute path to module workspace"),
    run: z.object({
        round: z.number(),
        config: z.record(z.unknown()),
        metrics: z.record(z.unknown()),
        status: z.enum(["pass", "fail"]),
        error_type: z.string().optional(),
    }).optional().describe("Run data (required for save action)"),
}, async (params) => {
    const result = await compareRuns(params);
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
});
// Start
const transport = new StdioServerTransport();
server.connect(transport);
//# sourceMappingURL=server.js.map