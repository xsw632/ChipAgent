#!/usr/bin/env python3
"""ChipAgent Backend MCP Server — Python implementation."""

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from datetime import datetime

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("chipagent-backend")

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent.parent

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _tail_lines(text: str, n: int) -> str:
    lines = text.split("\n")
    return "\n".join(lines[-n:])


def _env_config_path() -> Path:
    return PROJECT_ROOT / ".chipagent" / "env.json"


def _read_env_json() -> dict:
    p = _env_config_path()
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except Exception:
        return {}


# ---------------------------------------------------------------------------
# Tool: check_environment
# ---------------------------------------------------------------------------

@mcp.tool()
def check_environment() -> str:
    """Reports ORFS and sky130hd PDK environment status for ChipAgent local backend."""

    env = _read_env_json()
    orfs_flow = env.get("orfs", {}).get("flow_path")

    # Try to find ORFS
    orfs_installed = False
    orfs_path = None
    if orfs_flow and Path(orfs_flow).exists():
        orfs_installed = True
        orfs_path = str(Path(orfs_flow).parent)
    else:
        # Walk up from PROJECT_ROOT looking for OpenROAD-flow-scripts
        for parent in [PROJECT_ROOT] + list(PROJECT_ROOT.parents)[:10]:
            candidate = parent / "OpenROAD-flow-scripts"
            if (candidate / "flow" / "Makefile").exists():
                orfs_installed = True
                orfs_path = str(candidate)
                orfs_flow = str(candidate / "flow")
                break

    # Check sky130hd
    sky130hd = {"installed": False, "path": None}
    if orfs_flow:
        plat_dir = Path(orfs_flow) / "platforms" / "sky130hd"
        lib_file = plat_dir / "lib" / "sky130_fd_sc_hd__tt_025C_1v80.lib"
        if lib_file.exists():
            sky130hd = {
                "installed": True,
                "path": str(plat_dir),
                "liberty": "lib/sky130_fd_sc_hd__tt_025C_1v80.lib",
                "tech_lef": "lef/sky130_fd_sc_hd.tlef",
                "cell_lef": "lef/sky130_fd_sc_hd_merged.lef",
                "gds": "gds/sky130_fd_sc_hd.gds",
            }

    result = {
        "orfs": {
            "installed": orfs_installed,
            "path": orfs_path,
            "flow_path": orfs_flow,
        },
        "sky130hd": sky130hd,
    }
    return json.dumps(result, indent=2)


# ---------------------------------------------------------------------------
# Tool: generate_config
# ---------------------------------------------------------------------------

@mcp.tool()
def generate_config(
    module_name: str,
    verilog_path: str,
    workspace_dir: str,
    clock_port: str = "clock",
    clock_period_ns: float = 10,
    core_utilization: float = 40,
    place_density: float | None = None,
    gpl_timing_driven: bool | None = None,
    gpl_routability_driven: bool | None = None,
) -> str:
    """Generate ORFS config.mk and constraint.sdc for a compiled Verilog module."""

    verilog_abs = str(Path(verilog_path).resolve())
    verilog_content = Path(verilog_abs).read_text()

    design_name = module_name or _resolve_module_name(verilog_content)
    pnr_dir = Path(workspace_dir).resolve()
    pnr_dir.mkdir(parents=True, exist_ok=True)

    sdc_abs = str(pnr_dir / "constraint.sdc")
    config_path = str(pnr_dir / "config.mk")

    config_mk = _generate_config_mk(
        design_name, verilog_abs, sdc_abs, core_utilization,
        place_density, gpl_timing_driven, gpl_routability_driven,
    )
    sdc = _generate_sdc(design_name, verilog_content, clock_port, clock_period_ns)

    Path(config_path).write_text(config_mk)
    Path(sdc_abs).write_text(sdc)

    result = {
        "config_mk": config_path,
        "constraint_sdc": sdc_abs,
        "design_name": design_name,
    }
    return json.dumps(result, indent=2)


def _resolve_module_name(content: str, override: str | None = None) -> str:
    if override:
        return override
    match = re.search(r"^module\s+(\w+)", content, re.MULTILINE)
    if not match:
        raise ValueError("Could not extract module name from Verilog content")
    return match.group(1)


def _is_sequential(content: str) -> bool:
    return bool(re.search(r"always\s+@\s*\(\s*posedge", content))


def _generate_config_mk(
    design_name: str,
    verilog_abs: str,
    sdc_abs: str,
    core_utilization: float,
    place_density: float | None,
    gpl_timing_driven: bool | None,
    gpl_routability_driven: bool | None,
) -> str:
    lines = [
        f"export DESIGN_NAME = {design_name}",
        f"export PLATFORM = sky130hd",
        f"export VERILOG_FILES = {verilog_abs}",
        f"export SDC_FILE = {sdc_abs}",
        f"export CORE_UTILIZATION = {core_utilization}",
        "export TNS_END_PERCENT = 100",
    ]
    if place_density is not None:
        lines.append(f"export PLACE_DENSITY = {place_density}")
    if gpl_timing_driven is not None:
        lines.append(f"export GPL_TIMING_DRIVEN = {1 if gpl_timing_driven else 0}")
    if gpl_routability_driven is not None:
        lines.append(f"export GPL_ROUTABILITY_DRIVEN = {1 if gpl_routability_driven else 0}")
    lines.append("")
    return "\n".join(lines)


def _generate_sdc(
    design_name: str,
    verilog_content: str,
    clock_port: str,
    clock_period_ns: float,
) -> str:
    if _is_sequential(verilog_content):
        return "\n".join([
            f"current_design {design_name}",
            f"create_clock -name core_clock -period {clock_period_ns} [get_ports {clock_port}]",
            "set_input_delay -clock core_clock 0 [all_inputs -no_clocks]",
            "set_output_delay -clock core_clock 0 [all_outputs]",
            "",
        ])
    # Combinational: virtual clock
    return "\n".join([
        f"create_clock -name virtual_clk -period {clock_period_ns}",
        "set_input_delay -clock virtual_clk 0 [all_inputs]",
        "set_output_delay -clock virtual_clk 0 [all_outputs]",
        f"set_max_delay {clock_period_ns} -from [all_inputs] -to [all_outputs]",
        "",
    ])


# ---------------------------------------------------------------------------
# Tool: run_stage
# ---------------------------------------------------------------------------

VALID_STAGES = ["synth", "floorplan", "place", "cts", "route", "finish"]

@mcp.tool()
def run_stage(
    stage: str,
    config_mk_path: str,
    orfs_flow_path: str,
    timeout_minutes: int = 10,
) -> str:
    """Execute an ORFS make target (synth, floorplan, place, cts, route, finish) and return status with log path."""

    # Extract design nickname from config.mk
    config_content = Path(config_mk_path).read_text()
    nick_match = re.search(r"DESIGN_NICKNAME\s*=\s*(\w+)", config_content)
    design_nickname = nick_match.group(1) if nick_match else "unknown"

    log_path = f"{orfs_flow_path}/logs/sky130hd/{design_nickname}/base/"

    env = {**os.environ, "DESIGN_CONFIG": config_mk_path}

    try:
        proc = subprocess.run(
            ["make", stage],
            cwd=orfs_flow_path,
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout_minutes * 60,
        )
        result = {
            "success": proc.returncode == 0,
            "exit_code": proc.returncode,
            "stdout": _tail_lines(proc.stdout, 500),
            "stderr": _tail_lines(proc.stderr, 500),
            "stage": stage,
            "log_path": log_path,
        }
    except subprocess.TimeoutExpired:
        result = {
            "success": False,
            "exit_code": None,
            "stdout": "",
            "stderr": f"Process timed out after {timeout_minutes} minutes",
            "stage": stage,
            "log_path": log_path,
        }
    except Exception as e:
        result = {
            "success": False,
            "exit_code": None,
            "stdout": "",
            "stderr": str(e),
            "stage": stage,
            "log_path": log_path,
        }

    return json.dumps(result, indent=2)


# ---------------------------------------------------------------------------
# Tool: get_report
# ---------------------------------------------------------------------------

STAGE_REPORT_MAP = {
    "synth": ["synth_stat.txt"],
    "floorplan": ["2_floorplan_final.rpt"],
    "place": ["3_detailed_place.rpt"],
    "cts": ["4_cts_final.rpt"],
    "route": ["5_route_drc.rpt"],
    "finish": ["6_finish.rpt"],
}


@mcp.tool()
def get_report(
    design_name: str,
    stage: str,
    orfs_flow_path: str,
) -> str:
    """Extract stage-specific metrics from ORFS report files as structured JSON."""

    report_dir = Path(orfs_flow_path) / "reports" / "sky130hd" / design_name / "base"
    log_dir = Path(orfs_flow_path) / "logs" / "sky130hd" / design_name / "base"

    if not report_dir.exists():
        result = {
            "stage": stage,
            "error": f"Report not found. Run stage '{stage}' first.",
            "report_path": str(report_dir),
        }
        return json.dumps(result, indent=2)

    metrics: dict = {}
    files = STAGE_REPORT_MAP.get(stage, [])

    for fname in files:
        fpath = report_dir / fname
        if not fpath.exists():
            continue
        content = fpath.read_text()

        if fname == "synth_stat.txt":
            metrics.update(_parse_synth_stat(content))
            metrics.update(_parse_synth_area(content))
        elif fname == "6_finish.rpt":
            metrics.update(_parse_finish_report(content))
            metrics.update(_parse_power(content))
        elif fname == "5_route_drc.rpt":
            metrics.update(_parse_drc_report(content))
        else:
            metrics["raw"] = content[:2000]

    # For finish, also parse area from 6_report.log
    if stage == "finish":
        finish_log = log_dir / "6_report.log"
        if finish_log.exists():
            metrics.update(_parse_route_area(finish_log.read_text()))

    result = {
        "stage": stage,
        "metrics": metrics,
        "report_path": str(report_dir),
    }
    if stage == "finish":
        result["log_path"] = str(log_dir / "6_report.log")

    return json.dumps(result, indent=2)


def _parse_finish_report(content: str) -> dict:
    metrics = {}
    tns = re.search(r"report_tns\n-+\ntns max ([\d.-]+)", content)
    if tns:
        metrics["tns"] = tns.group(1)
    wns = re.search(r"report_wns\n-+\nwns max ([\d.-]+)", content)
    if wns:
        metrics["wns"] = wns.group(1)
    return metrics


def _parse_synth_stat(content: str) -> dict:
    match = re.search(r"Number of cells:\s+(\d+)", content)
    return {"cell_count": int(match.group(1)) if match else None}


def _parse_route_area(content: str) -> dict:
    match = re.search(r"Design area ([\d.]+) um\^2 ([\d.]+)% utilization", content)
    if match:
        return {"area": float(match.group(1)), "utilization": float(match.group(2))}
    return {"area": None, "utilization": None}


def _parse_drc_report(content: str) -> dict:
    if not content.strip():
        return {"violations": 0}
    matches = re.findall(r"violation type:", content, re.IGNORECASE)
    return {"violations": len(matches)}


def _parse_power(content: str) -> dict:
    result = {"total_w": None, "internal_pct": None, "switching_pct": None, "leakage_pct": None}
    total = re.search(r"^Total\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)", content, re.MULTILINE)
    if not total:
        return result
    result["total_w"] = float(total.group(4))
    pct = re.search(r"^\s+([\d.]+)%\s+([\d.]+)%\s+([\d.]+)%\s*$", content, re.MULTILINE)
    if pct:
        result["internal_pct"] = float(pct.group(1))
        result["switching_pct"] = float(pct.group(2))
        result["leakage_pct"] = float(pct.group(3))
    return result


def _parse_synth_area(content: str) -> dict:
    match = re.search(r"Chip area for module '\\?\w+':\s+([\d.]+)", content)
    return {"synth_area": float(match.group(1)) if match else None}


# ---------------------------------------------------------------------------
# Tool: diagnose_failure
# ---------------------------------------------------------------------------

PLACEMENT_OVERFLOW_RE = re.compile(r"placement overflow|not enough sites|Cannot place", re.IGNORECASE)
CONGESTION_RE = re.compile(r"GRT-0119|Routing congestion too high|Total overflow:\s*[1-9]", re.IGNORECASE)


@mcp.tool()
def diagnose_failure(
    stage: str,
    success: bool,
    stderr: str = "",
    finish_report_content: str | None = None,
    drc_report_content: str | None = None,
    sdc_content: str | None = None,
    current_clock_period_ns: float = 10,
    current_place_density: float = 0.6,
    current_core_utilization: float = 40,
) -> str:
    """Classify ORFS flow failure and suggest parameter adjustments for retry."""

    finish_wns = None
    if finish_report_content:
        metrics = _parse_finish_report(finish_report_content)
        if "wns" in metrics:
            finish_wns = float(metrics["wns"])

    drc_violations = None
    if drc_report_content:
        drc_violations = _parse_drc_report(drc_report_content)["violations"]

    classification = _classify_error(stage, success, stderr, finish_wns, drc_violations, sdc_content)
    suggested = _suggest_params(
        classification["error_type"],
        current_clock_period_ns,
        current_place_density,
        current_core_utilization,
    )

    result = {**classification, "suggested_params": suggested}
    return json.dumps(result, indent=2)


def _classify_error(stage, success, stderr, finish_wns, drc_violations, sdc_content) -> dict:
    # Priority 1: synthesis failure
    if stage == "synth" and not success:
        return {
            "error_type": "synthesis_error",
            "severity": "critical",
            "details": f"Synthesis failed: {stderr[:200]}",
            "restart_from": "synth",
        }

    # Priority 2: placement overflow
    if PLACEMENT_OVERFLOW_RE.search(stderr):
        return {
            "error_type": "placement_overflow",
            "severity": "recoverable",
            "details": "Placement overflow detected in stderr",
            "restart_from": "floorplan",
        }

    # Priority 3: congestion
    if CONGESTION_RE.search(stderr):
        return {
            "error_type": "congestion",
            "severity": "recoverable",
            "details": "Routing congestion detected in stderr",
            "restart_from": "place",
        }

    # Priority 4: DRC violations
    if drc_violations is not None and drc_violations > 0:
        return {
            "error_type": "drc",
            "severity": "recoverable",
            "details": f"{drc_violations} DRC violation(s) found",
            "restart_from": "place",
        }

    # Priority 5: silent timing violation (WNS < 0)
    if finish_wns is not None and finish_wns < 0:
        is_comb = sdc_content and re.search(r"virtual_clk", sdc_content, re.IGNORECASE)
        return {
            "error_type": "timing_violation",
            "severity": "critical" if is_comb else "recoverable",
            "details": f"Timing violation: WNS = {finish_wns} ns",
            "restart_from": "synth",
        }

    # Fallback
    return {
        "error_type": "unknown",
        "severity": "critical",
        "details": f"Unclassified failure at stage '{stage}': {stderr[:200]}",
        "restart_from": "synth",
    }


def _clamp(v, lo, hi):
    return max(lo, min(hi, v))


def _round_to(v, decimals):
    factor = 10 ** decimals
    return round(v * factor) / factor


def _suggest_params(error_type, cp, pd, cu) -> dict:
    if error_type == "timing_violation":
        return {"clock_period_ns": _clamp(_round_to(cp * 1.5, 2), 1.0, 100.0)}
    elif error_type == "congestion":
        return {"place_density": _clamp(_round_to(pd - 0.1, 2), 0.30, 0.85)}
    elif error_type == "drc":
        return {"place_density": _clamp(_round_to(pd - 0.05, 2), 0.30, 0.85)}
    elif error_type == "placement_overflow":
        return {"core_utilization": _clamp(cu - 15, 20, 70)}
    else:
        return {}


# ---------------------------------------------------------------------------
# Tool: clean_design
# ---------------------------------------------------------------------------

@mcp.tool()
def clean_design(
    config_mk_path: str,
    orfs_flow_path: str,
) -> str:
    """Reset ORFS cached artifacts for a design via make clean_all."""

    env = {**os.environ, "DESIGN_CONFIG": config_mk_path}

    try:
        proc = subprocess.run(
            ["make", "clean_all"],
            cwd=orfs_flow_path,
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        result = {
            "success": proc.returncode == 0,
            "exit_code": proc.returncode,
            "stdout": _tail_lines(proc.stdout, 100),
            "stderr": _tail_lines(proc.stderr, 100),
        }
    except subprocess.TimeoutExpired:
        result = {
            "success": False,
            "exit_code": None,
            "stdout": "",
            "stderr": "Process timed out after 30 seconds",
        }
    except Exception as e:
        result = {
            "success": False,
            "exit_code": None,
            "stdout": "",
            "stderr": str(e),
        }

    return json.dumps(result, indent=2)


# ---------------------------------------------------------------------------
# Tool: compare_runs
# ---------------------------------------------------------------------------

@mcp.tool()
def compare_runs(
    action: str,
    workspace_dir: str,
    round: int | None = None,
    config: dict | None = None,
    metrics: dict | None = None,
    status: str | None = None,
    error_type: str | None = None,
    timestamp: str | None = None,
) -> str:
    """Save, load, recommend best, or clear PnR run QoR history."""

    history_path = Path(workspace_dir).resolve() / "qor_history.json"

    if action == "save":
        if round is None or config is None or metrics is None or status is None:
            return json.dumps({"error": "round, config, metrics, status are required for save action"}, indent=2)
        entry = {
            "round": round,
            "config": config,
            "metrics": metrics,
            "status": status,
        }
        if error_type is not None:
            entry["error_type"] = error_type
        entry["timestamp"] = timestamp or datetime.now().isoformat()

        history = _load_history(history_path)
        history.append(entry)
        history_path.parent.mkdir(parents=True, exist_ok=True)
        history_path.write_text(json.dumps(history, indent=2))

        return json.dumps({"saved": True, "total_runs": len(history), "history": history}, indent=2)

    elif action == "load":
        history = _load_history(history_path)
        return json.dumps({"total_runs": len(history), "history": history}, indent=2)

    elif action == "recommend":
        history = _load_history(history_path)
        best = _recommend_best(history)
        msg = (
            f"Best run: round {best['round']} (clock={best['config'].get('clock_period_ns')}ns, WNS={best['metrics'].get('wns')}ns, area={best['metrics'].get('area')}, power={best['metrics'].get('total_power_w', 'N/A')}W)"
            if best
            else "No passing run found with WNS >= 0 and zero DRC violations"
        )
        return json.dumps({"total_runs": len(history), "recommendation": best, "message": msg}, indent=2)

    elif action == "clear":
        history_path.parent.mkdir(parents=True, exist_ok=True)
        history_path.write_text(json.dumps([], indent=2))
        return json.dumps({"cleared": True, "total_runs": 0}, indent=2)

    else:
        return json.dumps({"error": f"Unknown action: {action}"}, indent=2)


def _load_history(path: Path) -> list:
    if not path.exists():
        return []
    try:
        return json.loads(path.read_text())
    except Exception:
        return []


def _recommend_best(history: list) -> dict | None:
    passing = []
    for r in history:
        if r.get("status") != "pass":
            continue
        wns = r.get("metrics", {}).get("wns")
        if wns is None or wns < 0:
            continue
        drc = r.get("metrics", {}).get("drc_violations", 0) or 0
        if drc != 0:
            continue
        passing.append(r)

    if not passing:
        return None

    def sort_key(r):
        cp = r.get("config", {}).get("clock_period_ns", float("inf"))
        area = r.get("metrics", {}).get("area", float("inf"))
        power = r.get("metrics", {}).get("total_power_w", float("inf"))
        return (cp, area, power)

    passing.sort(key=sort_key)
    return passing[0]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run()