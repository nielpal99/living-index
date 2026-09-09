"""Validate the national ACS state/county/place income extract."""

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "work/raw/acs5_place_income_2024.csv"
MANIFEST = ROOT / "work/raw/acs5_place_income_2024.manifest.json"
US_FIPS = {f"{n:02d}" for n in range(1, 57)}


def main() -> None:
    with INPUT.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    manifest = json.loads(MANIFEST.read_text())
    errors = []
    keys = [(row["census_geoid"], row["acs_vintage"]) for row in rows]
    if len(keys) != len(set(keys)):
        errors.append("duplicate geography/vintage keys")
    if {row["state_fips"] for row in rows} - US_FIPS:
        errors.append("territory or invalid FIPS found")
    for row in rows:
        if row["geography_type"] not in {"state", "county", "place"}:
            errors.append(f"invalid geography_type: {row['geography_type']}")
        if row["median_household_income"] and int(row["median_household_income"]) < 0:
            errors.append(f"negative income: {row['census_geoid']}")
    counts = {kind: sum(row["geography_type"] == kind for row in rows) for kind in ("state", "county", "place")}
    if counts["state"] != 51:
        errors.append(f"expected 51 state/DC records, found {counts['state']}")
    if manifest.get("record_count") != len(rows):
        errors.append("manifest record_count does not match extract")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"ACS income contract passed: {len(rows):,} rows; {counts}")


if __name__ == "__main__":
    main()
