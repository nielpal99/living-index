"""Fetch ACS 5-year median income for every U.S. state, county, and Census place."""

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
OUTPUT = ROOT / "work/raw/acs5_place_income_2024.csv"
MANIFEST = ROOT / "work/raw/acs5_place_income_2024.manifest.json"
US_FIPS = {f"{n:02d}" for n in range(1, 57)}


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


def fetch_geo(geo_type: str, context: ssl.SSLContext, key: str) -> list[dict[str, object]]:
    params = {"get": "NAME,B19013_001E,B01003_001E", "key": key}
    prefix = {"state": "0400000US", "county": "0500000US", "place": "1600000US"}[geo_type]
    if geo_type == "state":
        params["for"] = "state:*"
    else:
        params["for"] = f"{geo_type}:*"
        params["in"] = "state:*"
    header, *rows = fetch(params, context)
    records = []
    for row in rows:
        item = dict(zip(header, row))
        if item["state"] not in US_FIPS:
            continue
        suffix = item["state"] + (item.get("county") or item.get("place") or "")
        records.append({
            "census_geoid": prefix + suffix,
            "geography_type": geo_type,
            "state_fips": item["state"],
            "county_fips": item.get("county"),
            "place_fips": item.get("place"),
            "geography_name": item["NAME"],
            "acs_vintage": VINTAGE,
            "median_household_income": clean_int(item.get("B19013_001E")),
            "total_population": clean_int(item.get("B01003_001E")),
            "source_id": f"acs5_{VINTAGE}_{geo_type}_income",
        })
    return records


def main() -> None:
    context = ssl.create_default_context(cafile=certifi.where())
    records = []
    for geo_type in ("state", "county", "place"):
        batch = fetch_geo(geo_type, context, read_key())
        records.extend(batch)
        print(f"Fetched {len(batch):,} {geo_type} records")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    digest = hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
    MANIFEST.write_text(json.dumps({
        "source_id": "acs5_2024_state_county_place_income",
        "publisher": "U.S. Census Bureau",
        "dataset": "ACS 5-year",
        "vintage": VINTAGE,
        "retrieved_at": datetime.now(timezone.utc).isoformat(),
        "source_url": DATASET,
        "geographies": ["state", "county", "place"],
        "record_count": len(records),
        "sha256": digest,
        "notes": "Census places are the reproducible city search surface; U.S. states plus DC, excluding territories.",
    }, indent=2) + "\n")
    print(f"Wrote {len(records):,} records to {OUTPUT}")


if __name__ == "__main__":
    main()
