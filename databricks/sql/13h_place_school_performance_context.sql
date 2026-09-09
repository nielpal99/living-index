-- Append-only context join between Census-place spatial overlaps and loaded
-- district performance observations. Do not use this table as an attendance-
-- boundary assignment or to calculate a single place-level score.

CREATE TABLE IF NOT EXISTS living_index.silver.place_school_performance_context (
  place_geoid STRING,
  place_name STRING,
  state_fips STRING,
  district_geoid STRING,
  district_name STRING,
  place_area_share_pct DECIMAL(7,3),
  crosswalk_method STRING,
  crosswalk_confidence STRING,
  crosswalk_validation_status STRING,
  test_type STRING,
  metric_name STRING,
  metric_value DECIMAL(10,3),
  score_year STRING,
  students_tested BIGINT,
  participation_rate DECIMAL(7,3),
  aggregation_method STRING,
  source_type STRING,
  source_id STRING,
  performance_confidence STRING,
  performance_notes STRING,
  loaded_at TIMESTAMP
) USING DELTA;

CREATE OR REPLACE TEMP VIEW place_school_performance_context_raw
USING CSV
OPTIONS (
  path '/Volumes/workspace/default/raw_sources/place_school_performance_context_2024_25.csv',
  header 'true',
  inferSchema 'false'
);

INSERT INTO living_index.silver.place_school_performance_context
SELECT
  r.place_geoid,
  r.place_name,
  r.state_fips,
  r.district_geoid,
  r.district_name,
  try_cast(r.place_area_share_pct AS DECIMAL(7,3)),
  r.crosswalk_method,
  r.crosswalk_confidence,
  r.crosswalk_validation_status,
  upper(r.test_type),
  r.metric_name,
  try_cast(r.metric_value AS DECIMAL(10,3)),
  r.score_year,
  try_cast(nullif(r.students_tested, '') AS BIGINT),
  try_cast(nullif(r.participation_rate, '') AS DECIMAL(7,3)),
  r.aggregation_method,
  r.source_type,
  r.source_id,
  r.performance_confidence,
  r.performance_notes,
  current_timestamp()
FROM place_school_performance_context_raw r
WHERE NOT EXISTS (
  SELECT 1
  FROM living_index.silver.place_school_performance_context x
  WHERE x.place_geoid = r.place_geoid
    AND x.district_geoid = r.district_geoid
    AND x.test_type = upper(r.test_type)
    AND x.score_year = r.score_year
    AND x.source_id = r.source_id
);

SELECT
  state_fips,
  test_type,
  score_year,
  count(*) AS context_rows,
  count(DISTINCT place_geoid) AS places,
  count(DISTINCT district_geoid) AS districts,
  count_if(students_tested IS NULL) AS missing_students_tested,
  count_if(participation_rate IS NULL) AS missing_participation_rate,
  count_if(crosswalk_confidence = 'low') AS low_confidence_spatial_links
FROM living_index.silver.place_school_performance_context
GROUP BY state_fips, test_type, score_year
ORDER BY state_fips, test_type, score_year;
