import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
function isCombinational(clockPort) {
    const lower = clockPort.toLowerCase();
    return lower === "" || lower === "none" || lower === "virtual_clk";
}
function generateConfigMk(params) {
    const lines = [
        `export DESIGN_NAME = ${params.designName}`,
        `export PLATFORM = sky130hd`,
        `export VERILOG_FILES = ${params.verilogPath}`,
        `export SDC_FILE = ${params.sdcPath}`,
        `export CORE_UTILIZATION = ${params.coreUtilization}`,
        `export TNS_END_PERCENT = 100`,
    ];
    if (params.placeDensity !== undefined) {
        lines.push(`export PLACE_DENSITY = ${params.placeDensity}`);
    }
    if (params.gplTimingDriven !== undefined) {
        lines.push(`export GPL_TIMING_DRIVEN = ${params.gplTimingDriven}`);
    }
    if (params.gplRoutabilityDriven !== undefined) {
        lines.push(`export GPL_ROUTABILITY_DRIVEN = ${params.gplRoutabilityDriven}`);
    }
    return lines.join("\n") + "\n";
}
function generateCombinationalSdc(clockPeriodNs) {
    return [
        `create_clock -name virtual_clk -period ${clockPeriodNs}`,
        `set_input_delay -clock virtual_clk 0 [all_inputs]`,
        `set_output_delay -clock virtual_clk 0 [all_outputs]`,
        `set_max_delay ${clockPeriodNs} -from [all_inputs] -to [all_outputs]`,
        "",
    ].join("\n");
}
function generateSequentialSdc(designName, clockPort, clockPeriodNs) {
    const ioDelayPercent = 20;
    const ioDelayNs = (clockPeriodNs * ioDelayPercent) / 100;
    return [
        `current_design ${designName}`,
        `set clk_name  core_clock`,
        `set clk_port  [get_ports ${clockPort}]`,
        `set clk_period ${clockPeriodNs}`,
        `create_clock -name $clk_name -period $clk_period $clk_port`,
        `set_input_delay  [expr $clk_period * 0.${ioDelayPercent}] -clock $clk_name [all_inputs]`,
        `set_output_delay [expr $clk_period * 0.${ioDelayPercent}] -clock $clk_name [all_outputs]`,
        "",
    ].join("\n");
}
export function generateConstraintSdc(designName, params) {
    if (params.combinational || isCombinational(params.clockPort)) {
        return generateCombinationalSdc(params.clockPeriodNs);
    }
    return generateSequentialSdc(designName, params.clockPort, params.clockPeriodNs);
}
export function generateConfigFiles(input) {
    const pnrDir = join(input.workspaceDir, "pnr");
    mkdirSync(pnrDir, { recursive: true });
    const configMkPath = join(pnrDir, "config.mk");
    const sdcPath = join(pnrDir, "constraint.sdc");
    const designName = input.moduleName;
    const coreUtil = input.coreUtilization ?? 40;
    const configMkContent = generateConfigMk({
        designName,
        verilogPath: input.verilogPath,
        sdcPath,
        coreUtilization: coreUtil,
        placeDensity: input.placeDensity,
        gplTimingDriven: input.gplTimingDriven,
        gplRoutabilityDriven: input.gplRoutabilityDriven,
    });
    const combinational = isCombinational(input.clockPort);
    const sdcContent = generateConstraintSdc(designName, {
        clockPort: input.clockPort,
        clockPeriodNs: input.clockPeriodNs,
        combinational,
    });
    writeFileSync(configMkPath, configMkContent, "utf-8");
    writeFileSync(sdcPath, sdcContent, "utf-8");
    return { config_mk: configMkPath, design_name: designName };
}
//# sourceMappingURL=config.js.map