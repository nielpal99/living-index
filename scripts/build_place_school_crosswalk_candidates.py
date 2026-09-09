"""Build conservative place-to-school crosswalk candidates from local NCES CCD data.

This is deliberately a candidate layer: matching a school's mailing city to a Census
place name is not a boundary join and must not be treated as proof that the school
serves the entire place. Spatial or official attendance-boundary validation comes later.
"""

from __future__ import annotations

import csv
import re
import zipfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLACES = ROOT / "work/raw/acs5_place_income_2024.csv"
SCHOOLS = ROOT / "work/raw/ccd_school_2023_24.zip"
OUTPUT = ROOT / "work/raw/place_school_crosswalk_candidates_2023_24.csv"


def norm(value: str) -> str:
    value = (value or "").upper().replace("&", " AND ")
    value = re.sub(r"\b(CITY|TOWN|VILLAGE|BOROUGH|CDP|TOWNSHIP|PLANTATION)\b", " ", value)
    return re.sub(r"[^A-Z0-9]+", " ", value).strip()


def main() -> None:
    places: dict[tuple[str, str], dict[str, str]] = {}
    with PLACES.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row["geography_type"] == "place":
                # The local extract labels places as "Name, State"; NCES stores
                # the mailing city separately, so normalize only the place name.
                places[(row["state_fips"], norm(row["geography_name"].split(",", 1)[0]))] = row

    schools_by_place: dict[tuple[str, str], set[tuple[str, str]]] = defaultdict(set)
    zf = zipfile.ZipFile(SCHOOLS)
    csv_name = next(name for name in zf.namelist() if name.endswith(".csv"))
    with zf.open(csv_name) as raw:
        text = (line.decode("latin-1") for line in raw)
        for row in csv.DictReader(text):
            if row.get("SY_STATUS") != "1":
                continue
            key = (row.get("FIPST", "").zfill(2), norm(row.get("MCITY", "")))
            if key in places and row.get("LEAID") and row.get("NCESSCH"):
                schools_by_place[key].add((row["LEAID"], row["NCESSCH"]))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="", encoding="utf-8") as handle:
        fields = [
            "census_geoid", "geography_name", "state_fips", "place_fips",
            "nces_school_count", "nces_district_count", "match_method",
            "confidence", "validation_status", "notes",
        ]
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for key, schools in sorted(schools_by_place.items()):
            place = places[key]
            writer.writerow({
                "census_geoid": place["census_geoid"],
                "geography_name": place["geography_name"],
                "state_fips": place["state_fips"],
                "place_fips": place["place_fips"],
                "nces_school_count": len(schools),
                "nces_district_count": len({district for district, _ in schools}),
                "match_method": "nces_school_city_to_census_place_name",
                "confidence": "low",
                "validation_status": "candidate_only",
                "notes": "Mailing-city name match; not a geographic attendance-boundary join.",
            })
    print(f"Wrote {len(schools_by_place):,} conservative crosswalk candidates to {OUTPUT}")


if __name__ == "__main__":
    main()
