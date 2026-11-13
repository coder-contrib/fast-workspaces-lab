#!/usr/bin/env python3
"""Recompute the five ready-time values from the redacted Coder traces."""

import csv
from datetime import datetime
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parent.parent


def instant(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def duration(data):
    scripts = {}
    for row in data["agent_script_timings"]:
        key = row["workspace_agent_id"], row["display_name"]
        if key not in scripts or instant(row["started_at"]) > instant(scripts[key]["started_at"]):
            scripts[key] = row
        if row["status"] != "ok":
            raise ValueError(f"Startup script failed: {row['display_name']}")

    rows = data["provisioner_timings"] + data["agent_connection_timings"] + list(scripts.values())
    if not rows or not data["agent_connection_timings"] or not scripts:
        raise ValueError("The trace has no complete agent timeline")
    start = min(instant(row["started_at"]) for row in rows)
    end = max(instant(row["ended_at"]) for row in rows)
    return round((end - start).total_seconds(), 3)


def main():
    with (ROOT / "data/traces-manifest.csv").open(newline="") as file:
        manifest = list(csv.DictReader(file))
    with (ROOT / "data/speeds.csv").open(newline="") as file:
        reported = list(csv.DictReader(file))

    by_step = {}
    for row in manifest:
        data = json.loads((ROOT / "traces" / row["file"]).read_text())
        seconds = duration(data)
        by_step.setdefault(int(row["step"]), []).append(seconds)
        print(f"Step {row['step']} {row['variant']} {row['file']}: {seconds:.3f} s")

    if len(reported) != 5 or set(by_step) != set(range(1, 6)):
        raise ValueError("The packet needs five steps")
    for row in reported:
        step = int(row["step"])
        values = by_step[step]
        measured = round(statistics.median(values), 3)
        expected = float(row["ui_timeline_s"])
        if len(values) != int(row["samples"]) or abs(measured - expected) > 0.005:
            raise ValueError(f"Step {step}: measured {measured} s, published {expected} s")
        print(f"Step {step} median: {measured:.3f} s")


if __name__ == "__main__":
    main()
