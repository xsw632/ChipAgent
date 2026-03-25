#!/usr/bin/env python3
"""Lightweight VCD parser for ChipAgent debug analysis.

Parses Value Change Dump files using only Python stdlib.
Extracts signal values at specific timestamps for failure diagnosis.
"""

import argparse
import bisect
import json
import re
import sys


class VCDParser:
    """Single-pass VCD parser with suffix-based signal lookup."""

    def __init__(self, vcd_path):
        self.vcd_path = vcd_path
        self.header = {}
        self.signals = {}       # symbol -> {path: str, width: int}
        self.path_to_sym = {}   # full_path -> symbol
        self.transitions = {}   # symbol -> [(time, value), ...]
        self._parse()

    def _parse(self):
        with open(self.vcd_path, "r") as f:
            content = f.read()

        # Parse header fields
        for field in ("date", "version", "timescale"):
            match = re.search(
                rf"\${field}\s+(.*?)\s*\$end", content, re.DOTALL
            )
            if match:
                self.header[field] = match.group(1).strip()

        # Parse signal definitions
        scope_stack = []
        in_defs = True
        past_dumpvars = False
        current_time = 0

        for line in content.splitlines():
            line = line.strip()
            if not line:
                continue

            if in_defs:
                if line.startswith("$scope"):
                    parts = line.split()
                    # $scope module <name> $end
                    if len(parts) >= 3:
                        scope_stack.append(parts[2])
                elif line.startswith("$upscope"):
                    if scope_stack:
                        scope_stack.pop()
                elif line.startswith("$var"):
                    # $var wire <width> <symbol> <name> $end
                    parts = line.split()
                    if len(parts) >= 5:
                        width = int(parts[2])
                        symbol = parts[3]
                        name = parts[4]
                        full_path = ".".join(scope_stack + [name])
                        self.signals[symbol] = {
                            "path": full_path,
                            "width": width,
                        }
                        self.path_to_sym[full_path] = symbol
                        self.transitions[symbol] = []
                elif line.startswith("$enddefinitions"):
                    in_defs = False
                continue

            # Value change section
            if line.startswith("$dumpvars"):
                past_dumpvars = True
                continue
            if line == "$end":
                continue

            if line.startswith("#"):
                current_time = int(line[1:])
                continue

            # Parse value changes
            if line.startswith("b") or line.startswith("B"):
                parts = line.split()
                if len(parts) == 2:
                    value = parts[0][1:]  # strip 'b'/'B'
                    symbol = parts[1]
                    if symbol in self.transitions:
                        self.transitions[symbol].append(
                            (current_time, value)
                        )
            elif len(line) >= 2 and line[0] in "01xXzZ":
                value = line[0]
                symbol = line[1:]
                if symbol in self.transitions:
                    self.transitions[symbol].append((current_time, value))

    def _find_symbol(self, signal_path):
        """Find symbol by suffix match on signal path."""
        signal_lower = signal_path.lower()
        # Exact match first
        if signal_path in self.path_to_sym:
            return self.path_to_sym[signal_path]
        # Suffix match
        candidates = []
        for path, sym in self.path_to_sym.items():
            if path.lower().endswith(signal_lower):
                candidates.append((path, sym))
        if len(candidates) == 1:
            return candidates[0][1]
        if len(candidates) > 1:
            # Prefer shortest path (most specific match)
            candidates.sort(key=lambda x: len(x[0]))
            return candidates[0][1]
        return None

    def get_value_at_time(self, signal_path, timestamp):
        """Get signal value at or before the given timestamp."""
        symbol = self._find_symbol(signal_path)
        if symbol is None:
            return None
        trans = self.transitions.get(symbol, [])
        if not trans:
            return None
        # Binary search for most recent change <= timestamp
        times = [t[0] for t in trans]
        idx = bisect.bisect_right(times, timestamp) - 1
        if idx < 0:
            return None
        return trans[idx][1]

    def get_signals_at_time(self, signal_paths, timestamp):
        """Get multiple signal values at a timestamp."""
        result = {}
        for sig in signal_paths:
            result[sig] = self.get_value_at_time(sig, timestamp)
        return result

    def list_signals(self):
        """Return all signal full paths."""
        return sorted(self.path_to_sym.keys())

    def search_signals(self, keyword):
        """Return signal paths where keyword appears as suffix (case-insensitive)."""
        keyword_lower = keyword.lower()
        return [
            path
            for path in self.path_to_sym
            if path.lower().endswith(keyword_lower)
        ]


def main():
    parser = argparse.ArgumentParser(
        description="Parse VCD files and extract signal values at timestamps."
    )
    parser.add_argument(
        "--vcd", required=True, help="Path to VCD file"
    )
    parser.add_argument(
        "--signals", nargs="+", help="Signal names to query (suffix match)"
    )
    parser.add_argument(
        "--time", nargs="+", type=int, help="Timestamps to query"
    )
    parser.add_argument(
        "--list-signals",
        action="store_true",
        help="List all signals in the VCD file",
    )
    args = parser.parse_args()

    try:
        vcd = VCDParser(args.vcd)
    except FileNotFoundError:
        print(
            json.dumps({"error": f"VCD file not found: {args.vcd}"}),
            file=sys.stderr,
        )
        sys.exit(1)
    except Exception as e:
        print(
            json.dumps({"error": f"Failed to parse VCD: {str(e)}"}),
            file=sys.stderr,
        )
        sys.exit(1)

    if args.list_signals:
        print(json.dumps({"signals": vcd.list_signals()}, indent=2))
        return

    if args.signals and args.time:
        result = {}
        for t in args.time:
            result[str(t)] = vcd.get_signals_at_time(args.signals, t)
        print(json.dumps(result, indent=2))
        return

    parser.print_help()


if __name__ == "__main__":
    main()
