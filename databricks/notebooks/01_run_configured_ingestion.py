"""Run all configured normalized-source adapters additively.

This notebook is intended to be the single ingestion task in a Databricks
Workflow. Source-specific normalization happens upstream; this task owns
validation, deduplication, lineage-safe append, and quality snapshots.
"""

from pyspark.sql import functions as F


run_id = spark.sql("SELECT current_timestamp() AS ts").first()["ts"]

registry = spark.table("living_index.silver.source_registry").where(
    "active_flag = true AND source_status = 'loaded' "
    "AND loader_key = 'state_csv_adapter' AND source_path IS NOT NULL"
).collect()

spark.sql("""
CREATE TABLE IF NOT EXISTS living_index.gold.pipeline_runs (
  run_id TIMESTAMP,
  source_id STRING,
  status STRING,
  rows_seen BIGINT,
  rows_inserted BIGINT,
  rows_rejected BIGINT,
  reason STRING,
  created_at TIMESTAMP
) USING DELTA
""")

spark.sql("""
CREATE TABLE IF NOT EXISTS living_index.silver.source_file_manifest (
  manifest_id STRING,
  source_id STRING,
  source_url STRING,
  source_path STRING,
  publisher STRING,
  retrieved_at TIMESTAMP,
  score_year STRING,
  file_format STRING,
  byte_count BIGINT,
  sha256 STRING,
  content_type STRING,
  record_count BIGINT,
  manifest_status STRING,
  notes STRING
) USING DELTA
""")

for source in registry:
    source_id = source["source_id"]
    try:
        raw = spark.read.option("header", True).option("inferSchema", False).csv(source["source_path"])
        raw_count = raw.count()
        required = {
            "observation_id", "nces_district_id", "test_type", "metric_name",
            "metric_value", "score_year", "students_tested", "participation_rate",
            "aggregation_method", "source_type", "source_id", "confidence",
        }
        missing = sorted(required - set(raw.columns))
        if missing:
            raise ValueError(f"missing columns: {','.join(missing)}")

        prepared = raw.select(
            F.col("observation_id").cast("string"),
            F.lit(None).cast("string").alias("nces_school_id"),
            F.col("nces_district_id").cast("string"),
            F.col("test_type").cast("string"),
            F.col("metric_name").cast("string"),
            F.expr("try_cast(metric_value AS DECIMAL(12,3))").alias("metric_value"),
            F.col("score_year").cast("string"),
            F.expr("try_cast(students_tested AS BIGINT)").alias("students_tested"),
            F.expr("try_cast(participation_rate AS DECIMAL(7,3))").alias("participation_rate"),
            F.col("aggregation_method").cast("string"),
            F.col("source_type").cast("string"),
            F.lit(source_id).alias("source_id"),
            F.col("confidence").cast("string"),
            F.col("notes").cast("string"),
            F.lit(None).cast("decimal(7,3)").alias("benchmark_attainment_rate"),
            F.lit(None).cast("string").alias("benchmark_definition"),
            F.col("performance_population").cast("string") if "performance_population" in raw.columns else F.lit(None).cast("string").alias("performance_population"),
            F.lit(None).cast("decimal(7,5)").alias("score_percentile"),
            F.lit(None).cast("string").alias("percentile_scope"),
            F.current_timestamp().alias("loaded_at"),
        ).where(
            (F.col("source_id") == source_id) &
            F.col("nces_district_id").isNotNull() &
            F.col("metric_value").isNotNull() &
            F.col("test_type").isin("SAT", "ACT")
        ).dropDuplicates(["observation_id"])

        prepared.createOrReplaceTempView("configured_source_rows")

        # Capture the exact artifact used by this run. The manifest is
        # append-only and keyed by content hash, so reruns do not overwrite
        # source history.
        try:
            artifact = spark.read.format("binaryFile").load(source["source_path"]).select(
                F.sum("length").cast("long").alias("byte_count"),
                F.sha2(F.concat_ws("", F.collect_list(F.base64("content"))), 256).alias("sha256"),
            ).first()
            byte_count, sha256 = artifact["byte_count"], artifact["sha256"]
        except Exception:
            byte_count, sha256 = None, None
        manifest_id = f"{source_id}:{sha256 or run_id.isoformat()}"
        manifest_row = spark.createDataFrame(
            [(manifest_id, source_id, source["source_url"], source["source_path"], source["publisher"],
              run_id, source["score_year"], source["file_format"], byte_count, sha256, "text/csv",
              raw_count, "loaded", "Manifest captured by configured ingestion run.")],
            "manifest_id string, source_id string, source_url string, source_path string, publisher string, "
            "retrieved_at timestamp, score_year string, file_format string, byte_count long, sha256 string, "
            "content_type string, record_count long, manifest_status string, notes string",
        )
        manifest_row.createOrReplaceTempView("configured_source_manifest")
        spark.sql("""
        INSERT INTO living_index.silver.source_file_manifest
        SELECT m.* FROM configured_source_manifest m
        WHERE NOT EXISTS (
          SELECT 1 FROM living_index.silver.source_file_manifest x
          WHERE x.manifest_id = m.manifest_id
        )
        """)
        before = spark.table("living_index.silver.performance_observations").where(F.col("source_id") == source_id).count()
        spark.sql("""
        INSERT INTO living_index.silver.performance_observations (
          observation_id,nces_school_id,nces_district_id,test_type,metric_name,
          metric_value,score_year,students_tested,participation_rate,
          aggregation_method,source_type,source_id,confidence,notes,
          benchmark_attainment_rate,benchmark_definition,performance_population,
          score_percentile,percentile_scope,loaded_at
        )
        SELECT k.* FROM configured_source_rows k
        WHERE NOT EXISTS (
          SELECT 1 FROM living_index.silver.performance_observations p
          WHERE p.observation_id = k.observation_id
        )
        """)
        after = spark.table("living_index.silver.performance_observations").where(F.col("source_id") == source_id).count()
        spark.createDataFrame([(run_id, source_id, "success", raw_count, after - before, raw_count - prepared.count(), None, run_id)],
                              "run_id timestamp, source_id string, status string, rows_seen long, rows_inserted long, rows_rejected long, reason string, created_at timestamp") \
            .write.mode("append").saveAsTable("living_index.gold.pipeline_runs")
    except Exception as exc:
        spark.createDataFrame([(run_id, source_id, "failed", 0, 0, 0, str(exc)[:4000], run_id)],
                              "run_id timestamp, source_id string, status string, rows_seen long, rows_inserted long, rows_rejected long, reason string, created_at timestamp") \
            .write.mode("append").saveAsTable("living_index.gold.pipeline_runs")
        raise

print(f"Configured ingestion completed for {len(registry)} source(s); run_id={run_id}")
