# src/cli.py
from __future__ import annotations
from pathlib import Path
from datetime import datetime
import json

from .temporal_engine import load_thresholds, cohort_support, plot_patient_timeline

def main():
    import argparse
    ap = argparse.ArgumentParser(description="Temporal pattern mining & reporting")
    ap.add_argument("--cohort", default="data/bundles_temporal")
    ap.add_argument("--outdir", default="out")
    args = ap.parse_args()

    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)

    thr = load_thresholds()
    stats = cohort_support(Path(args.cohort), thr)

    # Write JSON summary
    (out / "temporal_stats.json").write_text(json.dumps(stats, indent=2), encoding="utf-8")

    # Make quick patient timelines
    plot_patient_timeline(Path(args.cohort), out / "timelines", thr, max_plots=12)

    # Markdown report
    md = []
    md.append(f"# Agent Report — Temporal Clinical Patterns\n")
    md.append(f"_Generated: {datetime.utcnow().isoformat(timespec='seconds')}Z_\n")
    md.append("## Rules\n")
    md.append(f"- Fever → Tachycardia within **{thr['rules']['fever_to_tachy_hours_max']}h**")
    md.append(f"- Tachycardia → Low SpO₂ within **{thr['rules']['tachy_to_lowspo2_hours_max']}h**\n")

    def line(k, label):
        sup = stats[k]["support"]
        med = stats[k]["dt_median"]
        ex  = stats[k]["examples"][:5]
        mtxt = f"{med}h" if med is not None else "—"
        return f"- **{label}** — support: **{sup}**, median Δt: **{mtxt}**, examples: {ex}"

    md.append("## Results\n")
    md.append(line("fever_to_tachy", "Fever → Tachy"))
    md.append(line("tachy_to_lowspo2", "Tachy → Low SpO₂"))

    md.append("\n## Artifacts\n")
    md.append("- `out/temporal_stats.json`")
    md.append("- `out/timelines/*.png` (sample patient timelines)\n")

    report_path = out / "agent_report.md"
    report_path.write_text("\n".join(md) + "\n", encoding="utf-8")
    print(f"✅ Wrote report: {report_path}")

if __name__ == "__main__":
    main()
