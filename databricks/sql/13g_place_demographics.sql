-- Descriptive place-demographics layer.
-- Run after the ACS place income/education loads in a Databricks SQL warehouse.
-- These signals are context and search facets only; they are not V1 score inputs.
-- The insert is append-only by Census place GEOID and ACS vintage.

CREATE TABLE IF NOT EXISTS living_index.silver.place_demographics (
  census_geoid STRING,
  geography_type STRING,
  state_fips STRING,
  place_fips STRING,
  geography_name STRING,
  acs_vintage STRING,
  total_population BIGINT,
  white_alone_pct DECIMAL(7,3),
  black_alone_pct DECIMAL(7,3),
  asian_alone_pct DECIMAL(7,3),
  hispanic_or_latino_pct DECIMAL(7,3),
  foreign_born_pct DECIMAL(7,3),
  under_18_pct DECIMAL(7,3),
  source_id STRING,
  loaded_at TIMESTAMP
) USING DELTA;

CREATE OR REPLACE TEMP VIEW place_demographics_raw
USING CSV
OPTIONS (
  path '/Volumes/workspace/default/raw_sources/acs5_place_demographics_2024.csv',
  header 'true',
  inferSchema 'false'
);

INSERT INTO living_index.silver.place_demographics
SELECT
  r.census_geoid,
  r.geography_type,
  r.state_fips,
  nullif(r.place_fips, ''),
  r.geography_name,
  r.acs_vintage,
  try_cast(r.total_population AS BIGINT),
  try_cast(r.white_alone_pct AS DECIMAL(7,3)),
  try_cast(r.black_alone_pct AS DECIMAL(7,3)),
  try_cast(r.asian_alone_pct AS DECIMAL(7,3)),
  try_cast(r.hispanic_or_latino_pct AS DECIMAL(7,3)),
  try_cast(r.foreign_born_pct AS DECIMAL(7,3)),
  try_cast(r.under_18_pct AS DECIMAL(7,3)),
  r.source_id,
  current_timestamp()
FROM place_demographics_raw r
WHERE NOT EXISTS (
  SELECT 1
  FROM living_index.silver.place_demographics x
  WHERE x.census_geoid = r.census_geoid
    AND x.acs_vintage = r.acs_vintage
);

SELECT
  geography_type,
  count(*) AS records,
  count_if(total_population IS NULL) AS missing_population,
  count_if(asian_alone_pct IS NULL) AS missing_asian_pct,
  count_if(hispanic_or_latino_pct IS NULL) AS missing_hispanic_pct,
  count_if(foreign_born_pct IS NULL) AS missing_foreign_born_pct,
  count_if(under_18_pct IS NULL) AS missing_under_18_pct
FROM living_index.silver.place_demographics
GROUP BY geography_type
ORDER BY geography_type;
