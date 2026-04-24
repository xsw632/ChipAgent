import { spawn } from "node:child_process";
<<<<<<< HEAD
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
=======
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

interface WorkspaceConfig {
  workspace_dir: string;
  mcp_server_path: string;
  backend_mode: string;
  docker_image?: string;
  docker_volumes?: string[];
  docker_workdir?: string;
  orfs_flow_path?: string;
}

/**
 * Read ~/.chipagent/workspace.json for workspace configuration.
 * Returns null if the file does not exist.
 */
function readWorkspaceConfig(): WorkspaceConfig | null {
  try {
    const configPath = join(homedir(), ".chipagent", "workspace.json");
    if (!existsSync(configPath)) return null;
    const content = readFileSync(configPath, "utf-8");
    return JSON.parse(content) as WorkspaceConfig;
  } catch {
    return null;
  }
>>>>>>> main
}

function tailLines(text: string, n: number): string {
  const lines = text.split("\n");
<<<<<<< HEAD
  return lines.slice(-n).join("\n");
=======
  return lines.slice(-n). join("\n");
>>>>>>> main
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
<<<<<<< HEAD
      const { args, cwd, env } = buildCleanArgs(config_mk_path, orfs_flow_path);
=======
      const workspaceConfig = readWorkspaceConfig();
>>>>>>> main

      const result = await new Promise<{
        success: boolean;
        exit_code: number | null;
        stdout: string;
        stderr: string;
      }>((resolve) => {
        let stdout = "";
        let stderr = "";

<<<<<<< HEAD
        const proc = spawn("make", args, {
          cwd,
          env: env as NodeJS.ProcessEnv,
          stdio: ["ignore", "pipe", "pipe"],
        });
=======
        let proc: ReturnType<typeof spawn>;

        if (workspaceConfig?.backend_mode === "docker") {
          // Docker mode: run clean_all inside the openroad/orfs container
          const workspaceDir = workspaceConfig.workspace_dir;
          const dockerImage = workspaceConfig.docker_image ?? "openroad/orfs:latest";
          const dockerWorkdir = workspaceConfig.docker_workdir ?? "/OpenROAD-flow-scripts/flow";

          proc = spawn("docker", [
            "run",
            "--rm",
            "-v",
            `${workspaceDir}:/workspace`,
            "-w",
            dockerWorkdir,
            dockerImage,
            "make",
            "clean_all",
            `DESIGN_CONFIG=${config_mk_path.replace(workspaceDir, "/workspace")}`,
          ], {
            env: { ...process.env },
            stdio: ["ignore", "pipe", "pipe"],
          });
        } else {
          // Local mode
          proc = spawn("make", ["clean_all"], {
            cwd: orfs_flow_path,
            env: { ...process.env, DESIGN_CONFIG: config_mk_path },
            stdio: ["ignore", "pipe", "pipe"],
          });
        }
>>>>>>> main

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
