export interface SynthReport {
    cell_count: number;
    synth_area: number;
}
export interface TimingReport {
    wns: number;
    tns: number;
}
export interface DrcReport {
    violations: number;
}
export interface FinishReport {
    wns: number;
    tns: number;
    total_w: number;
    internal_pct: number;
    switching_pct: number;
    leakage_pct: number;
    area: number;
    utilization: number;
}
export declare function parseSynthStat(content: string): SynthReport;
export declare function parseTimingReport(content: string): TimingReport;
export declare function parseDrcReport(content: string): DrcReport;
export declare function parseFinishReport(content: string): FinishReport;
export declare function getReport(designName: string, stage: string, orfsFlowPath: string): Record<string, unknown>;
