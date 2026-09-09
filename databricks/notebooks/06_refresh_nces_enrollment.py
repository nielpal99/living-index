"""Append NCES enrollment snapshots and expose current coverage.

Expected input: an official NCES membership extract in the raw volume with
NCES district ID, state, enrollment year, and total enrollment columns. The
notebook refuses to guess a field mapping and never deletes snapshots.
"""

from pyspark.sql import functions as F


INPUT_PATH = "/Volumes/workspace/default/raw_sources/nces_district_membership.csv"
SOURCE_ID = "nces_district_membership"

raw = spark.read.option("header", True).option("inferSchema", False).csv(INPUT_PATH)
required = {"nces_district_id", "state_abbr", "enrollment", "enrollment_year"}
missing = sorted(required - set(raw.columns))
if missing:
    raise ValueError(f"Missing required membership columns: {','.join(missing)}")

snapshot_id = F.sha2(F.concat_ws("|", F.col("nces_district_id"), F.col("enrollment_year"), F.lit(SOURCE_ID)), 256)
prepared = raw.select(
    snapshot_id.alias("snapshot_id"),
    F.col("nces_district_id").cast("string"),
    F.col("state_abbr").cast("string"),
    F.expr("try_cast(enrollment AS BIGINT)").alias("enrollment"),
    F.col("enrollment_year").cast("string"),
    F.lit(SOURCE_ID).alias("source_id"),
    F.current_timestamp().alias("retrieved_at"),
    F.lit("district").alias("geographic_precision"),
    F.coalesce(F.col("suppression_flag").cast("boolean"), F.lit(False)).alias("suppression_flag")
    if "suppression_flag" in raw.columns else F.lit(False).alias("suppression_flag"),
    F.col("notes").cast("string") if "notes" in raw.columns else F.lit(None).cast("string").alias("notes"),
).where(
    F.col("nces_district_id").isNotNull() &
    F.col("enrollment").isNotNull() &
    F.col("suppression_flag").eqNullSafe(False)
).dropDuplicates(["snapshot_id"])

prepared.createOrReplaceTempView("nces_enrollment_rows")
spark.sql("""
INSERT INTO living_index.silver.district_enrollment_snapshots
SELECT r.*
FROM nces_enrollment_rows r
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.district_enrollment_snapshots e
  WHERE e.snapshot_id = r.snapshot_id
)
""")

print(f"Appended {prepared.count()} NCES enrollment snapshot candidate(s).")
