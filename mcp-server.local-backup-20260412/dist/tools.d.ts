import { type QorRun } from "./qor.js";
export declare function checkEnvironment(): Promise<{
    orfs: {
        installed: boolean;
        flow_path: string;
    };
    sky130hd: {
        installed: boolean;
    };
}>;
export declare function generateConfig(input: {
    module_name: string;
    verilog_path: string;
    workspace_dir: string;
    clock_port: string;
    clock_period_ns: number;
    core_utilization?: number;
    place_density?: number;
    gpl_timing_driven?: boolean;
    gpl_routability_driven?: boolean;
}): Promise<{
    config_mk: string;
    design_name: string;
}>;
export declare function runStage(input: {
    stage: string;
    config_mk_path: string;
    orfs_flow_path: string;
}): Promise<{
    success: boolean;
    stdout: string;
    stderr: string;
}>;
export declare function getReportTool(input: {
    design_name: string;
    stage: string;
    orfs_flow_path: string;
}): Promise<Record<string, unknown>>;
export declare function cleanDesign(input: {
    config_mk_path: string;
    orfs_flow_path: string;
}): Promise<{
    success: boolean;
}>;
export declare function diagnoseFailureTool(input: {
    stage: string;
    success: boolean;
    stderr: string;
    finish_report_content?: string;
    drc_report_content?: string;
    sdc_content?: string;
    current_clock_period_ns?: number;
    current_place_density?: number;
    current_core_utilization?: number;
}): Promise<import("./diagnosis.js").DiagnosisResult>;
export declare function compareRuns(input: {
    action: "clear" | "save" | "load" | "recommend";
    workspace_dir: string;
    run?: {
        round: number;
        config: Record<string, unknown>;
        metrics: Record<string, unknown>;
        status: "pass" | "fail";
        error_type?: string;
    };
}): Promise<{
    success: boolean;
} | {
    runs: QorRun[];
} | {
    best_run: QorRun | null;
    reason: string;
}>;
