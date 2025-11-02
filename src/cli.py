# src/cli.py
from __future__ import annotations
import argparse
from pathlib import Path
from .agent.loop import run_once
from .rules import Thresholds

def main():
    ap = argparse.ArgumentParser(description="Agentic Temporal Health Assistant")
    ap.add_argument("--bundles", default="data/bundles_temporal")
    ap.add_argument("--out", default="out/agent_reports")
    ap.add_argument("--state", default="out/agent_state.json")
    ap.add_argument("--fever_to_tachy_hours", type=float, default=6.0)
    args = ap.parse_args()

    thr = Thresholds(fever_to_tachy_hours=args.fever_to_tachy_hours)
    path = run_once(Path(args.bundles), Path(args.out), Path(args.state), thr)
    print(f"✅ Wrote report: {path}")

if __name__ == "__main__":
    main()
