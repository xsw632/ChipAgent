export interface ConfigParams {
    designName: string;
    verilogPath: string;
    sdcPath: string;
    coreUtilization: number;
    placeDensity?: number;
    gplTimingDriven?: boolean;
    gplRoutabilityDriven?: boolean;
}
export interface SdcParams {
    clockPort: string;
    clockPeriodNs: number;
    combinational: boolean;
}
export declare function generateConstraintSdc(designName: string, params: SdcParams): string;
export interface GenerateConfigResult {
    config_mk: string;
    design_name: string;
}
export declare function generateConfigFiles(input: {
    moduleName: string;
    verilogPath: string;
    workspaceDir: string;
    clockPort: string;
    clockPeriodNs: number;
    coreUtilization?: number;
    placeDensity?: number;
    gplTimingDriven?: boolean;
    gplRoutabilityDriven?: boolean;
}): GenerateConfigResult;
