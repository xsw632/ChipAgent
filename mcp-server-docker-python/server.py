#!/usr/bin/env python3
"""ChipAgent Backend Docker MCP Server — Python implementation.

Runs ORFS PnR stages inside Docker containers via the openroad/orfs image.
All tool APIs match the local server but execute through docker run.
"""

import json
import os
import re
import subprocess
import threading
from datetime import datetime
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("chipagent-backend-docker")

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent


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


class DockerConfig:
    __slots__ = ("image", "workdir")

    def __init__(self, image: str, workdir: str) -> None:
        self.image = image
        self.workdir = workdir


DEFAULT_DOCKER_CONFIG = DockerConfig(
    image="openroad/orfs:latest",
    workdir="/OpenROAD-flow-scripts/flow",
)


def _read_docker_config() -> DockerConfig:
    raw = _read_env_json()
    dc = raw.get("docker_config", {})
    return DockerConfig(
        image=dc.get("image", DEFAULT_DOCKER_CONFIG.image),
        workdir=dc.get("workdir", DEFAULT_DOCKER_CONFIG.workdir),
    )


def _container_path(host_path: str) -> str:
    return host_path.replace(str(PROJECT_ROOT), "/workspace")


def _ensure_dir(dir_path: str) -> None:
    Path(dir_path).mkdir(parents=True, exist_ok=True)


def _extract_design_name(config_mk_path: str) -> str:
    try:
        content = Path(config_mk_path).read_text()
        match = re.search(r"DESIGN_NAME\s*=\s*(\w+)", content)
        return match.group(1) if match else "unknown"
    except Exception:
        return "unknown"


def _extract_design_nickname(config_mk_path: str) -> str:
    try:
        content = Path(config_mk_path).read_text()
        match = re.search(r"DESIGN_NICKNAME\s*=\s*(\w+)", content)
        return match.group(1) if match else _extract_design_name(config_mk_path)
    except Exception:
        return "unknown"


def _run_docker_command(
    docker_args: list[str],
    timeout_seconds: int,
    tail_stdout: int = 500,
    tail_stderr: int = 500,
) -> dict:
    proc = subprocess.Popen(
        docker_args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    stdout_chunks: list[str] = []
    stderr_chunks: list[str] = []

    def _read_stream(stream, chunks):
        for line in stream:
            chunks.append(line)

    stdout_thread = threading.Thread(
        target=_read_stream, args=(proc.stdout, stdout_chunks), daemon=True
    )
    stderr_thread = threading.Thread(
        target=_read_stream, args=(proc.stderr, stderr_chunks), daemon=True
    )
    stdout_thread.start()
    stderr_thread.start()

    try:
        proc.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=10)
        stdout_thread.join(timeout=5)
        stderr_thread.join(timeout=5)
        return {
            "success": False,
            "exit_code": None,
            "stdout": _tail_lines("".join(stdout_chunks), tail_stdout),
            "stderr": f"Process timed out after {timeout_seconds // 60} minutes",
        }
    except Exception as e:
        proc.kill()
        return {"success": False, "exit_code": None, "stdout": "", "stderr": str(e)}

    stdout_thread.join(timeout=5)
    stderr_thread.join(timeout=5)

    return {
        "success": proc.returncode == 0,
        "exit_code": proc.returncode,
        "stdout": _tail_lines("".join(stdout_chunks), tail_stdout),
        "stderr": _tail_lines("".join(stderr_chunks), tail_stderr),
    }


# ---------------------------------------------------------------------------
# Tool: check_environment
# ---------------------------------------------------------------------------

@mcp.tool()
def check_environment() -> str:
    """Check Docker and ORFS environment status for ChipAgent Docker backend."""

    config = _read_docker_config()

    docker_installed = False
    docker_version = None
    try:
        proc = subprocess.run(
            ["docker", "--version"],
            capture_output=True, text=True, timeout=10,
        )
        if proc.returncode == 0:
            docker_installed = True
            docker_version = proc.stdout.strip()
    except Exception:
        pass

    image_exists = False
    try:
        proc = subprocess.run(
            ["docker", "image", "inspect", config.image],
            capture_output=True, text=True, timeout=10,
        )
        if proc.returncode == 0:
            image_exists = True
    except Exception:
        pass

    orfs_check = {}
    if image_exists:
        for key, test_cmd in [
            ("makefile", f"test -f {config.workdir}/Makefile && echo 'OK'"),
            ("sky130hd", f"test -d {config.workdir}/platforms/sky130hd && echo 'OK'"),
            ("sky130ram", f"test -d {config.workdir}/platforms/sky130ram && echo 'OK'"),
        ]:
            try:
                proc = subprocess.run(
                    ["docker", "run", "--rm", config.image, "bash", "-c", test_cmd],
                    capture_output=True, text=True, timeout=15,
                )
                orfs_check[key] = "OK" in proc.stdout
            except Exception:
                orfs_check[key] = False

    result = {
        "docker": {
            "installed": docker_installed,
            "version": docker_version,
            "image": config.image,
            "image_exists": image_exists,
            "workdir": config.workdir,
        },
        "orfs": orfs_check,
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
    """Generate ORFS config.mk and constraint.sdc on the host filesystem (Docker mode).

    Files are written to the host; Docker containers will access them via volume mounts.
    """

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
    design_name: str, verilog_abs: str, sdc_abs: str,
    core_utilization: float, place_density: float | None,
    gpl_timing_driven: bool | None, gpl_routability_driven: bool | None,
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
    design_name: str, verilog_content: str,
    clock_port: str, clock_period_ns: float,
) -> str:
    if _is_sequential(verilog_content):
        return "\n".join([
            f"current_design {design_name}",
            f"create_clock -name core_clock -period {clock_period_ns} [get_ports {clock_port}]",
            "set_input_delay -clock core_clock 0 [all_inputs -no_clocks]",
            "set_output_delay -clock core_clock 0 [all_outputs]",
            "",
        ])
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
    """Execute an ORFS make target via Docker (synth, floorplan, place, cts, route, finish).

    Runs inside openroad/orfs container with volume mounts for project root and design dirs.
    """

    config = _read_docker_config()
    design_nickname = _extract_design_nickname(config_mk_path)
    workspace_dir = str(PROJECT_ROOT)

    host_flow_dir = os.path.join(workspace_dir, "OpenROAD-flow-scripts", "flow")
    container_config_path = _container_path(config_mk_path)

    volumes: list[str] = []
    volumes.extend(["-v", f"{workspace_dir}:/workspace"])

    for host_sub, container_sub in [
        ("results", "results"), ("logs", "logs"),
        ("reports", "reports"), ("objects", "objects"),
    ]:
        host_path = os.path.join(host_flow_dir, host_sub, "sky130hd", design_nickname, "base")
        container_path = f"{config.workdir}/{container_sub}/sky130hd/{design_nickname}/base"
        _ensure_dir(host_path)
        volumes.extend(["-v", f"{host_path}:{container_path}"])

    # Conditional SRAM22 mount (prefer PROJECT_ROOT/sram22_sky130_macros)
    sram22_host = str(PROJECT_ROOT / "sram22_sky130_macros")
    if not os.path.isdir(sram22_host):
        sram22_host = os.path.join(orfs_flow_path, "platforms", "sky130ram", "sram22_sky130_macros")
    if os.path.isdir(sram22_host):
        volumes.extend(["-v", f"{sram22_host}:{config.workdir}/platforms/sky130ram/sram22_sky130_macros"])

    uid = os.getuid()
    gid = os.getgid()

    docker_args = [
        "docker", "run", "--rm",
        f"--user={uid}:{gid}",
        *volumes,
        "-w", config.workdir,
        config.image,
        "make", stage,
        f"DESIGN_CONFIG={container_config_path}",
    ]

    host_log_path = os.path.join(host_flow_dir, "logs", "sky130hd", design_nickname, "base")
    timeout_seconds = min(timeout_minutes, 120) * 60

    result = _run_docker_command(docker_args, timeout_seconds)
    result["stage"] = stage
    result["log_path"] = host_log_path

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
    """Extract stage-specific metrics from ORFS report files as structured JSON (Docker mode).

    Reads reports from host filesystem where Docker containers mounted their output.
    """

    results_base = str(PROJECT_ROOT / "OpenROAD-flow-scripts" / "flow")
    report_dir = Path(results_base) / "reports" / "sky130hd" / design_name / "base"
    log_dir = Path(results_base) / "logs" / "sky130hd" / design_name / "base"

    if not report_dir.exists():
        result = {
            "stage": stage,
            "error": f"Report not found. Run stage '{stage}' first.",
            "report_path": str(report_dir),
        }
        return json.dumps(result, indent=2)

    metrics: dict = {}
    for fname in STAGE_REPORT_MAP.get(stage, []):
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

    if stage == "finish":
        finish_log = log_dir / "6_report.log"
        if finish_log.exists():
            metrics.update(_parse_route_area(finish_log.read_text()))

    result = {"stage": stage, "metrics": metrics, "report_path": str(report_dir)}
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
    """Classify ORFS flow failure and suggest parameter adjustments for retry (Docker mode)."""

    finish_wns = None
    if finish_report_content:
        m = _parse_finish_report(finish_report_content)
        if "wns" in m:
            finish_wns = float(m["wns"])

    drc_violations = None
    if drc_report_content:
        drc_violations = _parse_drc_report(drc_report_content)["violations"]

    classification = _classify_error(stage, success, stderr, finish_wns, drc_violations, sdc_content)
    suggested = _suggest_params(
        classification["error_type"],
        current_clock_period_ns, current_place_density, current_core_utilization,
    )

    result = {**classification, "suggested_params": suggested}
    return json.dumps(result, indent=2)


def _classify_error(stage, success, stderr, finish_wns, drc_violations, sdc_content) -> dict:
    if stage == "synth" and not success:
        return {"error_type": "synthesis_error", "severity": "critical",
                "details": f"Synthesis failed: {stderr[:200]}", "restart_from": "synth"}

    if PLACEMENT_OVERFLOW_RE.search(stderr):
        return {"error_type": "placement_overflow", "severity": "recoverable",
                "details": "Placement overflow detected in stderr", "restart_from": "floorplan"}

    if CONGESTION_RE.search(stderr):
        return {"error_type": "congestion", "severity": "recoverable",
                "details": "Routing congestion detected in stderr", "restart_from": "place"}

    if drc_violations is not None and drc_violations > 0:
        return {"error_type": "drc", "severity": "recoverable",
                "details": f"{drc_violations} DRC violation(s) found", "restart_from": "place"}

    if finish_wns is not None and finish_wns < 0:
        is_comb = sdc_content and re.search(r"virtual_clk", sdc_content, re.IGNORECASE)
        return {"error_type": "timing_violation",
                "severity": "critical" if is_comb else "recoverable",
                "details": f"Timing violation: WNS = {finish_wns} ns", "restart_from": "synth"}

    return {"error_type": "unknown", "severity": "critical",
            "details": f"Unclassified failure at stage '{stage}': {stderr[:200]}",
            "restart_from": "synth"}


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
    """Reset ORFS cached artifacts for a design via docker run make clean_all."""

    config = _read_docker_config()
    workspace_dir = str(PROJECT_ROOT)
    container_config_path = _container_path(config_mk_path)

    uid = os.getuid()
    gid = os.getgid()

    docker_args = [
        "docker", "run", "--rm",
        f"--user={uid}:{gid}",
        "-v", f"{workspace_dir}:/workspace",
        "-w", config.workdir,
    ]

    # Conditional SRAM22 mount (prefer PROJECT_ROOT/sram22_sky130_macros)
    sram22_host = str(PROJECT_ROOT / "sram22_sky130_macros")
    if not os.path.isdir(sram22_host):
        sram22_host = os.path.join(orfs_flow_path, "platforms", "sky130ram", "sram22_sky130_macros")
    if os.path.isdir(sram22_host):
        docker_args.extend(["-v", f"{sram22_host}:{config.workdir}/platforms/sky130ram/sram22_sky130_macros"])

    docker_args.extend([
        config.image,
        "make", "clean_all",
        f"DESIGN_CONFIG={container_config_path}",
    ])

    result = _run_docker_command(docker_args, 30, tail_stdout=100, tail_stderr=100)
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
    """Save, load, recommend best, or clear PnR run QoR history (Docker mode)."""

    history_path = Path(workspace_dir).resolve() / "qor_history.json"

    if action == "save":
        if round is None or config is None or metrics is None or status is None:
            return json.dumps({"error": "round, config, metrics, status are required for save action"}, indent=2)
        entry = {"round": round, "config": config, "metrics": metrics, "status": status}
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
            f"Best run: round {best['round']} (clock={best['config'].get('clock_period_ns')}ns, "
            f"WNS={best['metrics'].get('wns')}ns, area={best['metrics'].get('area')}, "
            f"power={best['metrics'].get('total_power_w', 'N/A')}W)"
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
    passing = [
        r for r in history
        if r.get("status") == "pass"
        and r.get("metrics", {}).get("wns") is not None
        and r.get("metrics", {}).get("wns") >= 0
        and (r.get("metrics", {}).get("drc_violations", 0) or 0) == 0
    ]

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