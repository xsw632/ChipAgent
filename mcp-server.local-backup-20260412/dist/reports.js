import { readFileSync } from "node:fs";
import { join } from "node:path";
function readReportFile(filePath) {
    try {
        return readFileSync(filePath, "utf-8");
    }
    catch {
        return null;
    }
}
function parseFloatSafe(val) {
    if (val === undefined || val === "N/A")
        return null;
    const n = parseFloat(val);
    return Number.isNaN(n) ? null : n;
}
export function parseSynthStat(content) {
    const cellMatch = content.match(/Number of cells:\s+(\d+)/);
    const areaMatch = content.match(/Chip area[^:]*:\s+([\d.]+)/);
    return {
        cell_count: cellMatch ? parseInt(cellMatch[1], 10) : 0,
        synth_area: areaMatch ? parseFloat(areaMatch[1]) : 0,
    };
}
export function parseTimingReport(content) {
    const tnsMatch = content.match(/tns max\s+([\d.e+-]+)/);
    const wnsMatch = content.match(/wns max\s+([\d.e+-]+)/);
    return {
        tns: tnsMatch ? parseFloat(tnsMatch[1]) : 0,
        wns: wnsMatch ? parseFloat(wnsMatch[1]) : 0,
    };
}
export function parseDrcReport(content) {
    if (!content || content.trim().length === 0) {
        return { violations: 0 };
    }
    const violationMatch = content.match(/violation/i);
    if (violationMatch) {
        const countMatch = content.match(/(\d+)\s+violation/i);
        return { violations: countMatch ? parseInt(countMatch[1], 10) : 1 };
    }
    const nonEmptyLines = content
        .split("\n")
        .filter((line) => line.trim().length > 0);
    return { violations: nonEmptyLines.length > 0 ? nonEmptyLines.length : 0 };
}
export function parseFinishReport(content) {
    const tnsMatch = content.match(/finish report_tns\s*\n-+\s*\ntns max\s+([\d.e+-]+)/);
    const wnsMatch = content.match(/finish report_wns\s*\n-+\s*\nwns max\s+([\d.e+-]+)/);
    const tns = tnsMatch ? parseFloat(tnsMatch[1]) : 0;
    const wns = wnsMatch ? parseFloat(wnsMatch[1]) : 0;
    // Parse power table: find "Total" line under "finish report_power"
    let totalW = 0;
    let internalPct = 0;
    let switchingPct = 0;
    let leakagePct = 0;
    const powerSection = content.match(/finish report_power\s*\n[-]+\n([\s\S]*?)(?=\n=|\nfinish\s|\s*$)/);
    if (powerSection) {
        const totalLine = powerSection[1].match(/^Total\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)/m);
        if (totalLine) {
            totalW = parseFloat(totalLine[4]);
        }
        const pctLine = powerSection[1].match(/\s+([\d.]+)%\s+([\d.]+)%\s+([\d.]+)%\s*$/m);
        if (pctLine) {
            internalPct = parseFloat(pctLine[1]);
            switchingPct = parseFloat(pctLine[2]);
            leakagePct = parseFloat(pctLine[3]);
        }
    }
    // Parse area from "Design area" or utilization from finish report
    let area = 0;
    let utilization = 0;
    const areaMatch = content.match(/Design area\s+([\d.]+)\s+um\^2\s+([\d.]+)%\s+utilization/);
    if (areaMatch) {
        area = parseFloat(areaMatch[1]);
        utilization = parseFloat(areaMatch[2]);
    }
    return {
        wns,
        tns,
        total_w: totalW,
        internal_pct: internalPct,
        switching_pct: switchingPct,
        leakage_pct: leakagePct,
        area,
        utilization,
    };
}
// Stage-to-report file mapping
const REPORT_FILES = {
    synth: "synth_stat.txt",
    floorplan: "2_floorplan_final.rpt",
    place: "3_detailed_place.rpt",
    cts: "4_cts_final.rpt",
    route: "5_route_drc.rpt",
    finish: "6_finish.rpt",
};
export function getReport(designName, stage, orfsFlowPath) {
    const reportDir = join(orfsFlowPath, "reports", "sky130hd", designName, "base");
    const reportFile = REPORT_FILES[stage];
    if (!reportFile) {
        return { error: `Unknown stage: ${stage}` };
    }
    const content = readReportFile(join(reportDir, reportFile));
    if (content === null) {
        return { error: `Report not found: ${reportFile}` };
    }
    switch (stage) {
        case "synth":
            return parseSynthStat(content);
        case "floorplan":
        case "place":
        case "cts":
            return parseTimingReport(content);
        case "route":
            return parseDrcReport(content);
        case "finish":
            return parseFinishReport(content);
        default:
            return { error: `Unsupported stage: ${stage}` };
    }
}
//# sourceMappingURL=reports.js.map