import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export const VALID_STAGES = ["synth", "floorplan", "place", "cts", "route", "finish"] as const;
type Stage = (typeof VALID_STAGES)[number];

export function buildMakeArgs(
  stage: string,
  configMkPath: string,
  orfsFlowPath: string,
): { args: string[]; cwd: string; env: Record<string, string | undefined> } {
  return {
    args: [stage],
    cwd: orfsFlowPath,
    env: { ...process.env, DESIGN_CONFIG: configMkPath },
  };
}

function extractDesignName(configMkPath: string): string {
  try {
    const content = readFileSync(configMkPath, "utf-8");
    const match = content.match(/DESIGN_NAME\s*=\s*(\w+)/);
    return match ? match[1] : "unknown";
  } catch {
    return "unknown";
  }
}

function tailLines(text: string, n: number): string {
  const lines = text.split("\n");
  return lines.slice(-n).join("\n");
}

export function registerRunStage(server: McpServer): void {
  server.tool(
    "run_stage",
    "Execute an ORFS make target (synth, floorplan, place, cts, route, finish) and return status with log path",
    {
      stage: z.enum(VALID_STAGES).describe("ORFS make target to execute"),
      config_mk_path: z.string().describe("Absolute path to config.mk"),
      orfs_flow_path: z.string().describe("Absolute path to ORFS flow/ directory"),
    },
    async ({ stage, config_mk_path, orfs_flow_path }) => {
      const { args, cwd, env } = buildMakeArgs(stage, config_mk_path, orfs_flow_path);
      const designName = extractDesignName(config_mk_path);
      const logPath = `${orfs_flow_path}/logs/sky130hd/${designName}/base/`;

      const result = await new Promise<{
        success: boolean;
        exit_code: number | null;
        stdout: string;
        stderr: string;
      }>((resolve) => {
        let stdout = "";
        let stderr = "";

        const proc = spawn("make", args, {
          cwd,
          env: env as NodeJS.ProcessEnv,
          stdio: ["ignore", "pipe", "pipe"],
        });

        proc.stdout.on("data", (chunk: Buffer) => {
          stdout += chunk.toString();
        });
        proc.stderr.on("data", (chunk: Buffer) => {
          stderr += chunk.toString();
        });

        const timeout = setTimeout(() => {
          proc.kill("SIGTERM");
          resolve({ success: false, exit_code: null, stdout: tailLines(stdout, 500), stderr: "Process timed out after 10 minutes" });
        }, 600_000);

        proc.on("close", (code) => {
          clearTimeout(timeout);
          resolve({
            success: code === 0,
            exit_code: code,
            stdout: tailLines(stdout, 500),
            stderr: tailLines(stderr, 500),
          });
        });

        proc.on("error", (err) => {
          clearTimeout(timeout);
          resolve({ success: false, exit_code: null, stdout: "", stderr: err.message });
        });
      });

      const output = { ...result, stage, log_path: logPath };
      return { content: [{ type: "text" as const, text: JSON.stringify(output, null, 2) }] };
    },
  );
}
