"""Fetch ACS 5-year unified school-district demographics for the warehouse."""

import csv
import json
import ssl
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

import certifi


ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / ".env"
OUTPUT = ROOT / "work/raw/acs5_school_district_unified_2023.json"
CSV_OUTPUT = ROOT / "work/raw/acs5_school_district_unified_2023.csv"


def read_key() -> str:
    for line in ENV_FILE.read_text().splitlines():
        if line.startswith("CENSUS_API_KEY="):
            value = line.split("=", 1)[1].strip()
            if value:
                return value
    raise RuntimeError("Put the replacement key in .env after CENSUS_API_KEY=")


def main() -> None:
    variables = [
        "NAME",
        "B19013_001E",
        "B15003_001E",
        "B15003_022E",
        "B15003_023E",
        "B15003_024E",
        "B15003_025E",
    ]
    params = {
        "get": ",".join(variables),
        "for": "school district (unified):*",
        "in": "state:*",
        "key": read_key(),
    }
    url = "https://api.census.gov/data/2023/acs/acs5?" + urlencode(params)
    ssl_context = ssl.create_default_context(cafile=certifi.where())
    with urlopen(url, timeout=90, context=ssl_context) as response:
        payload = json.loads(response.read().decode("utf-8"))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload))
    with CSV_OUTPUT.open("w", newline="") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerows(payload)
    print(f"Wrote {len(payload) - 1:,} ACS rows to {CSV_OUTPUT}")


if __name__ == "__main__":
    main()
