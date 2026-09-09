-- Place-level bachelor's attainment layer.
-- Run after 13_place_income.sql in a Databricks SQL warehouse.
-- The insert is append-only by Census place GEOID and ACS vintage.

CREATE TABLE IF NOT EXISTS living_index.silver.place_education (
  census_geoid STRING,
  geography_type STRING,
  state_fips STRING,
  county_fips STRING,
  place_fips STRING,
  geography_name STRING,
  acs_vintage STRING,
  education_universe_25_plus BIGINT,
  bachelors_or_higher_count BIGINT,
  bachelors_or_higher_pct DECIMAL(7,3),
  source_id STRING,
  loaded_at TIMESTAMP
) USING DELTA;

CREATE OR REPLACE TEMP VIEW place_education_raw
USING CSV
OPTIONS (
  path '/Volumes/workspace/default/raw_sources/acs5_place_education_2024.csv',
  header 'true',
  inferSchema 'false'
);

INSERT INTO living_index.silver.place_education
SELECT
  r.census_geoid,
  r.geography_type,
  r.state_fips,
  nullif(r.county_fips, ''),
  nullif(r.place_fips, ''),
  r.geography_name,
  r.acs_vintage,
  try_cast(r.education_universe_25_plus AS BIGINT),
  try_cast(r.bachelors_or_higher_count AS BIGINT),
  try_cast(r.bachelors_or_higher_pct AS DECIMAL(7,3)),
  r.source_id,
  current_timestamp()
FROM place_education_raw r
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.place_education x
  WHERE x.census_geoid = r.census_geoid AND x.acs_vintage = r.acs_vintage
);

SELECT geography_type,
       count(*) AS records,
       count_if(bachelors_or_higher_pct IS NULL) AS missing_education,
       min(bachelors_or_higher_pct) AS min_pct,
       max(bachelors_or_higher_pct) AS max_pct
FROM living_index.silver.place_education
GROUP BY geography_type
ORDER BY geography_type;
