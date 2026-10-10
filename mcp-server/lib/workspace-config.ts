import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface WorkspaceConfig {
  workspace_dir: string;
  backend_mode: string;
  mcp_server_path?: string;
  docker_image?: string;
  docker_volumes?: string[];
  docker_workdir?: string;
  docker_results_dir?: string;
  orfs_flow_path?: string;
}

/** Legacy TypeScript backend configuration; shared by all ORFS tools. */
export function readWorkspaceConfig(
  configPath = join(homedir(), ".chipagent", "workspace.json"),
): WorkspaceConfig | null {
  try {
    return JSON.parse(readFileSync(configPath, "utf-8")) as WorkspaceConfig;
  } catch {
    return null;
  }
}
