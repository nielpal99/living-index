-- State, county, and Census-place income layer.

CREATE TABLE IF NOT EXISTS living_index.silver.place_income (
  census_geoid STRING, geography_type STRING, state_fips STRING, county_fips STRING,
  place_fips STRING, geography_name STRING, acs_vintage STRING,
  median_household_income DECIMAL(18,2), total_population BIGINT, source_id STRING,
  loaded_at TIMESTAMP
) USING DELTA;

-- Read the validated public extract with an explicit cast into the canonical
-- schema. The anti-join preserves historical rows and makes reruns idempotent.
CREATE OR REPLACE TEMP VIEW place_income_raw
USING CSV
OPTIONS (
  path '/Volumes/workspace/default/raw_sources/acs5_place_income_2024.csv',
  header 'true',
  inferSchema 'false'
);

INSERT INTO living_index.silver.place_income
SELECT
  r.census_geoid,
  r.geography_type,
  r.state_fips,
  nullif(r.county_fips, ''),
  nullif(r.place_fips, ''),
  r.geography_name,
  r.acs_vintage,
  try_cast(r.median_household_income AS DECIMAL(18,2)),
  try_cast(r.total_population AS BIGINT),
  r.source_id,
  current_timestamp()
FROM place_income_raw r
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.place_income x
  WHERE x.census_geoid = r.census_geoid AND x.acs_vintage = r.acs_vintage
);

CREATE OR REPLACE VIEW living_index.gold.us_income_index AS
SELECT census_geoid, geography_type, state_fips, county_fips, place_fips,
       geography_name, acs_vintage, median_household_income, total_population,
       source_id, loaded_at,
       percent_rank() OVER (PARTITION BY geography_type ORDER BY median_household_income)
         AS income_percentile_scope,
       CASE WHEN geography_type = 'place' THEN 'census_place' ELSE geography_type END AS place_scope
FROM living_index.silver.place_income
WHERE median_household_income IS NOT NULL;

SELECT geography_type, count(*) AS records,
       count_if(median_household_income IS NULL) AS missing_income,
       min(median_household_income) AS min_income,
       max(median_household_income) AS max_income
FROM living_index.silver.place_income
GROUP BY geography_type
ORDER BY geography_type;
