# src/agent/loop.py
from __future__ import annotations
from pathlib import Path
from typing import List
import json
from datetime import datetime, timezone

from ..temporal_graph import load_bundle, extract_events, annotate_labels, path_exists_within
from ..rules import Thresholds
from ..tools.report_tool import write_markdown

def _list_bundles(root: Path) -> List[Path]:
    return sorted([p for p in root.glob("*.json") if p.is_file()])

def run_once(
    bundles_dir: Path = Path("data/bundles_temporal"),
    out_dir: Path = Path("out/agent_reports"),
    state_path: Path = Path("out/agent_state.json"),
    thresholds: Thresholds = Thresholds()
) -> Path:
    bundles = _list_bundles(bundles_dir)
    if not bundles:
        raise SystemExit(f"No bundles found in {bundles_dir}")

    findings = []  # per-patient pattern hits
    delta_hours = []

    for bp in bundles:
        b = load_bundle(bp)
        evs = extract_events(b)
        annotate_labels(evs, thresholds)
        dt = path_exists_within(evs, "Fever", "Tachycardia", thresholds.fever_to_tachy_hours)
        if dt is not None:
            findings.append((bp.name, "Fever→Tachycardia"))
            delta_hours.append(dt)

    support = len(findings)
    median_dt = None
    if delta_hours:
        s = sorted(delta_hours)
        mid = len(s)//2
        median_dt = s[mid] if len(s)%2==1 else (s[mid-1]+s[mid])/2

    # Compare with previous state
    prev_support = None
    state_path.parent.mkdir(parents=True, exist_ok=True)
    if state_path.exists():
        prev = json.loads(state_path.read_text(encoding="utf-8"))
        prev_support = prev.get("fever_to_tachy_support")

    # Save new state
    state_path.write_text(json.dumps({
        "ts": datetime.now(timezone.utc).isoformat(),
        "fever_to_tachy_support": support,
        "median_dt_hours": median_dt
    }, indent=2), encoding="utf-8")

    # Prepare report markdown
    lines = []
    lines.append(f"**Pattern:** Fever → Tachycardia within **{thresholds.fever_to_tachy_hours}h**")
    lines.append(f"- **Support (patients matching):** {support}")
    if prev_support is not None:
        change = support - prev_support
        emoji = "⬆️" if change>0 else ("⬇️" if change<0 else "➖")
        lines.append(f"- **Change vs last run:** {emoji} {change:+d}")
    if median_dt is not None:
        lines.append(f"- **Median Δt:** {median_dt:.2f} hours")
    if findings:
        lines.append("\n**Matching patients:**")
        for name, _ in findings[:20]:
            lines.append(f"- {name}")
        if len(findings) > 20:
            lines.append(f"- … and {len(findings)-20} more")

    body = "\n".join(lines)
    report_path = out_dir / "agent_report.md"
    write_markdown(report_path, "Agent Report — Temporal Patterns", body)
    return report_path
