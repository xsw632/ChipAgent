<<<<<<< HEAD
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export const VALID_STAGES = ["synth", "floorplan", "place", "cts", "route", "finish"] as const;
type Stage = (typeof VALID_STAGES)[number];

=======
import { spawn, execSync } from "node:child_process";
import { existsSync, readFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
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
  docker_results_dir?: string;
}

export const VALID_STAGES = ["synth", "floorplan", "place", "cts", "route", "finish"] as const;
type Stage = (typeof VALID_STAGES)[number];

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
}

>>>>>>> main
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

<<<<<<< HEAD
=======
function hostPath(workspaceDir: string, containerPath: string): string {
  // Convert a container /workspace path to the corresponding host absolute path
  if (containerPath.startsWith("/workspace")) {
    return containerPath.replace("/workspace", workspaceDir);
  }
  return containerPath;
}

function containerPath(workspaceDir: string, hostPath: string): string {
  // Convert a host absolute path to the corresponding container /workspace path
  return hostPath.replace(workspaceDir, "/workspace");
}

function ensureDir(dir: string): void {
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
}

>>>>>>> main
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
<<<<<<< HEAD
      const { args, cwd, env } = buildMakeArgs(stage, config_mk_path, orfs_flow_path);
      const designName = extractDesignName(config_mk_path);
      const logPath = `${orfs_flow_path}/logs/sky130hd/${designName}/base/`;
=======
      const workspaceConfig = readWorkspaceConfig();
      const designName = extractDesignName(configMkPath);

      // logPath uses the container path (for display), but in Docker mode
      // the actual results are at the mounted results_dir path
      const containerLogPath = `${orfs_flow_path}/logs/sky130hd/${designName}/base/`;
      const hostLogPath = workspaceConfig?.backend_mode === "docker" && workspaceConfig.docker_results_dir
        ? `${workspaceConfig.docker_results_dir}/OpenROAD-flow-scripts/flow/logs/sky130hd/${designName}/base/`
        : containerLogPath;
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
          const workspaceDir = workspaceConfig.workspace_dir;
          const dockerImage = workspaceConfig.docker_image ?? "openroad/orfs:latest";
          const dockerWorkdir = workspaceConfig.docker_workdir ?? "/OpenROAD-flow-scripts/flow";
          const resultsDir = workspaceConfig.docker_results_dir ?? workspaceDir;

          // Build docker run volumes: workspace mount + ORFS results mount
          const volumes: string[] = [
            `${workspaceDir}:/workspace`,
            `${resultsDir}:${dockerWorkdir}`,
          ];

          // Ensure host-side results directories exist so ORFS can write into them
          const hostResultsDir = `${resultsDir}/OpenROAD-flow-scripts/flow`;
          const hostReportsDir = `${hostResultsDir}/reports/sky130hd/${designName}/base`;
          const hostLogsDir = `${hostResultsDir}/logs/sky130hd/${designName}/base`;
          const hostResults2Dir = `${hostResultsDir}/results/sky130hd/${designName}/base`;
          ensureDir(hostReportsDir);
          ensureDir(hostLogsDir);
          ensureDir(hostResults2Dir);

          // Container paths for DESIGN_CONFIG and results
          const containerConfigPath = containerPath(workspaceDir, config_mk_path);

          const dockerArgs = [
            "run",
            "--rm",
            ...volumes.flatMap((v) => ["-v", v]),
            "-w",
            dockerWorkdir,
            dockerImage,
            "make",
            stage,
            `DESIGN_CONFIG=${containerConfigPath}`,
          ];

          proc = spawn("docker", dockerArgs, {
            env: { ...process.env },
            stdio: ["ignore", "pipe", "pipe"],
          });
        } else {
          // Local mode: run make directly
          const { args, cwd, env } = buildMakeArgs(stage, config_mk_path, orfs_flow_path);
          proc = spawn("make", args, {
            cwd,
            env: env as NodeJS.ProcessEnv,
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

<<<<<<< HEAD
      const output = { ...result, stage, log_path: logPath };
=======
      const output = { ...result, stage, log_path: hostLogPath };
>>>>>>> main
      return { content: [{ type: "text" as const, text: JSON.stringify(output, null, 2) }] };
    },
  );
}
