"""Fetch ACS 5-year housing context for U.S. Census places."""

import csv
import json
import ssl
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

import certifi

ROOT = Path(__file__).resolve().parents[1]
VINTAGE = "2024"
DATASET = f"https://api.census.gov/data/{VINTAGE}/acs/acs5"
OUTPUT = ROOT / "work/raw/acs5_place_housing_2024.csv"
US_FIPS = {f"{n:02d}" for n in range(1, 57)}


def key() -> str:
    for line in (ROOT / ".env").read_text().splitlines():
        if line.startswith("CENSUS_API_KEY=") and line.split("=", 1)[1].strip():
            return line.split("=", 1)[1].strip()
    raise RuntimeError("CENSUS_API_KEY is missing from .env")


def clean(value):
    return None if value in (None, "", "-666666666") else int(value)


def main() -> None:
    params = {
        "get": "NAME,B25077_001E,B25064_001E,B25070_001E,B25070_007E,B25070_008E,B25070_009E,B25070_010E",
        "for": "place:*",
        "in": "state:*",
        "key": key(),
    }
    context = ssl.create_default_context(cafile=certifi.where())
    with urlopen(DATASET + "?" + urlencode(params), timeout=120, context=context) as response:
        payload = json.loads(response.read().decode("utf-8"))
    header, *rows = payload
    records = []
    for row in rows:
        item = dict(zip(header, row))
        if item["state"] not in US_FIPS:
            continue
        total = clean(item.get("B25070_001E"))
        burdened = sum(clean(item.get(v)) or 0 for v in ("B25070_007E", "B25070_008E", "B25070_009E", "B25070_010E"))
        records.append({
            "census_geoid": "1600000US" + item["state"] + item["place"],
            "state_fips": item["state"],
            "place_fips": item["place"],
            "geography_name": item["NAME"],
            "acs_vintage": VINTAGE,
            "median_home_value": clean(item.get("B25077_001E")),
            "median_gross_rent": clean(item.get("B25064_001E")),
            "renter_cost_burden_30_pct_plus": round(100 * burdened / total, 1) if total else None,
            "renter_cost_burden_universe": total,
            "source_id": f"acs5_{VINTAGE}_place_housing",
        })
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    print(f"Wrote {len(records):,} place housing records to {OUTPUT}")


if __name__ == "__main__":
    main()
