export interface QorRun {
    round: number;
    config: Record<string, unknown>;
    metrics: {
        wns: number | null;
        tns: number | null;
        area: number | null;
        total_power_w: number | null;
        drc_violations: number | null;
        cell_count: number | null;
    };
    status: "pass" | "fail";
    error_type?: string;
}
export declare function clearHistory(workspaceDir: string): {
    success: boolean;
};
export declare function saveRun(workspaceDir: string, run: QorRun): {
    success: boolean;
};
export declare function loadRuns(workspaceDir: string): {
    runs: QorRun[];
};
export declare function recommendRun(workspaceDir: string): {
    best_run: QorRun | null;
    reason: string;
};
