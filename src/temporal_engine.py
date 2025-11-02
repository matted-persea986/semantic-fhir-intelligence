# src/temporal_engine.py
from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple, Any
from datetime import datetime, timezone
import json, statistics, math, yaml
import matplotlib.pyplot as plt

# LOINC
L_TEMP = ("http://loinc.org", "8310-5")   # Body temperature
L_HR   = ("http://loinc.org", "8867-4")   # Heart rate
L_SPO2 = ("http://loinc.org", "59408-5")  # Oxygen saturation

@dataclass
class Event:
    t: datetime
    kind: str         # 'fever' | 'tachy' | 'low_spo2'
    value: float
    src_obs_id: str   # Observation/<id>

def _iso_parse(s: str) -> datetime:
    if s.endswith("Z"): s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s).astimezone(timezone.utc)

def _code(e: dict) -> Tuple[str, str] | None:
    coding = (e.get("code") or {}).get("coding") or []
    if not coding: return None
    c = coding[0]
    return (c.get("system"), c.get("code"))

def load_thresholds(path: str | Path = "thresholds.yaml") -> dict:
    p = Path(path)
    if not p.exists():
        return {
            "rules": {
                "fever_to_tachy_hours_max": 6,
                "tachy_to_lowspo2_hours_max": 12,
                "tachy_hr_min": 100,
                "low_spo2_max": 92,
            }
        }
    return yaml.safe_load(p.read_text())

def extract_events_from_bundle(bundle_path: Path, thr: dict) -> Tuple[str, List[Event]]:
    b = json.loads(bundle_path.read_text(encoding="utf-8"))
    pid = None
    for entry in b.get("entry", []):
        r = entry.get("resource", {})
        if r.get("resourceType") == "Patient":
            pid = r.get("id")
            break
    if not pid:
        pid = bundle_path.stem

    tachy_min = thr["rules"]["tachy_hr_min"]
    spo2_max  = thr["rules"]["low_spo2_max"]

    events: List[Event] = []
    for entry in b.get("entry", []):
        r = entry.get("resource", {})
        if r.get("resourceType") != "Observation": 
            continue
        loinc = _code(r)
        dt_s  = r.get("effectiveDateTime")
        if not loinc or not dt_s:
            continue
        dt = _iso_parse(dt_s)

        vq = r.get("valueQuantity") or {}
        try:
            val = float(vq.get("value"))
        except Exception:
            continue

        if loinc == L_TEMP and val > 38.0:
            events.append(Event(dt, "fever", val, f"Observation/{r.get('id','obs')}"))
        elif loinc == L_HR and val >= tachy_min:
            events.append(Event(dt, "tachy", val, f"Observation/{r.get('id','obs')}"))
        elif loinc == L_SPO2 and val <= spo2_max:
            events.append(Event(dt, "low_spo2", val, f"Observation/{r.get('id','obs')}"))

    events.sort(key=lambda e: e.t)
    return pid, events

def match_temporal_patterns(events: List[Event], thr: dict) -> Dict[str, List[Tuple[Event, Event]]]:
    out: Dict[str, List[Tuple[Event, Event]]] = {
        "fever_to_tachy": [],
        "tachy_to_lowspo2": [],
    }
    max_fe_ta_h = thr["rules"]["fever_to_tachy_hours_max"]
    max_ta_sp_h = thr["rules"]["tachy_to_lowspo2_hours_max"]

    fevers = [e for e in events if e.kind == "fever"]
    tachys = [e for e in events if e.kind == "tachy"]
    for f in fevers:
        for t in tachys:
            if t.t >= f.t:
                dt_h = (t.t - f.t).total_seconds() / 3600.0
                if dt_h <= max_fe_ta_h:
                    out["fever_to_tachy"].append((f, t))
                    break

    lows = [e for e in events if e.kind == "low_spo2"]
    for t in tachys:
        for s in lows:
            if s.t >= t.t:
                dt_h = (s.t - t.t).total_seconds() / 3600.0
                if dt_h <= max_ta_sp_h:
                    out["tachy_to_lowspo2"].append((t, s))
                    break

    return out

def cohort_support(cohort_dir: Path, thr: dict) -> Dict[str, Any]:
    res = {
        "fever_to_tachy": {"support": 0, "dt_hours": [], "examples": []},
        "tachy_to_lowspo2": {"support": 0, "dt_hours": [], "examples": []},
    }
    bundles = sorted([p for p in cohort_dir.glob("*.json") if not p.name.startswith("_")])

    for p in bundles:
        pid, evs = extract_events_from_bundle(p, thr)
        matches = match_temporal_patterns(evs, thr)

        if matches["fever_to_tachy"]:
            res["fever_to_tachy"]["support"] += 1
            dt = (matches["fever_to_tachy"][0][1].t - matches["fever_to_tachy"][0][0].t).total_seconds()/3600.0
            res["fever_to_tachy"]["dt_hours"].append(dt)
            res["fever_to_tachy"]["examples"].append(pid)

        if matches["tachy_to_lowspo2"]:
            res["tachy_to_lowspo2"]["support"] += 1
            dt = (matches["tachy_to_lowspo2"][0][1].t - matches["tachy_to_lowspo2"][0][0].t).total_seconds()/3600.0
            res["tachy_to_lowspo2"]["dt_hours"].append(dt)
            res["tachy_to_lowspo2"]["examples"].append(pid)

    for k in res:
        dts = res[k]["dt_hours"]
        res[k]["dt_median"] = round(statistics.median(dts), 2) if dts else None
        del res[k]["dt_hours"]
    return res

def plot_patient_timeline(cohort_dir: Path, out_dir: Path, thr: dict, max_plots: int = 12):
    out_dir.mkdir(parents=True, exist_ok=True)
    bundles = sorted([p for p in cohort_dir.glob("*.json") if not p.name.startswith("_")])[:max_plots]
    for p in bundles:
        pid, evs = extract_events_from_bundle(p, thr)
        if not evs: continue
        t0 = evs[0].t
        xs = [(e.t - t0).total_seconds()/3600.0 for e in evs]
        ys, labels = [], []
        for e in evs:
            if e.kind == "fever": ys.append(3); labels.append(f"Fever {e.value}C")
            elif e.kind == "tachy": ys.append(2); labels.append(f"Tachy {int(e.value)}bpm")
            else: ys.append(1); labels.append(f"SpO₂ {e.value}%")

        plt.figure(figsize=(7, 2.2))
        plt.scatter(xs, ys)
        for x,y,l in zip(xs, ys, labels):
            plt.text(x, y+0.05, l, fontsize=8)
        plt.yticks([1,2,3], ["Low SpO₂", "Tachy", "Fever"])
        plt.xlabel("Hours since first event")
        plt.title(f"Timeline — {pid}")
        plt.tight_layout()
        out_path = out_dir / f"{pid}.png"
        plt.savefig(out_path, dpi=160)
        plt.close()
