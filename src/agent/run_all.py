# src/agent/run_all.py
from __future__ import annotations
from pathlib import Path
from ..synth_temporal import synth_cohort, CohortSpec
from .loop import run_once

def main():
    # 1) generate fresh cohort
    meta = synth_cohort(Path("data/bundles_temporal"), CohortSpec(n_patients=50))
    print(f"Generated {meta['n_files']} bundles.")

    # 2) run agent
    report = run_once()
    print(f"Report: {report}")

if __name__ == "__main__":
    main()
