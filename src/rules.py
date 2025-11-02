# src/rules.py
from __future__ import annotations
from dataclasses import dataclass
from typing import Optional

# Canonical LOINC codes we’ll use
LOINC_TEMP = ("http://loinc.org", "8310-5")
LOINC_HR   = ("http://loinc.org", "8867-4")
LOINC_SPO2 = ("http://loinc.org", "59408-5")  # optional extension

@dataclass
class Thresholds:
    fever_c: float = 38.0
    tachy_bpm: int = 100
    low_spo2: float = 92.0
    # temporal windows (hours)
    fever_to_tachy_hours: float = 6.0
    tachy_to_spo2_hours: float = 12.0

def is_fever(code_sys: str, code: str, value: Optional[float], unit: Optional[str], t: Thresholds) -> bool:
    if (code_sys, code) != LOINC_TEMP or value is None: 
        return False
    # assume Celsius for demo
    return value > t.fever_c

def is_tachy(code_sys: str, code: str, value: Optional[float], unit: Optional[str], t: Thresholds) -> bool:
    if (code_sys, code) != LOINC_HR or value is None:
        return False
    return value > t.tachy_bpm

def is_low_spo2(code_sys: str, code: str, value: Optional[float], unit: Optional[str], t: Thresholds) -> bool:
    if (code_sys, code) != LOINC_SPO2 or value is None:
        return False
    return value < t.low_spo2
