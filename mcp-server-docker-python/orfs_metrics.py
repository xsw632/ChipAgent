#!/usr/bin/env python3
"""ORFS artifact parsers for ChipAgent Docker MCP server.

Pure functions that parse ORFS stage JSON metrics, GRT congestion tables,
and STA critical-path reports into normalized signal dicts. All parsers
degrade softly: malformed or missing input yields None values or empty
dicts, never exceptions.
"""

import json
import re
from pathlib import Path

# Stage -> ordered list of ORFS log JSON files. Later files override earlier
# ones when merged, so the most refined sub-stage wins (e.g. place_dp > gp).
STAGE_JSON_MAP = {
    "synth": ["1_synth.json"],
    "floorplan": [
        "2_1_floorplan.json",
        "2_2_floorplan_macro.json",
        "2_3_floorplan_tapcell.json",
        "2_4_floorplan_pdn.json",
    ],
    "place": [
        "3_3_place_gp.json",
        "3_4_place_resized.json",
        "3_5_place_dp.json",
    ],
    "cts": ["4_1_cts.json"],
    "route": ["5_1_grt.json", "5_2_route.json"],
    "finish": ["6_report.json"],
}

# Normalized signal name -> suffix of the ORFS metric key (after the stage
# prefix is stripped). First match in merge order wins per file; across
# files, later files override.
SIGNAL_KEY_MAP = {
    "setup_ws": "timing__setup__ws",
    "setup_tns": "timing__setup__tns",
    "hold_ws": "timing__hold__ws",
    "hold_tns": "timing__hold__tns",
    "fmax_hz": "timing__fmax",
    "clock_skew_setup": "clock__skew__setup",
    "clock_skew_hold": "clock__skew__hold",
    "utilization": "design__instance__utilization",
    "instance_count": "design__instance__count",
    "instance_area": "design__instance__area",
    "stdcell_area": "design__instance__area__stdcell",
    "die_area": "design__die__area",
    "core_area": "design__core__area",
    "macro_count": "design__instance__count__macros",
    "setup_buffer_count": "design__instance__count__setup_buffer",
    "hold_buffer_count": "design__instance__count__hold_buffer",
    "repair_buffer_count": "design__instance__count__class:timing_repair_buffer",
    "max_slew_violations": "timing__drv__max_slew",
    "max_cap_violations": "timing__drv__max_cap",
    "setup_violation_count": "timing__drv__setup_violation_count",
    "hold_violation_count": "timing__drv__hold_violation_count",
    "drc_errors": "route__drc_errors",
    "wirelength": "route__wirelength",
    "wirelength_estimated": "route__wirelength__estimated",
    "vias": "route__vias",
    "displacement_max": "design__instance__displacement__max",
    "power_total_w": "power__total",
    "warnings_count": "flow__warnings__count",
    "errors_count": "flow__errors__count",
}


def _strip_stage_prefix(key: str) -> str:
    """'globalplace__timing__setup__ws' -> 'timing__setup__ws'."""
    parts = key.split("__", 1)
    return parts[1] if len(parts) == 2 else key


def parse_stage_json(path) -> dict:
    """Read one ORFS stage metrics JSON, return {stripped_key: value}.

    Returns an empty dict on any read/parse failure.
    """
    try:
        raw = json.loads(Path(path).read_text())
    except Exception:
        return {}
    if not isinstance(raw, dict):
        return {}
    return {_strip_stage_prefix(k): v for k, v in raw.items()}


def merge_stage_jsons(log_dir, stage: str) -> tuple[dict, list[str]]:
    """Merge all JSON files for a stage. Returns (merged, missing_files)."""
    merged: dict = {}
    missing: list[str] = []
    for fname in STAGE_JSON_MAP.get(stage, []):
        fpath = Path(log_dir) / fname
        if not fpath.exists():
            missing.append(fname)
            continue
        merged = {**merged, **parse_stage_json(fpath)}
    return merged, missing


def extract_signals(merged: dict) -> dict:
    """Map merged ORFS metrics to normalized signal names."""
    signals = {name: merged.get(suffix) for name, suffix in SIGNAL_KEY_MAP.items()}

    # Derived: fmax in MHz for readability
    fmax_hz = signals.pop("fmax_hz", None)
    signals["fmax_mhz"] = round(fmax_hz / 1e6, 2) if isinstance(fmax_hz, (int, float)) else None

    # Per-iteration detailed-route DRC trend (e.g. route__drc_errors__iter:3)
    iters = {}
    for key, value in merged.items():
        m = re.match(r"route__drc_errors__iter:(\d+)$", key)
        if m:
            iters[int(m.group(1))] = value
    signals["drc_errors_by_iter"] = (
        [iters[i] for i in sorted(iters)] if iters else None
    )
    return signals


# ---------------------------------------------------------------------------
# GRT congestion table (GRT-0096 in 5_1_grt.log)
# ---------------------------------------------------------------------------

# Example row:
# met1               709           252           35.54%             0 /  0 /  0
_CONGESTION_ROW_RE = re.compile(
    r"^(\w+)\s+(\d+)\s+(\d+)\s+([\d.]+)%\s+(\d+)\s*/\s*(\d+)\s*/\s*(\d+)\s*$"
)

HOTSPOT_USAGE_PCT = 80.0


def parse_grt_congestion(log_text: str) -> dict:
    """Parse the GRT-0096 final congestion report from a GRT log.

    Returns {layers: {name: {resource, demand, usage_pct, max_h, max_v,
    overflow}}, total_overflow, hotspot_layers}. Empty layers dict when the
    table is absent.
    """
    layers: dict = {}
    in_table = False
    for line in log_text.split("\n"):
        if "GRT-0096" in line:
            in_table = True
            continue
        if not in_table:
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith(("Layer", "---")):
            if layers and not stripped:
                break  # blank line after rows ends the table
            continue
        m = _CONGESTION_ROW_RE.match(stripped)
        if not m:
            if layers:
                break  # non-row line after rows ends the table
            continue
        name, resource, demand, usage, max_h, max_v, overflow = m.groups()
        if name.lower() == "total":
            continue  # summary row, not a layer
        layers[name] = {
            "resource": int(resource),
            "demand": int(demand),
            "usage_pct": float(usage),
            "max_h": int(max_h),
            "max_v": int(max_v),
            "overflow": int(overflow),
        }

    total_overflow = sum(l["overflow"] for l in layers.values())
    hotspot_layers = [
        name for name, l in layers.items()
        if l["usage_pct"] >= HOTSPOT_USAGE_PCT or l["overflow"] > 0
    ]
    return {
        "layers": layers,
        "total_overflow": total_overflow,
        "hotspot_layers": hotspot_layers,
    }


# ---------------------------------------------------------------------------
# Critical path breakdown (report_checks -path_delay max in 6_finish.rpt)
# ---------------------------------------------------------------------------

_PATH_SECTION_RE = re.compile(
    r"report_checks -path_delay max\n-+\n(.*?)(?:\n=====|\Z)", re.DOTALL
)
_STARTPOINT_RE = re.compile(r"Startpoint:\s*(\S+)")
_ENDPOINT_RE = re.compile(r"Endpoint:\s*(\S+)")
_SLACK_RE = re.compile(r"(-?[\d.]+)\s+slack\s+\((MET|VIOLATED)\)")
# Path table rows ("Fanout Cap Slew Delay Time ^/v pin (cell)"):
# - input-pin rows have 3 numbers (Slew Delay Time); Delay = net/wire delay
# - output-pin rows have 5 numbers (all columns); Delay = cell arc delay
_PATH_ROW_RE = re.compile(
    r"^\s*((?:-?[\d.]+\s+)+)[v^]\s+(\S+)\s+\((\S+)\)\s*$"
)


def parse_critical_path(report_text: str) -> dict:
    """Parse the worst setup path from a finish report.

    Returns {startpoint, endpoint, slack, met, stage_count, cell_delay_ns,
    net_delay_ns, wire_delay_pct}. Values are None when the section or
    fields are absent.
    """
    empty = {
        "startpoint": None, "endpoint": None, "slack": None, "met": None,
        "stage_count": None, "cell_delay_ns": None, "net_delay_ns": None,
        "wire_delay_pct": None,
    }
    section_match = _PATH_SECTION_RE.search(report_text)
    if not section_match:
        return empty
    section = section_match.group(1)

    start = _STARTPOINT_RE.search(section)
    end = _ENDPOINT_RE.search(section)
    slack = _SLACK_RE.search(section)

    cell_delay = 0.0
    net_delay = 0.0
    stage_count = 0
    for line in section.split("\n"):
        m = _PATH_ROW_RE.match(line)
        if not m:
            continue
        numbers = m.group(1).split()
        cell = m.group(3)
        if cell in ("in", "out", "net") or len(numbers) < 2:
            continue
        delay_val = float(numbers[-2])  # Delay is second-to-last column
        if len(numbers) >= 5:
            # Output-pin row (Fanout Cap Slew Delay Time): cell arc delay
            cell_delay += delay_val
            stage_count += 1
        else:
            # Input-pin row (Slew Delay Time): wire/net delay
            net_delay += delay_val

    total = cell_delay + net_delay
    return {
        "startpoint": start.group(1) if start else None,
        "endpoint": end.group(1) if end else None,
        "slack": float(slack.group(1)) if slack else None,
        "met": (slack.group(2) == "MET") if slack else None,
        "stage_count": stage_count if stage_count else None,
        "cell_delay_ns": round(cell_delay, 3) if total else None,
        "net_delay_ns": round(net_delay, 3) if total else None,
        "wire_delay_pct": round(net_delay / total * 100, 1) if total else None,
    }


# ---------------------------------------------------------------------------
# Top-level entry: collect everything for a stage
# ---------------------------------------------------------------------------

def collect_stage_metrics(log_dir, report_dir, stage: str) -> dict:
    """Gather normalized signals plus stage-specific extras.

    log_dir/report_dir are host paths to ORFS logs/ and reports/ base dirs.
    """
    merged, missing = merge_stage_jsons(log_dir, stage)
    result = {
        "stage": stage,
        "signals": extract_signals(merged) if merged else {},
        "missing_files": missing,
    }

    if stage == "route":
        grt_log = Path(log_dir) / "5_1_grt.log"
        if grt_log.exists():
            try:
                result["congestion"] = parse_grt_congestion(grt_log.read_text())
            except Exception:
                result["congestion"] = {"layers": {}, "total_overflow": None, "hotspot_layers": []}
        else:
            result["missing_files"] = [*missing, "5_1_grt.log"]

    if stage == "finish":
        finish_rpt = Path(report_dir) / "6_finish.rpt"
        if finish_rpt.exists():
            try:
                result["critical_path"] = parse_critical_path(finish_rpt.read_text())
            except Exception:
                result["critical_path"] = None
        else:
            result["missing_files"] = [*missing, "6_finish.rpt"]

    return result
