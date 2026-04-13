export interface DiagnosisInput {
  stage: string;
  success: boolean;
  stderr: string;
  finish_report_content?: string;
  drc_report_content?: string;
  sdc_content?: string;
  current_clock_period_ns?: number;
  current_place_density?: number;
  current_core_utilization?: number;
}

export interface DiagnosisResult {
  severity: "critical" | "adjustable";
  error_type: string;
  details: string;
  suggested_params: Record<string, number | boolean>;
  restart_from: string;
}

function isCriticalError(stderr: string): boolean {
  const criticalPatterns = [
    /syntax error/i,
    /cannot find module/i,
    /combinational loop/i,
    /elaboration failed/i,
    /no such file or directory.*\.v/i,
    /undefined module/i,
    /chisel execution failed/i,
  ];
  return criticalPatterns.some((p) => p.test(stderr));
}

export function diagnoseFailure(input: DiagnosisInput): DiagnosisResult {
  const { stage, success, stderr } = input;

  // Critical: synthesis errors that can't be fixed by parameter adjustment
  if (stage === "synth" && !success && isCriticalError(stderr)) {
    return {
      severity: "critical",
      error_type: "synthesis_error",
      details: "Synthesis failed with an unrecoverable error",
      suggested_params: {},
      restart_from: "synth",
    };
  }

  // Timing violations (negative WNS from finish, or resizer failures)
  if (stage === "finish" || (stage === "place" && !success && /resizer|timing/i.test(stderr))) {
    const currentPeriod = input.current_clock_period_ns ?? 10;
    const currentUtil = input.current_core_utilization ?? 40;

    const suggested: Record<string, number | boolean> = {};
    // Increase clock period by 20%
    suggested.clock_period_ns = Math.round(currentPeriod * 1.2 * 100) / 100;
    // Reduce utilization by 10 percentage points
    if (currentUtil > 20) {
      suggested.core_utilization = currentUtil - 10;
    }
    // Enable timing-driven placement
    suggested.gpl_timing_driven = true;

    return {
      severity: "adjustable",
      error_type: "timing_violation",
      details: `Timing violation detected. Increasing clock period to ${suggested.clock_period_ns}ns, reducing utilization to ${suggested.core_utilization ?? currentUtil}%`,
      suggested_params: suggested,
      restart_from: "synth",
    };
  }

  // DRC violations
  if (stage === "route") {
    const currentUtil = input.current_core_utilization ?? 40;
    const currentDensity = input.current_place_density;

    const suggested: Record<string, number | boolean> = {};
    // Reduce utilization
    if (currentUtil > 20) {
      suggested.core_utilization = currentUtil - 10;
    }
    // Reduce place density
    if (currentDensity !== undefined && currentDensity > 0.4) {
      suggested.place_density = Math.round((currentDensity - 0.05) * 100) / 100;
    }
    // Enable routability-driven placement
    suggested.gpl_routability_driven = true;

    return {
      severity: "adjustable",
      error_type: "drc_violation",
      details: `DRC violations detected. Reducing utilization to ${suggested.core_utilization ?? currentUtil}% and enabling routability-driven placement`,
      suggested_params: suggested,
      restart_from: "floorplan",
    };
  }

  // Congestion
  if (stage === "place" && /congestion/i.test(stderr)) {
    const currentUtil = input.current_core_utilization ?? 40;

    const suggested: Record<string, number | boolean> = {};
    if (currentUtil > 20) {
      suggested.core_utilization = currentUtil - 15;
    }
    suggested.gpl_routability_driven = true;

    return {
      severity: "adjustable",
      error_type: "congestion",
      details: `Congestion detected. Reducing utilization to ${suggested.core_utilization ?? currentUtil}%`,
      suggested_params: suggested,
      restart_from: "floorplan",
    };
  }

  // Floorplan failure
  if (stage === "floorplan" && !success) {
    const currentUtil = input.current_core_utilization ?? 40;

    return {
      severity: "adjustable",
      error_type: "floorplan_failure",
      details: `Floorplan failed. Reducing utilization from ${currentUtil}%`,
      suggested_params: {
        core_utilization: Math.max(currentUtil - 15, 20),
      },
      restart_from: "synth",
    };
  }

  // Generic stage failure
  return {
    severity: "adjustable",
    error_type: `${stage}_failure`,
    details: `Stage ${stage} failed. Retrying with adjusted parameters.`,
    suggested_params: {
      core_utilization: Math.max((input.current_core_utilization ?? 40) - 10, 20),
      gpl_timing_driven: true,
      gpl_routability_driven: true,
    },
    restart_from: "synth",
  };
}
