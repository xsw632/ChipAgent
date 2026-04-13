import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { parseFinishReport, parseDrcReport } from "./get-report.ts";

const VALID_STAGES = ["synth", "floorplan", "place", "cts", "route", "finish"] as const;

export interface DiagnosisResult {
  readonly error_type: "timing_violation" | "congestion" | "drc" | "placement_overflow" | "synthesis_error" | "unknown";
  readonly severity: "critical" | "recoverable";
  readonly details: string;
  readonly suggested_params: {
    readonly clock_period_ns?: number;
    readonly place_density?: number;
    readonly core_utilization?: number;
  };
  readonly restart_from: "synth" | "floorplan" | "place" | "cts" | "route" | "finish";
}

interface ClassifyInput {
  readonly stage: string;
  readonly success: boolean;
  readonly stderr: string;
  readonly finish_wns?: number;
  readonly drc_violations?: number;
  readonly sdc_content?: string;
}

const PLACEMENT_OVERFLOW_RE = /placement overflow|not enough sites|Cannot place/i;
const CONGESTION_RE = /GRT-0119|Routing congestion too high|Total overflow:\s*[1-9]/i;

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

export function classifyError(input: ClassifyInput): Omit<DiagnosisResult, "suggested_params"> {
  const { stage, success, stderr, finish_wns, drc_violations, sdc_content } = input;

  // Priority 1: synthesis failure
  if (stage === "synth" && !success) {
    return {
      error_type: "synthesis_error",
      severity: "critical",
      details: `Synthesis failed: ${stderr.slice(0, 200)}`,
      restart_from: "synth",
    };
  }

  // Priority 2: placement overflow
  if (PLACEMENT_OVERFLOW_RE.test(stderr)) {
    return {
      error_type: "placement_overflow",
      severity: "recoverable",
      details: `Placement overflow detected in stderr`,
      restart_from: "floorplan",
    };
  }

  // Priority 3: congestion
  if (CONGESTION_RE.test(stderr)) {
    return {
      error_type: "congestion",
      severity: "recoverable",
      details: `Routing congestion detected in stderr`,
      restart_from: "place",
    };
  }

  // Priority 4: DRC violations
  if (drc_violations !== undefined && drc_violations > 0) {
    return {
      error_type: "drc",
      severity: "recoverable",
      details: `${drc_violations} DRC violation(s) found`,
      restart_from: "place",
    };
  }

  // Priority 5: silent timing violation (WNS < 0)
  if (finish_wns !== undefined && finish_wns < 0) {
    const isCombinational = sdc_content !== undefined && /virtual_clk/i.test(sdc_content);
    return {
      error_type: "timing_violation",
      severity: isCombinational ? "critical" : "recoverable",
      details: `Timing violation: WNS = ${finish_wns} ns`,
      restart_from: "synth",
    };
  }

  // Fallback
  return {
    error_type: "unknown",
    severity: "critical",
    details: `Unclassified failure at stage '${stage}': ${stderr.slice(0, 200)}`,
    restart_from: "synth",
  };
}

export function suggestParams(
  error_type: DiagnosisResult["error_type"],
  current: { clock_period_ns?: number; place_density?: number; core_utilization?: number },
): DiagnosisResult["suggested_params"] {
  switch (error_type) {
    case "timing_violation": {
      const cp = current.clock_period_ns ?? 10;
      return { clock_period_ns: clamp(roundTo(cp * 1.5, 2), 1.0, 100.0) };
    }
    case "congestion": {
      const pd = current.place_density ?? 0.6;
      return { place_density: clamp(roundTo(pd - 0.1, 2), 0.30, 0.85) };
    }
    case "drc": {
      const pd = current.place_density ?? 0.6;
      return { place_density: clamp(roundTo(pd - 0.05, 2), 0.30, 0.85) };
    }
    case "placement_overflow": {
      const cu = current.core_utilization ?? 40;
      return { core_utilization: clamp(cu - 15, 20, 70) };
    }
    default:
      return {};
  }
}

export function registerDiagnoseFailure(server: McpServer): void {
  server.tool(
    "diagnose_failure",
    "Classify ORFS flow failure and suggest parameter adjustments for retry",
    {
      stage: z.enum(VALID_STAGES).describe("Which ORFS stage was running"),
      success: z.boolean().describe("Whether the stage exited with code 0"),
      stderr: z.string().optional().default("").describe("Stderr output from run_stage"),
      finish_report_content: z.string().optional().describe("Raw finish report text"),
      drc_report_content: z.string().optional().describe("Raw DRC report text"),
      sdc_content: z.string().optional().describe("SDC file content for timing classification"),
      current_clock_period_ns: z.number().optional().default(10).describe("Current clock period in ns"),
      current_place_density: z.number().optional().default(0.6).describe("Current placement density"),
      current_core_utilization: z.number().optional().default(40).describe("Current core utilization %"),
    },
    async ({
      stage, success, stderr,
      finish_report_content, drc_report_content, sdc_content,
      current_clock_period_ns, current_place_density, current_core_utilization,
    }): Promise<{ content: Array<{ type: "text"; text: string }> }> => {
      const finish_wns = finish_report_content
        ? (() => {
            const metrics = parseFinishReport(finish_report_content);
            return metrics.wns !== undefined ? parseFloat(metrics.wns) : undefined;
          })()
        : undefined;

      const drc_violations = drc_report_content
        ? parseDrcReport(drc_report_content).violations
        : undefined;

      const classification = classifyError({ stage, success, stderr, finish_wns, drc_violations, sdc_content });

      const suggested_params = suggestParams(classification.error_type, {
        clock_period_ns: current_clock_period_ns,
        place_density: current_place_density,
        core_utilization: current_core_utilization,
      });

      const result: DiagnosisResult = { ...classification, suggested_params };

      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );
}
