# src/synth_temporal.py
from __future__ import annotations
from pathlib import Path
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import random, json, uuid

# LOINC codes
LOINC_TEMP = ("http://loinc.org", "8310-5")   # Body temperature
LOINC_HR   = ("http://loinc.org", "8867-4")   # Heart rate
LOINC_SPO2 = ("http://loinc.org", "59408-5")  # SpO2 (optional)

@dataclass
class CohortSpec:
    n_patients: int = 40
    p_fever: float = 0.55            # chance a patient has a fever event
    p_tachy_given_fever: float = 0.65  # chance tachy follows fever
    p_tachy_alone: float = 0.15      # tachy without fever
    p_low_spo2: float = 0.25         # chance low SpO2 appears
    max_hours_fe_to_ta: int = 8      # max hours between fever → tachy
    start_date: datetime = datetime(2025, 1, 1, tzinfo=timezone.utc)

def _iso(dt): return dt.isoformat().replace("+00:00", "Z")

def _patient_name(i: int):
    return {"family": f"Patient{i:03d}", "given": ["Test"]}

def _obs(resource_id: str, patient_id: str, dt: datetime, loinc, display: str, value: float, unit: str):
    system, code = loinc
    return {
        "resourceType": "Observation",
        "id": resource_id,
        "status": "final",
        "subject": {"reference": f"Patient/{patient_id}"},
        "effectiveDateTime": _iso(dt),
        "code": {"coding": [{"system": system, "code": code, "display": display}]},
        "valueQuantity": {"value": value, "unit": unit}
    }

def _bundle(patient_id: str, patient_name, resources):
    return {
        "resourceType": "Bundle",
        "type": "collection",
        "entry": [{"resource": r} for r in
                  [{"resourceType":"Patient", "id": patient_id, "name":[patient_name]}] + resources]
    }

def synth_cohort(out_dir: Path, spec: CohortSpec):
    out_dir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(42)
    created = []

    for i in range(spec.n_patients):
        pid = f"p{1+i:03d}"
        t0  = spec.start_date + timedelta(days=rng.randint(0, 20), hours=rng.randint(7, 15))

        resources = []

        had_fever = rng.random() < spec.p_fever
        had_tachy = False

        if had_fever:
            temp_val = round(rng.uniform(38.1, 40.2), 1)
            fever_dt = t0 + timedelta(hours=rng.uniform(0, 2))
            resources.append(_obs("obs-temp-"+uuid.uuid4().hex[:6], pid, fever_dt, LOINC_TEMP, "Body temperature", temp_val, "Celsius"))

            # tachy after fever?
            if rng.random() < spec.p_tachy_given_fever:
                had_tachy = True
                delta_h = rng.uniform(0.5, spec.max_hours_fe_to_ta)
                tachy_dt = fever_dt + timedelta(hours=delta_h)
                hr_val = rng.randint(101, 138)
                resources.append(_obs("obs-hr-"+uuid.uuid4().hex[:6], pid, tachy_dt, LOINC_HR, "Heart rate", hr_val, "beats/minute"))
        else:
            # maybe tachy alone
            if rng.random() < spec.p_tachy_alone:
                had_tachy = True
                tachy_dt = t0 + timedelta(hours=rng.uniform(0, 10))
                hr_val = rng.randint(101, 130)
                resources.append(_obs("obs-hr-"+uuid.uuid4().hex[:6], pid, tachy_dt, LOINC_HR, "Heart rate", hr_val, "beats/minute"))

        # optional SpO2 (sometimes low)
        if rng.random() < spec.p_low_spo2:
            spo2_dt = t0 + timedelta(hours=rng.uniform(0, 14))
            spo2_val = round(rng.uniform(85, 99), 1)
            resources.append(_obs("obs-spo2-"+uuid.uuid4().hex[:6], pid, spo2_dt, LOINC_SPO2, "Oxygen saturation", spo2_val, "percent"))

        bundle = _bundle(pid, _patient_name(i+1), resources)
        path = out_dir / f"{pid}.json"
        path.write_text(json.dumps(bundle, indent=2), encoding="utf-8")
        created.append(path.name)

    meta = {
        "n_files": len(created),
        "files": created,
        "notes": {
            "p_fever": spec.p_fever,
            "p_tachy_given_fever": spec.p_tachy_given_fever,
            "p_tachy_alone": spec.p_tachy_alone,
            "p_low_spo2": spec.p_low_spo2
        }
    }
    (out_dir / "_meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return meta

def main():
    import argparse
    ap = argparse.ArgumentParser(description="Generate synthetic temporal FHIR Bundles")
    ap.add_argument("--out", default="data/bundles_temporal")
    ap.add_argument("--n", type=int, default=40)
    ap.add_argument("--seed", type=int, default=42)  # kept for future use
    args = ap.parse_args()

    spec = CohortSpec(n_patients=args.n)
    meta = synth_cohort(Path(args.out), spec)
    print(f"✅ Wrote {meta['n_files']} bundles to {args.out}")

if __name__ == "__main__":
    main()
