import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

interface OrfsResult {
  installed: boolean;
  path: string | null;
  flow_path: string | null;
}

interface Sky130hdResult {
  installed: boolean;
  path: string | null;
  liberty: string | null;
  tech_lef: string | null;
  cell_lef: string | null;
  gds: string | null;
}

interface DockerResult {
  installed: boolean;
  version: string | null;
}

interface EnvironmentResult {
  orfs: OrfsResult;
  sky130hd: Sky130hdResult;
  docker: DockerResult;
  backend_mode: "local" | "docker";
}

function findOrfs(): OrfsResult {
  const candidates: string[] = [];

  if (process.env["ORFS_DIR"]) {
    candidates.push(process.env["ORFS_DIR"]);
  }
  if (process.env["HOME"]) {
    candidates.push(join(process.env["HOME"], "OpenROAD-flow-scripts"));
  }
  candidates.push("/opt/OpenROAD-flow-scripts");

  for (const candidate of candidates) {
    const flowMakefile = join(candidate, "flow", "Makefile");
    if (existsSync(flowMakefile)) {
      return {
        installed: true,
        path: candidate,
        flow_path: join(candidate, "flow"),
      };
    }
  }

  return { installed: false, path: null, flow_path: null };
}

function findSky130hd(orfsFlowPath: string | null): Sky130hdResult {
  if (!orfsFlowPath) {
    return { installed: false, path: null, liberty: null, tech_lef: null, cell_lef: null, gds: null };
  }

  const platformDir = join(orfsFlowPath, "platforms", "sky130hd");
  const libertyRel = "lib/sky130_fd_sc_hd__tt_025C_1v80.lib";
  const libertyAbs = join(platformDir, libertyRel);

  if (!existsSync(libertyAbs)) {
    return { installed: false, path: null, liberty: null, tech_lef: null, cell_lef: null, gds: null };
  }

  return {
    installed: true,
    path: platformDir,
    liberty: libertyRel,
    tech_lef: "lef/sky130_fd_sc_hd.tlef",
    cell_lef: "lef/sky130_fd_sc_hd_merged.lef",
    gds: "gds/sky130_fd_sc_hd.gds",
  };
}

function detectDocker(): DockerResult {
  try {
    const version = execSync("docker --version", { encoding: "utf-8", timeout: 5000 }).trim();
    return { installed: true, version };
  } catch {
    return { installed: false, version: null };
  }
}

export function registerCheckEnvironment(server: McpServer): void {
  server.tool(
    "check_environment",
    "Reports ORFS, sky130hd PDK, and Docker environment status for ChipAgent backend",
    {},
    async (): Promise<{ content: Array<{ type: "text"; text: string }> }> => {
      const orfs = findOrfs();
      const sky130hd = findSky130hd(orfs.flow_path);
      const docker = detectDocker();

      const result: EnvironmentResult = {
        orfs,
        sky130hd,
        docker,
        backend_mode: orfs.installed ? "local" : "docker",
      };

      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    },
  );
}
