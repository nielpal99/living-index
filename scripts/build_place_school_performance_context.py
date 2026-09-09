"""Attach available district performance observations to Census-place overlaps.

This is a context layer, not an attendance-boundary assignment. A place may
retain multiple district/test rows, and no place-level academic score is
calculated here.
"""

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CROSSWALK = ROOT / "work/raw/place_unified_school_district_spatial_crosswalk_2023.csv"
PERFORMANCE_FILES = [
    ROOT / "work/raw/ga/ga_performance_observations_v2.csv",
    ROOT / "work/raw/tn/tn_act_performance_observations.csv",
    ROOT / "work/raw/ky/ky_act_performance_observations.csv",
]
OUTPUT = ROOT / "work/raw/place_school_performance_context_2024_25.csv"


def read_rows(path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


crosswalk = read_rows(CROSSWALK)
performance = []
for path in PERFORMANCE_FILES:
    performance.extend(read_rows(path))

by_district = {}
for row in performance:
    by_district.setdefault(row["nces_district_id"], []).append(row)

fields = [
    "place_geoid", "place_name", "state_fips", "district_geoid", "district_name",
    "place_area_share_pct", "crosswalk_method", "crosswalk_confidence",
    "crosswalk_validation_status", "test_type", "metric_name", "metric_value",
    "score_year", "students_tested", "participation_rate", "aggregation_method",
    "source_type", "source_id", "performance_confidence", "performance_notes",
]
rows = []
seen = set()
for link in crosswalk:
    district_id = link["district_geoid"].replace("9700000US", "", 1)
    for score in by_district.get(district_id, []):
        key = (link["place_geoid"], district_id, score["test_type"], score["score_year"], score["source_id"])
        if key in seen:
            continue
        seen.add(key)
        rows.append({
            "place_geoid": link["place_geoid"],
            "place_name": link["place_name"],
            "state_fips": link["state_fips"],
            "district_geoid": link["district_geoid"],
            "district_name": link["district_name"],
            "place_area_share_pct": link["place_area_share_pct"],
            "crosswalk_method": link["match_method"],
            "crosswalk_confidence": link["confidence"],
            "crosswalk_validation_status": link["validation_status"],
            "test_type": score["test_type"],
            "metric_name": score["metric_name"],
            "metric_value": score["metric_value"],
            "score_year": score["score_year"],
            "students_tested": score["students_tested"],
            "participation_rate": score["participation_rate"],
            "aggregation_method": score["aggregation_method"],
            "source_type": score["source_type"],
            "source_id": score["source_id"],
            "performance_confidence": score["confidence"],
            "performance_notes": score["notes"],
        })

with OUTPUT.open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)

print(f"Wrote {len(rows):,} place-district-test context rows to {OUTPUT}")
print(f"Places with performance context: {len({r['place_geoid'] for r in rows}):,}")
print(f"Districts represented: {len({r['district_geoid'] for r in rows}):,}")
