"""Normalize Georgia's official district-level SAT/ACT exports."""

import csv
import io
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INPUTS = {
    "ACT": ROOT / "work/raw/ga/ga_act_2024_25_highest.csv",
    "SAT": ROOT / "work/raw/ga/ga_sat_2024_25_highest.csv",
}
OUTPUT = ROOT / "work/raw/ga/ga_performance_observations.csv"
NCES_ZIP = ROOT / "work/raw/ccd_lea_2023_24.zip"


def clean_number(value: str):
    value = value.strip().rstrip(".")
    return value if value not in {"", "TFS", "N/A", "*"} else ""


def main() -> None:
    with zipfile.ZipFile(NCES_ZIP) as archive:
        nces_csv = next(name for name in archive.namelist() if name.lower().endswith(".csv"))
        nces_rows = csv.DictReader(io.TextIOWrapper(archive.open(nces_csv), encoding="utf-8-sig"))
        nces_by_name = {
            row["LEA_NAME"].strip().upper(): row["LEAID"]
            for row in nces_rows
            if row["ST"] == "GA"
        }
    observations = {}
    unmatched = set()
    for test_type, path in INPUTS.items():
        with path.open(newline="") as source:
            for row in csv.DictReader(source):
                component = "Composite" if test_type == "ACT" else "Combined Test Score"
                if row["SUBGRP_DESC"] != "All Students" or row["TEST_CMPNT_TYP_CD"] != component:
                    continue
                score = clean_number(row["DSTRCT_AVG_SCORE_VAL"])
                tested = clean_number(row["DSTRCT_NUM_TESTED_CNT"])
                if not score:
                    continue
                district_name = row["SCHOOL_DSTRCT_NM"].strip().upper()
                district_id = nces_by_name.get(district_name)
                if not district_id:
                    unmatched.add(district_name)
                    continue
                observations[(district_id, test_type)] = {
                    "observation_id": f"ga_{district_id}_{test_type.lower()}_2024_25",
                    "nces_school_id": "",
                    "nces_district_id": district_id,
                    "test_type": test_type,
                    "metric_name": "average_composite",
                    "metric_value": score,
                    "score_year": "2024-25",
                    "students_tested": tested,
                    "participation_rate": "",
                    "aggregation_method": "official_district_average",
                    "source_type": "official_state_export",
                    "source_id": "georgia_goews_2024_25_scores_crosswalked",
                    "confidence": "high",
                    "notes": "Georgia GOSA district average; All Students; highest/recent score export.",
                }

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    columns = list(next(iter(observations.values())).keys())
    with OUTPUT.open("w", newline="") as destination:
        writer = csv.DictWriter(destination, fieldnames=columns)
        writer.writeheader()
        writer.writerows(sorted(observations.values(), key=lambda item: (item["nces_district_id"], item["test_type"])))
    print(f"Wrote {len(observations):,} normalized district observations to {OUTPUT}")
    print(f"Excluded {len(unmatched):,} unmatched Georgia entities")


if __name__ == "__main__":
    main()
