"""Load ACS income for all U.S. states, counties, and Census places."""

import json
import ssl
from datetime import datetime, timezone
from urllib.parse import urlencode
from urllib.request import urlopen

from pyspark.sql import functions as F

ACS_VINTAGE = "2024"
US_FIPS = {f"{n:02d}" for n in range(1, 57)}
API = f"https://api.census.gov/data/{ACS_VINTAGE}/acs/acs5"
dbutils.widgets.text("force_refresh", "false")
force_refresh = dbutils.widgets.get("force_refresh").lower() == "true"

spark.sql("""
CREATE TABLE IF NOT EXISTS living_index.silver.place_income (
  census_geoid STRING, geography_type STRING, state_fips STRING, county_fips STRING,
  place_fips STRING, geography_name STRING, acs_vintage STRING,
  median_household_income DECIMAL(18,2), total_population BIGINT, source_id STRING,
  loaded_at TIMESTAMP
) USING DELTA
""")

spark.sql("""
CREATE TABLE IF NOT EXISTS living_index.gold.finops_run_events (
  run_id TIMESTAMP, pipeline_name STRING, source_id STRING, action STRING,
  rows_read BIGINT, rows_written BIGINT, api_requests BIGINT,
  skipped_reason STRING, created_at TIMESTAMP
) USING DELTA
""")

if not force_refresh and spark.catalog.tableExists("living_index.silver.place_income"):
    recent = spark.sql(f"""
      SELECT max(loaded_at) AS latest_loaded
      FROM living_index.silver.place_income
      WHERE acs_vintage = '{ACS_VINTAGE}'
    """).first()["latest_loaded"]
    age_days = (datetime.now(timezone.utc).replace(tzinfo=None) - recent).days if recent is not None else 99999
    if recent is not None and age_days < 30:
        spark.createDataFrame(
            [(None, "07_ingest_place_income", "acs5_2024_state_county_place_income", "skipped", 0, 0, 0,
              "Current vintage loaded within refresh window",)],
            "run_id timestamp, pipeline_name string, source_id string, action string, rows_read long, "
            "rows_written long, api_requests long, skipped_reason string",
        ).withColumn("created_at", F.current_timestamp()).write.mode("append").saveAsTable("living_index.gold.finops_run_events")
        dbutils.notebook.exit("Skipped: current ACS vintage is inside the 30-day refresh window.")


def fetch(geography_type, geography, prefix, key):
    params = {"get": "NAME,B19013_001E,B01003_001E", "for": f"{geography}:*", "key": key}
    if geography_type != "state":
        params["in"] = "state:*"
    with urlopen(API + "?" + urlencode(params), timeout=120, context=ssl.create_default_context()) as response:
        header, *rows = json.loads(response.read().decode("utf-8"))
    records = []
    for row in rows:
        item = dict(zip(header, row))
        if item["state"] not in US_FIPS:
            continue
        suffix = item["state"] + (item.get("county") or item.get("place") or "")
        income = item["B19013_001E"]
        population = item["B01003_001E"]
        records.append((prefix + suffix, geography_type, item["state"], item.get("county"),
                        item.get("place"), item["NAME"], ACS_VINTAGE,
                        None if income in ("", "-666666666") else income,
                        None if population in ("", "-666666666") else population,
                        f"acs5_{ACS_VINTAGE}_{geography_type}_income"))
    return records


records = []
volume_path = "/Volumes/workspace/default/raw_sources/acs5_place_income_2024.csv"
if dbutils.fs.ls("/Volumes/workspace/default/raw_sources") and any(
    f.name == "acs5_place_income_2024.csv" for f in dbutils.fs.ls("/Volumes/workspace/default/raw_sources")
):
    raw = spark.read.option("header", True).csv(volume_path)
else:
    key = dbutils.secrets.get(scope="living-index", key="census-api-key")
    records.extend(fetch("state", "state", "0400000US", key))
    records.extend(fetch("county", "county", "0500000US", key))
    records.extend(fetch("place", "place", "1600000US", key))
    raw = spark.createDataFrame(records, "census_geoid string, geography_type string, state_fips string, "
        "county_fips string, place_fips string, geography_name string, acs_vintage string, "
        "median_household_income string, total_population string, source_id string")

prepared = raw.select(
    F.col("census_geoid").cast("string"), F.col("geography_type").cast("string"),
    F.col("state_fips").cast("string"), F.col("county_fips").cast("string"), F.col("place_fips").cast("string"),
    F.col("geography_name").cast("string"), F.col("acs_vintage").cast("string"),
    F.expr("try_cast(median_household_income AS DECIMAL(18,2))").alias("median_household_income"),
    F.expr("try_cast(total_population AS BIGINT)").alias("total_population"),
    F.col("source_id").cast("string"), F.current_timestamp().alias("loaded_at"),
).where(F.col("census_geoid").isNotNull()).dropDuplicates(["census_geoid", "acs_vintage"])

prepared.createOrReplaceTempView("place_income_rows")
spark.sql("""
INSERT INTO living_index.silver.place_income
SELECT r.* FROM place_income_rows r
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.place_income x
  WHERE x.census_geoid = r.census_geoid AND x.acs_vintage = r.acs_vintage
)
""")
print(f"Appended {prepared.count()} ACS state/county/place income rows for vintage {ACS_VINTAGE}.")
spark.createDataFrame(
    [(None, "07_ingest_place_income", "acs5_2024_state_county_place_income", "loaded", raw.count(), prepared.count(), 3, None)],
    "run_id timestamp, pipeline_name string, source_id string, action string, rows_read long, "
    "rows_written long, api_requests long, skipped_reason string",
).withColumn("created_at", F.current_timestamp()).write.mode("append").saveAsTable("living_index.gold.finops_run_events")
