# src/temporal_graph.py
from __future__ import annotations
from dataclasses import dataclass
from typing import List, Dict, Any, Optional, Tuple
from pathlib import Path
from datetime import datetime, timezone
import json

from .rules import Thresholds, is_fever, is_tachy, is_low_spo2, LOINC_TEMP, LOINC_HR, LOINC_SPO2

def _parse_iso(ts: str) -> datetime:
    # robust ISO parser for Z timestamps
    return datetime.fromisoformat(ts.replace("Z","+00:00")).astimezone(timezone.utc)

@dataclass
class Event:
    patient: str
    time: datetime
    code_sys: str
    code: str
    value: Optional[float]
    unit: Optional[str]
    label: Optional[str] = None  # e.g., Fever/Tachy/LowSpO2

def load_bundle(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))

def extract_events(bundle: Dict[str, Any]) -> List[Event]:
    # patient id
    p_id = None
    for e in bundle.get("entry", []):
        r = e.get("resource", {})
        if r.get("resourceType") == "Patient":
            p_id = r.get("id")
            break
    if not p_id:
        p_id = "unknown"

    events: List[Event] = []
    for e in bundle.get("entry", []):
        r = e.get("resource", {})
        if r.get("resourceType") != "Observation":
            continue
        subj = r.get("subject", {}).get("reference", "")
        if not subj.endswith(p_id):
            # ignore cross-patient refs in this mini-demo
            pass
        code_list = r.get("code", {}).get("coding", [])
        if not code_list: 
            continue
        c = code_list[0]
        code_sys = c.get("system","")
        code = c.get("code","")
        ts = r.get("effectiveDateTime")
        if not ts:
            continue  # temporal graph needs time
        t = _parse_iso(ts)

        val = None
        unit = None
        if "valueQuantity" in r:
            vq = r["valueQuantity"]
            val = float(vq.get("value")) if vq.get("value") is not None else None
            unit = vq.get("unit")

        events.append(Event(patient=p_id, time=t, code_sys=code_sys, code=code, value=val, unit=unit))
    # sort by time
    events.sort(key=lambda e: e.time)
    return events

def annotate_labels(events: List[Event], thr: Thresholds) -> None:
    for ev in events:
        if is_fever(ev.code_sys, ev.code, ev.value, ev.unit, thr):
            ev.label = "Fever"
        elif is_tachy(ev.code_sys, ev.code, ev.value, ev.unit, thr):
            ev.label = "Tachycardia"
        elif is_low_spo2(ev.code_sys, ev.code, ev.value, ev.unit, thr):
            ev.label = "LowSpO2"

def path_exists_within(events: List[Event], a: str, b: str, max_hours: float) -> Optional[float]:
    """
    Return delta-hours if there exists a labeled event a followed by b within max_hours.
    Otherwise None.
    """
    from math import inf
    best = inf
    for i, e1 in enumerate(events):
        if e1.label != a:
            continue
        for j in range(i+1, len(events)):
            e2 = events[j]
            if e2.label != b:
                continue
            dt = (e2.time - e1.time).total_seconds() / 3600.0
            if 0 <= dt <= max_hours:
                best = min(best, dt)
                break
    return None if best == float("inf") else best
