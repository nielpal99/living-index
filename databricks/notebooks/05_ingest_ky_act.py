"""Load Kentucky's normalized official district ACT observations additively."""

from pyspark.sql import functions as F


SOURCE_PATH = "/Volumes/workspace/default/raw_sources/ky_act_performance_observations.csv"

raw = spark.read.option("header", True).option("inferSchema", False).csv(SOURCE_PATH)

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
        F.current_timestamp().alias("loaded_at"),
    )
    .where(F.col("metric_value").isNotNull())
    .dropDuplicates(["observation_id"])
)

observations.createOrReplaceTempView("ky_observations")
spark.sql("""
INSERT INTO living_index.silver.performance_observations (
  observation_id, nces_school_id, nces_district_id, test_type, metric_name,
  metric_value, score_year, students_tested, participation_rate,
  aggregation_method, source_type, source_id, confidence, notes, loaded_at,
  benchmark_attainment_rate, benchmark_definition, performance_population,
  score_percentile, percentile_scope
)
SELECT k.*, NULL, NULL, NULL, NULL, NULL
FROM ky_observations k
WHERE NOT EXISTS (
  SELECT 1
  FROM living_index.silver.performance_observations p
  WHERE p.observation_id = k.observation_id
)
""")

spark.sql("""
MERGE INTO living_index.silver.sources AS target
USING (SELECT
  'kentucky_act_2024_25_scores' AS source_id,
  'https://www.education.ky.gov/Open-House/data/Pages/Supplemental-Data-Assessment-and-Accountability.aspx' AS source_url,
  'Kentucky Department of Education' AS publisher,
  'official_state_export' AS source_type,
  current_date() AS retrieval_date,
  NULL AS document_hash,
  '2024-25 ACT Average Score workbook; district total rows; grade 11 average score by site.' AS notes
) AS source
ON target.source_id = source.source_id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
""")

spark.sql("""
INSERT INTO living_index.silver.metric_definitions
SELECT * FROM VALUES
 ('ky_act_average_composite_2024_25','average_composite','ACT','ACT composite points',
  'Kentucky grade 11 students represented in the official district-total average; population/window differs from Tennessee.',
  'school_district','2024-25','official district total grade 11 average',
  'state-relative-only','high','kentucky_act_2024_25_scores',
  'Not comparable to Georgia or Tennessee until population and aggregation definitions are aligned.',current_timestamp())
AS m(metric_id, metric_name, test_type, unit, population_definition, geography_level, vintage,
     aggregation_method, comparability_status, confidence_default, source_id, notes, registered_at)
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.metric_definitions d WHERE d.metric_id = m.metric_id
)
""")

spark.sql("""
INSERT INTO living_index.silver.observation_lineage
SELECT * FROM VALUES
 ('performance','kentucky_act_2024_25_scores','current',NULL,
  'Official Kentucky district ACT observations; retained as a separate methodology group.',current_date(),current_timestamp())
AS l(record_scope, source_id, record_status, supersedes_source_id, reason, effective_date, registered_at)
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.observation_lineage x
  WHERE x.record_scope = l.record_scope AND x.source_id = l.source_id
)
""")

print(f"Kentucky ACT observations considered: {observations.count()}")
