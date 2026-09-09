# Databricks notebook source
# Ingest ACS 5-year school-district demographics.
# Starting vintage is configurable; update it when a later release is selected.

from datetime import datetime
from urllib.parse import urlencode
from urllib.request import urlopen
import json

ACS_VINTAGE = "2023"
ACS_DATASET = f"https://api.census.gov/data/{ACS_VINTAGE}/acs/acs5"
TARGET_TABLE = "living_index.silver.demographics"
CENSUS_API_KEY = dbutils.secrets.get(scope="living-index", key="census-api-key")

# B19013: median household income.
# B15003: educational attainment for population 25+.
# 022E-025E are bachelor's, master's, professional, and doctoral degrees.
education_vars = ["B15003_001E"] + [f"B15003_{n:03d}E" for n in range(22, 26)]
variables = ["NAME", "B19013_001E"] + education_vars

params = {
    "get": ",".join(variables),
    "for": "school district (unified):*",
    "in": "state:*",
    "key": CENSUS_API_KEY,
}
url = f"{ACS_DATASET}?{urlencode(params)}"
with urlopen(url, timeout=60) as response:
    rows = json.loads(response.read().decode("utf-8"))

header, *data = rows
records = []
for row in data:
    item = dict(zip(header, row))
    total_25_plus = int(item["B15003_001E"] or 0)
    bachelors_or_higher = sum(int(item[f"B15003_{n:03d}E"] or 0) for n in range(22, 26))
    records.append({
        "census_geoid": f"9700000US{item['state']}{item['school district (unified)']}",
        "acs_vintage": ACS_VINTAGE,
        "median_household_income": float(item["B19013_001E"]) if item["B19013_001E"] not in (None, "", "-666666666") else None,
        "bachelors_or_higher_pct": (100.0 * bachelors_or_higher / total_25_plus) if total_25_plus else None,
        "population_25_plus": total_25_plus,
        "income_margin_of_error": None,
        "education_margin_of_error": None,
        "source_id": f"acs5_{ACS_VINTAGE}",
        "loaded_at": datetime.utcnow(),
    })

df = spark.createDataFrame(records)
df.write.format("delta").mode("append").saveAsTable(TARGET_TABLE)
display(df.limit(20))
