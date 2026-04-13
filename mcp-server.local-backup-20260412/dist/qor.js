import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
function historyPath(workspaceDir) {
    return join(workspaceDir, "qor_history.json");
}
function readHistory(workspaceDir) {
    const filePath = historyPath(workspaceDir);
    try {
        const content = readFileSync(filePath, "utf-8");
        const parsed = JSON.parse(content);
        return Array.isArray(parsed) ? parsed : [];
    }
    catch {
        return [];
    }
}
function writeHistory(workspaceDir, runs) {
    writeFileSync(historyPath(workspaceDir), JSON.stringify(runs, null, 2), "utf-8");
}
export function clearHistory(workspaceDir) {
    writeHistory(workspaceDir, []);
    return { success: true };
}
export function saveRun(workspaceDir, run) {
    const runs = readHistory(workspaceDir);
    runs.push(run);
    writeHistory(workspaceDir, runs);
    return { success: true };
}
export function loadRuns(workspaceDir) {
    return { runs: readHistory(workspaceDir) };
}
export function recommendRun(workspaceDir) {
    const runs = readHistory(workspaceDir);
    const passing = runs.filter((r) => r.status === "pass");
    if (passing.length === 0) {
        return { best_run: null, reason: "No passing run found" };
    }
    // Score: prefer WNS >= 0 (higher is safer), then fewest DRC violations, then smallest area
    const sorted = [...passing].sort((a, b) => {
        const wnsA = a.metrics.wns ?? -Infinity;
        const wnsB = b.metrics.wns ?? -Infinity;
        if (wnsA !== wnsB)
            return wnsB - wnsA; // higher WNS first
        const drcA = a.metrics.drc_violations ?? Infinity;
        const drcB = b.metrics.drc_violations ?? Infinity;
        if (drcA !== drcB)
            return drcA - drcB; // fewer DRC first
        const areaA = a.metrics.area ?? Infinity;
        const areaB = b.metrics.area ?? Infinity;
        return areaA - areaB; // smaller area first
    });
    const best = sorted[0];
    return {
        best_run: best,
        reason: `Round ${best.round}: best WNS=${best.metrics.wns}, area=${best.metrics.area}`,
    };
}
//# sourceMappingURL=qor.js.map