import { spawn } from "node:child_process";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function buildCleanArgs(
  configMkPath: string,
  orfsFlowPath: string,
): { args: string[]; cwd: string; env: Record<string, string | undefined> } {
  return {
    args: ["clean_all"],
    cwd: orfsFlowPath,
    env: { ...process.env, DESIGN_CONFIG: configMkPath },
  };
}

function tailLines(text: string, n: number): string {
  const lines = text.split("\n");
  return lines.slice(-n).join("\n");
}

export function registerCleanDesign(server: McpServer): void {
  server.tool(
    "clean_design",
    "Reset ORFS cached artifacts for a design via make clean_all",
    {
      config_mk_path: z.string().describe("Absolute path to config.mk"),
      orfs_flow_path: z.string().describe("Absolute path to ORFS flow/ directory"),
    },
    async ({ config_mk_path, orfs_flow_path }) => {
      const { args, cwd, env } = buildCleanArgs(config_mk_path, orfs_flow_path);

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
          resolve({
            success: false,
            exit_code: null,
            stdout: tailLines(stdout, 100),
            stderr: "Process timed out after 30 seconds",
          });
        }, 30_000);

        proc.on("close", (code) => {
          clearTimeout(timeout);
          resolve({
            success: code === 0,
            exit_code: code,
            stdout: tailLines(stdout, 100),
            stderr: tailLines(stderr, 100),
          });
        });

        proc.on("error", (err) => {
          clearTimeout(timeout);
          resolve({ success: false, exit_code: null, stdout: "", stderr: err.message });
        });
      });

      return { content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }] };
    },
  );
}
