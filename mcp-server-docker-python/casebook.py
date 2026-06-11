#!/usr/bin/env python3
"""Cross-design PnR experience casebook for ChipAgent Docker MCP server.

Persists per-design tuning trajectories (features, parameter rounds, best
config, outcome) and retrieves similar past cases so new designs can
warm-start from proven configurations instead of fixed conservative
baselines. All functions are pure: they take and return plain data and never
mutate their inputs.
"""

import json
import math
from pathlib import Path

CASEBOOK_FILENAME = "casebook.json"

# Similarity weights: platform mismatch is near-disqualifying; design scale
# (log cell count) matters most; clock target least.
WEIGHT_PLATFORM = 10.0
WEIGHT_SCALE = 3.0
WEIGHT_CLOCK = 1.0


def load_cases(casebook_path) -> list:
    """Read all cases from disk. Returns [] on missing or malformed file."""
    path = Path(casebook_path)
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, list) else []
    except Exception:
        return []


def save_case(cases: list, new_case: dict) -> list:
    """Return a new case list with new_case appended or replacing an existing
    entry for the same design+platform (latest trajectory wins)."""
    design = new_case.get("design")
    platform = new_case.get("platform")
    kept = [
        c for c in cases
        if not (c.get("design") == design and c.get("platform") == platform)
    ]
    return [*kept, new_case]


def write_cases(casebook_path, cases: list) -> None:
    path = Path(casebook_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cases, indent=2))


def _scale_distance(a, b) -> float:
    """Distance between two designs' cell counts on a log10 scale."""
    try:
        if not a or not b or a <= 0 or b <= 0:
            return 2.0  # unknown scale: penalize moderately
        return abs(math.log10(a) - math.log10(b))
    except Exception:
        return 2.0


def _clock_distance(a, b) -> float:
    """Relative clock-target difference, capped at 1."""
    try:
        if not a or not b or a <= 0 or b <= 0:
            return 1.0
        return min(abs(a - b) / max(a, b), 1.0)
    except Exception:
        return 1.0


def case_distance(features: dict, case: dict) -> float:
    """Lower is more similar."""
    case_features = case.get("features", {})
    platform_penalty = (
        0.0 if features.get("platform", "sky130hd") == case.get("platform", "sky130hd")
        else WEIGHT_PLATFORM
    )
    scale = _scale_distance(
        features.get("cell_count"), case_features.get("cell_count")
    )
    clock = _clock_distance(
        features.get("target_clock_ns"), case_features.get("target_clock_ns")
    )
    return platform_penalty + WEIGHT_SCALE * scale + WEIGHT_CLOCK * clock


def _summarize_case(case: dict, distance: float) -> dict:
    """Compact summary for the LLM: warm-start config + failure->fix history."""
    failure_fixes = [
        {
            "error_type": r.get("error_type"),
            "fix_applied": r.get("fix_applied"),
        }
        for r in case.get("rounds", [])
        if r.get("error_type")
    ]
    return {
        "design": case.get("design"),
        "platform": case.get("platform"),
        "features": case.get("features"),
        "outcome": case.get("outcome"),
        "best_config": case.get("best_config"),
        "rounds_used": len(case.get("rounds", [])),
        "failure_fixes": failure_fixes,
        "distance": round(distance, 3),
        "timestamp": case.get("timestamp"),
    }


def query_similar(features: dict, cases: list, top_k: int = 3) -> list:
    """Return up to top_k case summaries most similar to the given features,
    nearest first. Cases without a best_config are excluded (nothing to
    warm-start from)."""
    usable = [c for c in cases if c.get("best_config")]
    scored = sorted(
        ((case_distance(features, c), c) for c in usable),
        key=lambda pair: pair[0],
    )
    return [_summarize_case(c, d) for d, c in scored[:top_k]]
