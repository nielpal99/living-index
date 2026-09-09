-- V2 descriptive ACS housing context for Census places.
-- Append-only by Census place GEOID and ACS vintage; never overwrite history.

CREATE TABLE IF NOT EXISTS living_index.silver.place_housing_context (
  census_geoid STRING,
  state_fips STRING,
  place_fips STRING,
  geography_name STRING,
  acs_vintage STRING,
  median_home_value BIGINT,
  median_gross_rent BIGINT,
  renter_cost_burden_30_pct_plus DECIMAL(7,1),
  renter_cost_burden_universe BIGINT,
  source_id STRING,
  loaded_at TIMESTAMP
) USING DELTA;

CREATE OR REPLACE TEMP VIEW place_housing_context_raw
USING CSV OPTIONS (
  path '/Volumes/workspace/default/raw_sources/acs5_place_housing_2024.csv',
  header 'true', inferSchema 'false'
);

INSERT INTO living_index.silver.place_housing_context
SELECT
  r.census_geoid,
  r.state_fips,
  nullif(r.place_fips, ''),
  r.geography_name,
  r.acs_vintage,
  try_cast(r.median_home_value AS BIGINT),
  try_cast(r.median_gross_rent AS BIGINT),
  try_cast(r.renter_cost_burden_30_pct_plus AS DECIMAL(7,1)),
  try_cast(r.renter_cost_burden_universe AS BIGINT),
  r.source_id,
  current_timestamp()
FROM place_housing_context_raw r
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.place_housing_context x
  WHERE x.census_geoid = r.census_geoid AND x.acs_vintage = r.acs_vintage
);

SELECT
  count(*) AS place_records,
  count_if(median_home_value IS NULL) AS missing_home_value,
  count_if(median_gross_rent IS NULL) AS missing_rent,
  count_if(renter_cost_burden_30_pct_plus IS NULL) AS missing_cost_burden
FROM living_index.silver.place_housing_context;
