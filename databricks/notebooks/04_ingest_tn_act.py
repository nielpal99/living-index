"""Load normalized Tennessee ACT observations from the managed volume."""

from pyspark.sql import functions as F


SOURCE_PATH = "/Volumes/workspace/default/raw_sources/tn_act_performance_observations.csv"

raw = (
    spark.read
    .option("header", True)
    .option("inferSchema", True)
    .csv(SOURCE_PATH)
)

observations = (
    raw.select(
        "observation_id",
        F.lit(None).cast("string").alias("nces_school_id"),
        F.col("nces_district_id").cast("string"),
        F.col("test_type").cast("string"),
        F.col("metric_name").cast("string"),
        F.col("metric_value").cast("decimal(12,3)"),
        F.col("score_year").cast("string"),
        F.col("students_tested").cast("bigint"),
        F.col("participation_rate").cast("decimal(7,3)"),
        F.col("aggregation_method").cast("string"),
        F.col("source_type").cast("string"),
        F.col("source_id").cast("string"),
        F.col("confidence").cast("string"),
        F.col("notes").cast("string"),
        F.lit(None).cast("decimal(7,3)").alias("benchmark_attainment_rate"),
        F.lit(None).cast("string").alias("benchmark_definition"),
        F.lit(None).cast("string").alias("performance_population"),
        F.lit(None).cast("decimal(7,5)").alias("score_percentile"),
        F.lit(None).cast("string").alias("percentile_scope"),
        F.current_timestamp().alias("loaded_at"),
    )
    .dropDuplicates(["observation_id"])
)

(
    observations.write
    .mode("append")
    .option("mergeSchema", "false")
    .saveAsTable("living_index.silver.performance_observations")
)

spark.sql("""
MERGE INTO living_index.silver.sources AS target
USING (
  SELECT
    'tennessee_act_2024_25_scores' AS source_id,
    'https://www.tn.gov/education/districts/federal-programs-and-oversight/data/data-downloads.html' AS source_url,
    'Tennessee Department of Education' AS publisher,
    'official_state_export' AS source_type,
    current_date() AS retrieval_date,
    NULL AS document_hash,
    '2024-25 district ACT file; All Students; highest scores in the three years preceding graduation.' AS notes
) AS source
ON target.source_id = source.source_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
""")

print(f"Tennessee ACT observations written: {observations.count()}")
