"""Fetch descriptive ACS demographic composition for every U.S. Census place."""

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
OUTPUT = ROOT / "work/raw/acs5_place_demographics_2024.csv"
MANIFEST = ROOT / "work/raw/acs5_place_demographics_2024.manifest.json"


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


def pct(count: int | None, total: int | None) -> float | None:
    return round(100.0 * count / total, 3) if count is not None and total else None


def main() -> None:
    context = ssl.create_default_context(cafile=certifi.where())
    age_under_18 = [f"B01001_{n:03d}E" for n in (*range(3, 7), *range(27, 31))]
    variables = ["NAME", "B01003_001E", "B02001_002E", "B02001_003E", "B02001_005E", "B03003_003E", "B05002_013E", *age_under_18]
    header, *rows = fetch({"get": ",".join(variables), "for": "place:*", "in": "state:*", "key": read_key()}, context)
    records = []
    for row in rows:
        item = dict(zip(header, row))
        total = clean_int(item.get("B01003_001E"))
        under_18 = sum(clean_int(item.get(name)) or 0 for name in age_under_18)
        records.append({
            "census_geoid": "1600000US" + item["state"] + item["place"],
            "geography_type": "place",
            "state_fips": item["state"],
            "place_fips": item["place"],
            "geography_name": item["NAME"],
            "acs_vintage": VINTAGE,
            "total_population": total,
            "white_alone_pct": pct(clean_int(item.get("B02001_002E")), total),
            "black_alone_pct": pct(clean_int(item.get("B02001_003E")), total),
            "asian_alone_pct": pct(clean_int(item.get("B02001_005E")), total),
            "hispanic_or_latino_pct": pct(clean_int(item.get("B03003_003E")), total),
            "foreign_born_pct": pct(clean_int(item.get("B05002_013E")), total),
            "under_18_pct": pct(under_18, total),
            "source_id": f"acs5_{VINTAGE}_place_demographics",
        })
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    MANIFEST.write_text(json.dumps({
        "source_id": "acs5_2024_place_demographics",
        "publisher": "U.S. Census Bureau",
        "dataset": "ACS 5-year",
        "vintage": VINTAGE,
        "retrieved_at": datetime.now(timezone.utc).isoformat(),
        "source_url": DATASET,
        "variables": variables,
        "record_count": len(records),
        "sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        "notes": "Descriptive composition signals only; not used in the V1 quality or ranking score.",
    }, indent=2) + "\n")
    print(f"Wrote {len(records):,} place demographic records to {OUTPUT}")


if __name__ == "__main__":
    main()
