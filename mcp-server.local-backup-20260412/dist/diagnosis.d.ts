export interface DiagnosisInput {
    stage: string;
    success: boolean;
    stderr: string;
    finish_report_content?: string;
    drc_report_content?: string;
    sdc_content?: string;
    current_clock_period_ns?: number;
    current_place_density?: number;
    current_core_utilization?: number;
}
export interface DiagnosisResult {
    severity: "critical" | "adjustable";
    error_type: string;
    details: string;
    suggested_params: Record<string, number | boolean>;
    restart_from: string;
}
export declare function diagnoseFailure(input: DiagnosisInput): DiagnosisResult;
