import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";
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

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Build a list of candidate directories where ORFS might be installed,
 * ordered by priority. Each candidate is checked for the existence of
 * `flow/Makefile` to confirm a valid installation.
 */
function getOrfsCandidates(): ReadonlyArray<string> {
  const candidates: Array<string> = [];

  // 1. ORFS_DIR environment variable (explicit override)
  const envDir = process.env["ORFS_DIR"];
  if (envDir) {
    candidates.push(envDir);
  }

  // 2. Walk upward from this file's directory to find a sibling
  //    OpenROAD-flow-scripts/ directory. This works whether the file
  //    lives in the source repo or in the installed plugin copy
  //    (which may be nested deeper).
  let dir = __dirname;
  for (let i = 0; i < 10; i++) {
    candidates.push(join(dir, "OpenROAD-flow-scripts"));
    const parent = dirname(dir);
    if (parent === dir) break; // filesystem root
    dir = parent;
  }

  return candidates;
}

export function findOrfs(): OrfsResult {
  const candidates = getOrfsCandidates();

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

export function findSky130hd(orfsFlowPath: string | null): Sky130hdResult {
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
