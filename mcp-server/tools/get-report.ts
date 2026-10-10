import { readWorkspaceConfig } from "../lib/workspace-config.ts";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function parseFinishReport(content: string): Record<string, string> {
  const metrics: Record<string, string> = {};
  const tnsMatch = content.match(/report_tns\n-+\ntns max ([\d.-]+)/);
  if (tnsMatch) metrics.tns = tnsMatch[1];
  const wnsMatch = content.match(/report_wns\n-+\nwns max ([\d.-]+)/);
  if (wnsMatch) metrics.wns = wnsMatch[1];
  return metrics;
}

export function parseSynthStat(content: string): { cell_count: number | null } {
  const match = content.match(/Number of cells:\s+(\d+)/);
  return { cell_count: match ? parseInt(match[1], 10) : null };
}

export function parseRouteArea(content: string): { area: number | null; utilization: number | null } {
  const match = content.match(/Design area ([\d.]+) um\^2 ([\d.]+)% utilization/);
  return match
    ? { area: parseFloat(match[1]), utilization: parseFloat(match[2]) }
    : { area: null, utilization: null };
}

export function parseDrcReport(content: string): { violations: number } {
  if (!content.trim()) return { violations: 0 };
  const matches = content.match(/violation type:/gi);
  return { violations: matches ? matches.length : 0 };
}

export function parsePower(content: string): {
  total_w: number | null;
  internal_pct: number | null;
  switching_pct: number | null;
  leakage_pct: number | null;
} {
  const nullResult = { total_w: null, internal_pct: null, switching_pct: null, leakage_pct: null };
  const totalMatch = content.match(/^Total\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)/m);
  if (!totalMatch) return nullResult;
  const total_w = parseFloat(totalMatch[4]);
  const pctMatch = content.match(/^\s+([\d.]+)%\s+([\d.]+)%\s+([\d.]+)%\s*$/m);
  if (!pctMatch) return { total_w, internal_pct: null, switching_pct: null, leakage_pct: null };
  return {
    total_w,
    internal_pct: parseFloat(pctMatch[1]),
    switching_pct: parseFloat(pctMatch[2]),
    leakage_pct: parseFloat(pctMatch[3]),
  };
}

export function parseSynthArea(content: string): { synth_area: number | null } {
  const match = content.match(/Chip area for module '\\?\w+':\s+([\d.]+)/);
  return { synth_area: match ? parseFloat(match[1]) : null };
}

const STAGE_REPORT_MAP: Record<string, string[]> = {
  synth: ["synth_stat.txt"],
  floorplan: ["2_floorplan_final.rpt"],
  place: ["3_detailed_place.rpt"],
  cts: ["4_cts_final.rpt"],
  route: ["5_route_drc.rpt"],
  finish: ["6_finish.rpt"],
};

function readIfExists(filePath: string): string | null {
  return existsSync(filePath) ? readFileSync(filePath, "utf-8") : null;
}

export function registerGetReport(server: McpServer): void {
  server.tool(
    "get_report",
    "Extract stage-specific metrics from ORFS report files as structured JSON",
    {
      design_name: z.string().describe("Design name (matches DESIGN_NAME in config.mk)"),
      stage: z.enum(["synth", "floorplan", "place", "cts", "route", "finish"]).describe("ORFS stage"),
      orfs_flow_path: z.string().describe("Absolute path to ORFS flow/ directory"),
    },
    async ({ design_name, stage, orfs_flow_path }) => {
      const workspaceConfig = readWorkspaceConfig();

      // In Docker mode, reports are written to the mounted results directory on the host,
      // not to the original orfs_flow_path (which is the container-internal path).
      let reportDir: string;
      let logDir: string;

      if (workspaceConfig?.backend_mode === "docker" && workspaceConfig.docker_results_dir) {
        // Reports live at docker_results_dir/OpenROAD-flow-scripts/flow/...
        const resultsBase = `${workspaceConfig.docker_results_dir}/OpenROAD-flow-scripts/flow`;
        reportDir = join(resultsBase, "reports", "sky130hd", design_name, "base");
        logDir = join(resultsBase, "logs", "sky130hd", design_name, "base");
      } else {
        // Local mode: use the orfs_flow_path directly
        reportDir = join(orfs_flow_path, "reports", "sky130hd", design_name, "base");
        logDir = join(orfs_flow_path, "logs", "sky130hd", design_name, "base");
      }

      if (!existsSync(reportDir)) {
        const result = { stage, error: `Report not found. Run stage '${stage}' first.`, report_path: reportDir };
        return { content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }] };
      }

      const files = STAGE_REPORT_MAP[stage] ?? [];
      const metrics: Record<string, unknown> = {};

      for (const file of files) {
        const filePath = join(reportDir, file);
        if (!existsSync(filePath)) continue;
        const content = readFileSync(filePath, "utf-8");

        if (file === "synth_stat.txt") {
          Object.assign(metrics, parseSynthStat(content), parseSynthArea(content));
        } else if (file === "6_finish.rpt") {
          Object.assign(metrics, parseFinishReport(content), parsePower(content));
        } else if (file === "5_route_drc.rpt") {
          Object.assign(metrics, parseDrcReport(content));
        } else {
          metrics.raw = content.slice(0, 2000);
        }
      }

      if (stage === "finish") {
        const finishLogPath = join(logDir, "6_report.log");
        const finishLogContent = readIfExists(finishLogPath);
        if (finishLogContent) {
          Object.assign(metrics, parseRouteArea(finishLogContent));
        }
      }

      const result = {
        stage,
        metrics,
        report_path: reportDir,
        log_path: stage === "finish" ? join(logDir, "6_report.log") : undefined,
      };
      return { content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }] };
    },
  );
}
