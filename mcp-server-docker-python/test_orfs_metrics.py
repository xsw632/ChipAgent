#!/usr/bin/env python3
"""Tests for orfs_metrics parsers. Run: python3 test_orfs_metrics.py

Uses embedded fixtures; additionally validates against real ALU8 artifacts
under MyDesign/ when present.
"""

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from orfs_metrics import (
    STAGE_JSON_MAP,
    collect_stage_metrics,
    extract_signals,
    merge_stage_jsons,
    parse_critical_path,
    parse_grt_congestion,
    parse_stage_json,
)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ALU8_BASE = PROJECT_ROOT / "MyDesign" / "ALU8" / "workspace" / "pnr"
ALU8_LOGS = ALU8_BASE / "logs" / "sky130hd" / "ALU8" / "base"
ALU8_REPORTS = ALU8_BASE / "reports" / "sky130hd" / "ALU8" / "base"

PASS = 0
FAIL = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS {name}")
    else:
        FAIL += 1
        print(f"  FAIL {name} {detail}")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

GRT_LOG_FIXTURE = """\
[INFO GRT-0096] Final congestion report:
Layer         Resource        Demand        Usage (%)    Max H / Max V / Total Overflow
---------------------------------------------------------------------------------------
li1                  0             0            0.00%             0 /  0 /  0
met1               709           652           91.96%             2 /  1 /  5
met2               616           214           34.74%             0 /  0 /  0
met3               452             2            0.44%             0 /  0 /  0

[INFO GRT-0101] Running extra iterations to remove overflow.
"""

FINISH_RPT_FIXTURE = """\
==========================================================================
finish report_checks -path_delay max
--------------------------------------------------------------------------
Startpoint: io_a[0] (input port clocked by core_clock)
Endpoint: io_z (output port clocked by core_clock)
Path Group: core_clock
Path Type: max

Fanout     Cap    Slew   Delay    Time   Description
-----------------------------------------------------------------------------
                          0.00    0.00 ^ input external delay
     1    0.00    0.00    0.00    0.00 ^ io_a[0] (in)
                                         io_a[0] (net)
                  0.00    0.10    0.10 ^ buf1/A (sky130_fd_sc_hd__buf_1)
     3    0.01    0.10    0.50    0.60 ^ buf1/X (sky130_fd_sc_hd__buf_1)
                                         n1 (net)
                  0.12    0.30    0.90 ^ and2/B (sky130_fd_sc_hd__and2_1)
     1    0.01    0.12    0.20    1.10 ^ and2/X (sky130_fd_sc_hd__and2_1)
                                         io_z (net)
                  0.03    0.00    1.10 ^ io_z (out)
                                  1.10   data arrival time

                                 10.00   data required time
-----------------------------------------------------------------------------
                                 10.00   data required time
                                 -1.10   data arrival time
-----------------------------------------------------------------------------
                                  8.90   slack (MET)


==========================================================================
finish report_checks -unconstrained
--------------------------------------------------------------------------
"""

STAGE_JSON_FIXTURE = {
    "globalplace__timing__setup__ws": -1.5,
    "globalplace__timing__setup__tns": -42.0,
    "globalplace__timing__hold__ws": 0.2,
    "globalplace__timing__fmax": 2.5e08,
    "globalplace__design__instance__utilization": 0.71,
    "globalplace__design__instance__count": 1234,
    "globalplace__flow__warnings__count": 3,
    "globalplace__flow__errors__count": 0,
}

ROUTE_JSON_FIXTURE = {
    "detailedroute__route__drc_errors__iter:0": 40,
    "detailedroute__route__drc_errors__iter:1": 12,
    "detailedroute__route__drc_errors__iter:2": 0,
    "detailedroute__route__drc_errors": 0,
    "detailedroute__route__wirelength": 3454,
    "detailedroute__route__vias": 1379,
}


# ---------------------------------------------------------------------------
# Fixture tests
# ---------------------------------------------------------------------------

def test_grt_congestion() -> None:
    print("parse_grt_congestion:")
    result = parse_grt_congestion(GRT_LOG_FIXTURE)
    check("4 layers parsed", len(result["layers"]) == 4, str(result["layers"].keys()))
    check("met1 usage", result["layers"].get("met1", {}).get("usage_pct") == 91.96)
    check("met1 overflow", result["layers"].get("met1", {}).get("overflow") == 5)
    check("total_overflow", result["total_overflow"] == 5)
    check("hotspot is met1", result["hotspot_layers"] == ["met1"], str(result["hotspot_layers"]))
    empty = parse_grt_congestion("no table here")
    check("no table -> empty layers", empty["layers"] == {} and empty["total_overflow"] == 0)


def test_critical_path() -> None:
    print("parse_critical_path:")
    result = parse_critical_path(FINISH_RPT_FIXTURE)
    check("startpoint", result["startpoint"] == "io_a[0]", str(result))
    check("endpoint", result["endpoint"] == "io_z")
    check("slack", result["slack"] == 8.90)
    check("met", result["met"] is True)
    check("stage_count", result["stage_count"] == 2, str(result["stage_count"]))
    # cell: 0.50 + 0.20 = 0.70; net: 0.10 + 0.30 + 0.00(out row skipped? no: io_z is (out), skipped) = 0.40
    check("cell_delay", result["cell_delay_ns"] == 0.70, str(result["cell_delay_ns"]))
    check("net_delay", result["net_delay_ns"] == 0.40, str(result["net_delay_ns"]))
    check("wire_delay_pct", result["wire_delay_pct"] == 36.4, str(result["wire_delay_pct"]))
    empty = parse_critical_path("nothing")
    check("missing section -> None slack", empty["slack"] is None)


def test_stage_json_and_signals() -> None:
    print("parse_stage_json / extract_signals:")
    with tempfile.TemporaryDirectory() as td:
        gp = Path(td) / "3_3_place_gp.json"
        gp.write_text(json.dumps(STAGE_JSON_FIXTURE))
        parsed = parse_stage_json(gp)
        check("prefix stripped", "timing__setup__ws" in parsed)
        signals = extract_signals(parsed)
        check("setup_ws", signals["setup_ws"] == -1.5)
        check("setup_tns", signals["setup_tns"] == -42.0)
        check("fmax_mhz", signals["fmax_mhz"] == 250.0, str(signals["fmax_mhz"]))
        check("utilization", signals["utilization"] == 0.71)
        check("warnings_count", signals["warnings_count"] == 3)

        # route iter trend
        route_signals = extract_signals(
            {k.split("__", 1)[1]: v for k, v in ROUTE_JSON_FIXTURE.items()}
        )
        check("drc_errors_by_iter", route_signals["drc_errors_by_iter"] == [40, 12, 0],
              str(route_signals["drc_errors_by_iter"]))
        check("drc_errors final", route_signals["drc_errors"] == 0)

    check("bad file -> empty", parse_stage_json("/nonexistent/x.json") == {})


def test_merge_missing() -> None:
    print("merge_stage_jsons:")
    with tempfile.TemporaryDirectory() as td:
        merged, missing = merge_stage_jsons(td, "place")
        check("all missing listed", missing == STAGE_JSON_MAP["place"], str(missing))
        check("merged empty", merged == {})


# ---------------------------------------------------------------------------
# Real-artifact tests (only when ALU8 outputs exist)
# ---------------------------------------------------------------------------

def test_real_alu8() -> None:
    if not ALU8_LOGS.exists():
        print("ALU8 artifacts not found — skipping real-artifact tests")
        return
    print("real ALU8 artifacts:")

    place = collect_stage_metrics(ALU8_LOGS, ALU8_REPORTS, "place")
    check("place setup_ws present", isinstance(place["signals"].get("setup_ws"), (int, float)),
          str(place["signals"].get("setup_ws")))
    check("place utilization present", place["signals"].get("utilization") is not None)

    route = collect_stage_metrics(ALU8_LOGS, ALU8_REPORTS, "route")
    check("route drc_errors == 0", route["signals"].get("drc_errors") == 0,
          str(route["signals"].get("drc_errors")))
    check("route drc trend ends 0", (route["signals"].get("drc_errors_by_iter") or [None])[-1] == 0,
          str(route["signals"].get("drc_errors_by_iter")))
    check("congestion layers parsed", len(route.get("congestion", {}).get("layers", {})) >= 5,
          str(route.get("congestion", {}).get("layers", {}).keys()))
    check("no overflow", route["congestion"]["total_overflow"] == 0)

    finish = collect_stage_metrics(ALU8_LOGS, ALU8_REPORTS, "finish")
    check("finish setup_ws ~7.0", abs((finish["signals"].get("setup_ws") or 0) - 6.99594) < 0.01,
          str(finish["signals"].get("setup_ws")))
    check("repair_buffer_count == 29", finish["signals"].get("repair_buffer_count") == 29,
          str(finish["signals"].get("repair_buffer_count")))
    cp = finish.get("critical_path") or {}
    check("critical path slack 7.0", cp.get("slack") == 7.00, str(cp.get("slack")))
    check("critical path met", cp.get("met") is True)
    check("wire_delay_pct computed", isinstance(cp.get("wire_delay_pct"), float), str(cp))

    cts = collect_stage_metrics(ALU8_LOGS, ALU8_REPORTS, "cts")
    check("cts hold_violation_count == 0", cts["signals"].get("hold_violation_count") == 0)


def main() -> int:
    test_grt_congestion()
    test_critical_path()
    test_stage_json_and_signals()
    test_merge_missing()
    test_real_alu8()
    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
