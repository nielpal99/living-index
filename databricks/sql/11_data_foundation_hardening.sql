-- Append-only manifests and enrollment snapshots for reproducible coverage.

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
) USING DELTA;

CREATE TABLE IF NOT EXISTS living_index.silver.district_enrollment_snapshots (
  snapshot_id STRING,
  nces_district_id STRING,
  state_abbr STRING,
  enrollment BIGINT,
  enrollment_year STRING,
  source_id STRING,
  retrieved_at TIMESTAMP,
  geographic_precision STRING,
  suppression_flag BOOLEAN,
  notes STRING
) USING DELTA;

CREATE OR REPLACE VIEW living_index.gold.current_district_enrollment AS
SELECT *
FROM (
  SELECT e.*, row_number() OVER (
    PARTITION BY nces_district_id ORDER BY enrollment_year DESC, retrieved_at DESC
  ) AS rn
  FROM living_index.silver.district_enrollment_snapshots e
  WHERE suppression_flag = false AND enrollment IS NOT NULL
)
WHERE rn = 1;

CREATE OR REPLACE VIEW living_index.gold.data_foundation_coverage AS
SELECT
  d.state_abbr,
  count(*) AS district_count,
  count_if(e.nces_district_id IS NOT NULL) AS districts_with_enrollment,
  round(100.0 * count_if(e.nces_district_id IS NOT NULL) / count(*), 2) AS enrollment_coverage_pct,
  count_if(d.census_geoid IS NULL) AS districts_missing_census_geoid,
  count_if(d.district_name IS NULL) AS districts_missing_name
FROM living_index.silver.districts d
LEFT JOIN living_index.gold.current_district_enrollment e
  ON d.nces_district_id = e.nces_district_id
GROUP BY d.state_abbr;

SELECT * FROM living_index.gold.data_foundation_coverage ORDER BY state_abbr;
