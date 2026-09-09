"""Fetch ACS 5-year bachelor's attainment for every U.S. Census place."""

import csv
import hashlib
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
OUTPUT = ROOT / "work/raw/acs5_place_education_2024.csv"
MANIFEST = ROOT / "work/raw/acs5_place_education_2024.manifest.json"


def read_key() -> str:
    for line in (ROOT / ".env").read_text().splitlines():
        if line.startswith("CENSUS_API_KEY=") and line.split("=", 1)[1].strip():
            return line.split("=", 1)[1].strip()
    raise RuntimeError("CENSUS_API_KEY is missing from .env")


def fetch(params: dict[str, str], context: ssl.SSLContext) -> list[list[str]]:
    with urlopen(DATASET + "?" + urlencode(params), timeout=120, context=context) as response:
        return json.loads(response.read().decode("utf-8"))


def clean_int(value: str | None) -> int | None:
    return None if value in (None, "", "-666666666") else int(value)


def main() -> None:
    context = ssl.create_default_context(cafile=certifi.where())
    variables = "NAME,B15003_001E,B15003_022E,B15003_023E,B15003_024E,B15003_025E"
    header, *rows = fetch({"get": variables, "for": "place:*", "in": "state:*", "key": read_key()}, context)
    records = []
    for row in rows:
        item = dict(zip(header, row))
        universe = clean_int(item.get("B15003_001E"))
        degree_count = sum(clean_int(item.get(name)) or 0 for name in (
            "B15003_022E", "B15003_023E", "B15003_024E", "B15003_025E"
        ))
        records.append({
            "census_geoid": "1600000US" + item["state"] + item["place"],
            "geography_type": "place",
            "state_fips": item["state"],
            "place_fips": item["place"],
            "geography_name": item["NAME"],
            "acs_vintage": VINTAGE,
            "education_universe_25_plus": universe,
            "bachelors_or_higher_count": degree_count if universe is not None else None,
            "bachelors_or_higher_pct": round(degree_count * 100 / universe, 3) if universe else None,
            "source_id": f"acs5_{VINTAGE}_place_education",
        })
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    MANIFEST.write_text(json.dumps({
        "source_id": "acs5_2024_place_education",
        "publisher": "U.S. Census Bureau",
        "dataset": "ACS 5-year",
        "vintage": VINTAGE,
        "retrieved_at": datetime.now(timezone.utc).isoformat(),
        "source_url": DATASET,
        "variables": ["B15003_001E", "B15003_022E", "B15003_023E", "B15003_024E", "B15003_025E"],
        "record_count": len(records),
        "sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        "notes": "Bachelor's-or-higher is the share of residents age 25+ with a bachelor's, master's, professional, or doctorate degree.",
    }, indent=2) + "\n")
    print(f"Wrote {len(records):,} place education records to {OUTPUT}")


if __name__ == "__main__":
    main()
