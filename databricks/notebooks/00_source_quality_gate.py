"""Configuration-driven, append-only source quality gate.

Designed for a Databricks Workflow task. It snapshots coverage checks instead
of mutating source observations, so quality history remains auditable.
"""

from pyspark.sql import functions as F


run_id = spark.sql("SELECT current_timestamp() AS ts").first()["ts"]

spark.sql("""
CREATE TABLE IF NOT EXISTS living_index.gold.source_quality_snapshots (
  run_id TIMESTAMP,
  source_id STRING,
  state_abbr STRING,
  observation_count BIGINT,
  district_count BIGINT,
  base_district_count BIGINT,
  district_coverage_pct DECIMAL(7,2),
  missing_sample_size BIGINT,
  missing_participation_rate BIGINT,
  source_metadata_present BOOLEAN,
  registry_status STRING,
  quality_status STRING,
  quality_reason STRING,
  created_at TIMESTAMP
) USING DELTA
""")

registry = spark.table("living_index.silver.source_registry").alias("r")
observations = spark.table("living_index.silver.performance_observations").alias("p")
sources = spark.table("living_index.silver.sources").alias("s")
districts = spark.table("living_index.silver.districts").alias("d")

observation_summary = (
    observations.join(districts, F.col("p.nces_district_id") == F.col("d.nces_district_id"), "left")
    .groupBy("p.source_id")
    .agg(
        F.count("p.observation_id").alias("observation_count"),
        F.countDistinct("p.nces_district_id").alias("district_count"),
        F.sum(F.when(F.col("p.students_tested").isNull(), 1).otherwise(0)).alias("missing_sample_size"),
        F.sum(F.when(F.col("p.participation_rate").isNull(), 1).otherwise(0)).alias("missing_participation_rate"),
    )
    .alias("o")
)

base = districts.groupBy("state_abbr").agg(
    F.countDistinct("nces_district_id").alias("base_district_count")
).alias("b")

snapshot = (
    registry
    .join(sources, F.col("r.source_id") == F.col("s.source_id"), "left")
    .join(observation_summary, F.col("r.source_id") == F.col("o.source_id"), "left")
    .join(base, F.col("r.state_abbr") == F.col("b.state_abbr"), "left")
    .select(
        F.lit(run_id).cast("timestamp").alias("run_id"),
        F.col("r.source_id"), F.col("r.state_abbr"),
        F.coalesce(F.col("o.observation_count"), F.lit(0)).cast("long").alias("observation_count"),
        F.coalesce(F.col("o.district_count"), F.lit(0)).cast("long").alias("district_count"),
        F.coalesce(F.col("b.base_district_count"), F.lit(0)).cast("long").alias("base_district_count"),
        F.when(F.col("b.base_district_count") > 0,
               F.round(100 * F.coalesce(F.col("o.district_count"), F.lit(0)) / F.col("b.base_district_count"), 2))
         .cast("decimal(7,2)").alias("district_coverage_pct"),
        F.coalesce(F.col("o.missing_sample_size"), F.lit(0)).cast("long").alias("missing_sample_size"),
        F.coalesce(F.col("o.missing_participation_rate"), F.lit(0)).cast("long").alias("missing_participation_rate"),
        F.col("s.source_id").isNotNull().alias("source_metadata_present"),
        F.col("r.source_status").alias("registry_status"),
        F.when(F.coalesce(F.col("o.observation_count"), F.lit(0)) == 0, "blocked")
         .when(F.col("s.source_id").isNull(), "blocked")
         .when(F.col("r.comparability_status") != "national-comparable", "state-relative-only")
         .otherwise("ready-for-comparison").alias("quality_status"),
        F.when(F.coalesce(F.col("o.observation_count"), F.lit(0)) == 0, "No observations loaded.")
         .when(F.col("s.source_id").isNull(), "Source provenance is not registered.")
         .when(F.col("r.comparability_status") != "national-comparable", "Metric is not approved for national comparison.")
         .otherwise("Source passes current registry checks.").alias("quality_reason"),
        F.current_timestamp().alias("created_at"),
    )
)

snapshot.write.mode("append").saveAsTable("living_index.gold.source_quality_snapshots")
print(f"Quality snapshot written for {snapshot.count()} configured sources; run_id={run_id}")
