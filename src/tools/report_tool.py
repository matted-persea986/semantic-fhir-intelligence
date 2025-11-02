# src/tools/report_tool.py
from __future__ import annotations
from pathlib import Path
from datetime import datetime, timezone

def write_markdown(report_path: Path, title: str, body_md: str) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    md = f"# {title}\n\n_Generated: {now}_\n\n{body_md}\n"
    report_path.write_text(md, encoding="utf-8")
