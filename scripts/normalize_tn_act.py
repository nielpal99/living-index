"""Normalize Tennessee's official 2024-25 district ACT export."""

import csv
import io
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "work/raw/tn/converted/tn_act_district_2024_25.csv"
NCES_ZIP = ROOT / "work/raw/ccd_lea_2023_24.zip"
OUTPUT = ROOT / "work/raw/tn/tn_act_performance_observations.csv"


def clean_number(value: str) -> str:
    value = (value or "").strip().rstrip(".")
    return value if value not in {"", "<1%", ">99%", "*", "N/A"} else ""


def main() -> None:
    with zipfile.ZipFile(NCES_ZIP) as archive:
        nces_csv = next(name for name in archive.namelist() if name.lower().endswith(".csv"))
        rows = csv.DictReader(io.TextIOWrapper(archive.open(nces_csv), encoding="utf-8-sig"))
        nces_by_name = {
            row["LEA_NAME"].strip().upper(): row["LEAID"]
            for row in rows
            if row["ST"] == "TN"
        }

    observations = []
    unmatched = set()
    with INPUT.open(newline="") as source:
        for row in csv.DictReader(source):
            if row["Subgroup"].strip() != "All Students":
                continue
            score = clean_number(row["Average Composite Score"])
            tested = clean_number(row["Valid Tests"])
            participation = clean_number(row["Participation Rate"])
            if not score:
                continue
            district_name = row["District Name"].strip().upper()
            district_id = nces_by_name.get(district_name)
            if not district_id:
                unmatched.add(district_name)
                continue
            observations.append({
                "observation_id": f"tn_{district_id}_act_2024_25",
                "nces_school_id": "",
                "nces_district_id": district_id,
                "test_type": "ACT",
                "metric_name": "average_composite",
                "metric_value": score,
                "score_year": "2024-25",
                "students_tested": tested,
                "participation_rate": participation,
                "aggregation_method": "official_district_average",
                "source_type": "official_state_export",
                "source_id": "tennessee_act_2024_25_scores",
                "confidence": "high",
                "notes": "Tennessee district ACT average; All Students; highest scores in prior three years for graduates.",
            })

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    columns = list(observations[0].keys())
    with OUTPUT.open("w", newline="") as destination:
        writer = csv.DictWriter(destination, fieldnames=columns)
        writer.writeheader()
        writer.writerows(sorted(observations, key=lambda item: item["nces_district_id"]))
    print(f"Wrote {len(observations):,} Tennessee district ACT observations to {OUTPUT}")
    print(f"Excluded {len(unmatched):,} unmatched Tennessee entities")


if __name__ == "__main__":
    main()
