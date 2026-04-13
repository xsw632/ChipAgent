import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";

export interface QorRun {
  readonly round: number;
  readonly config: Record<string, unknown>;
  readonly metrics: Record<string, unknown>;
  readonly status: "pass" | "fail";
  readonly error_type?: string;
  readonly timestamp: string;
}

export function loadHistory(historyPath: string): readonly QorRun[] {
  if (!existsSync(historyPath)) return [];
  const content = readFileSync(historyPath, "utf-8");
  return JSON.parse(content) as QorRun[];
}

export function saveRun(historyPath: string, run: QorRun): readonly QorRun[] {
  mkdirSync(dirname(historyPath), { recursive: true });
  const history = loadHistory(historyPath);
  const updated = [...history, run];
  writeFileSync(historyPath, JSON.stringify(updated, null, 2), "utf-8");
  return updated;
}

export function recommendBest(runs: readonly QorRun[]): QorRun | null {
  const passing = runs.filter((r) => {
    if (r.status !== "pass") return false;
    const wns = r.metrics.wns as number | undefined;
    if (wns === undefined || wns < 0) return false;
    const drc = (r.metrics.drc_violations as number | undefined) ?? 0;
    if (drc !== 0) return false;
    return true;
  });

  if (passing.length === 0) return null;

  const sorted = [...passing].sort((a, b) => {
    const cpA = (a.config.clock_period_ns as number) ?? Infinity;
    const cpB = (b.config.clock_period_ns as number) ?? Infinity;
    if (cpA !== cpB) return cpA - cpB;
    const areaA = (a.metrics.area as number) ?? Infinity;
    const areaB = (b.metrics.area as number) ?? Infinity;
    if (areaA !== areaB) return areaA - areaB;
    const powerA = (a.metrics.total_power_w as number | undefined) ?? Infinity;
    const powerB = (b.metrics.total_power_w as number | undefined) ?? Infinity;
    return powerA - powerB;
  });

  return sorted[0];
}

export function registerCompareRuns(server: McpServer): void {
  server.tool(
    "compare_runs",
    "Save, load, recommend best, or clear PnR run QoR history",
    {
      action: z
        .enum(["save", "load", "recommend", "clear"])
        .describe("Operation to perform"),
      workspace_dir: z
        .string()
        .describe("Absolute path to module workspace directory"),
      run: z
        .object({
          round: z.number(),
          config: z.any(),
          metrics: z.any(),
          status: z.enum(["pass", "fail"]),
          error_type: z.string().optional(),
          timestamp: z.string().optional(),
        })
        .optional()
        .describe("Run data (required for save action)"),
    },
    async ({ action, workspace_dir, run }) => {
      const historyPath = resolve(workspace_dir, "qor_history.json");

      switch (action) {
        case "save": {
          if (!run) {
            return {
              content: [
                {
                  type: "text" as const,
                  text: JSON.stringify(
                    { error: "run data is required for save action" },
                    null,
                    2,
                  ),
                },
              ],
              isError: true,
            };
          }
          const entry: QorRun = {
            round: run.round,
            config: run.config,
            metrics: run.metrics,
            status: run.status,
            ...(run.error_type !== undefined
              ? { error_type: run.error_type }
              : {}),
            timestamp: run.timestamp ?? new Date().toISOString(),
          };
          const updated = saveRun(historyPath, entry);
          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify(
                  { saved: true, total_runs: updated.length, history: updated },
                  null,
                  2,
                ),
              },
            ],
          };
        }

        case "load": {
          const history = loadHistory(historyPath);
          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify(
                  { total_runs: history.length, history },
                  null,
                  2,
                ),
              },
            ],
          };
        }

        case "recommend": {
          const history = loadHistory(historyPath);
          const best = recommendBest(history);
          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify(
                  {
                    total_runs: history.length,
                    recommendation: best,
                    message: best
                      ? `Best run: round ${best.round} (clock=${best.config.clock_period_ns}ns, WNS=${best.metrics.wns}ns, area=${best.metrics.area}, power=${best.metrics.total_power_w ?? 'N/A'}W)`
                      : "No passing run found with WNS >= 0 and zero DRC violations",
                  },
                  null,
                  2,
                ),
              },
            ],
          };
        }

        case "clear": {
          mkdirSync(dirname(historyPath), { recursive: true });
          writeFileSync(historyPath, JSON.stringify([], null, 2), "utf-8");
          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify(
                  { cleared: true, total_runs: 0 },
                  null,
                  2,
                ),
              },
            ],
          };
        }
      }
    },
  );
}
