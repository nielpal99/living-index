-- Provenance and search surface for the national income layer.

CREATE TABLE IF NOT EXISTS living_index.silver.income_source_registry (
  source_id STRING,
  publisher STRING,
  source_url STRING,
  dataset STRING,
  vintage STRING,
  geography_scope STRING,
  metric_definition STRING,
  unit STRING,
  suppression_definition STRING,
  retrieval_cadence STRING,
  registered_at TIMESTAMP
) USING DELTA;

INSERT INTO living_index.silver.income_source_registry
SELECT source_id, publisher, source_url, dataset, vintage, geography_scope,
       metric_definition, unit, suppression_definition, retrieval_cadence, current_timestamp()
FROM VALUES
 ('acs5_2024_state_income','U.S. Census Bureau','https://api.census.gov/data/2024/acs/acs5','ACS 5-year','2024','state','B19013_001E median household income','USD','-666666666 means unavailable','annual'),
 ('acs5_2024_county_income','U.S. Census Bureau','https://api.census.gov/data/2024/acs/acs5','ACS 5-year','2024','county','B19013_001E median household income','USD','-666666666 means unavailable','annual'),
 ('acs5_2024_place_income','U.S. Census Bureau','https://api.census.gov/data/2024/acs/acs5','ACS 5-year','2024','place','B19013_001E median household income','USD','-666666666 means unavailable','annual')
AS s(source_id,publisher,source_url,dataset,vintage,geography_scope,metric_definition,unit,suppression_definition,retrieval_cadence)
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.income_source_registry x WHERE x.source_id = s.source_id
);

-- User-facing income bands. The $120,000 band is the current V1 baseline;
-- these labels are derived attributes and do not alter the ACS source values.
CREATE TABLE IF NOT EXISTS living_index.gold.income_brackets (
  bracket_id STRING,
  bracket_label STRING,
  lower_bound DECIMAL(18,2),
  upper_bound_exclusive DECIMAL(18,2),
  is_v1_baseline BOOLEAN,
  sort_order INT
) USING DELTA;

MERGE INTO living_index.gold.income_brackets AS target
USING (
  SELECT * FROM VALUES
    ('under_80000', 'Under 80,000', CAST(0.00 AS DECIMAL(18,2)), CAST(80000.00 AS DECIMAL(18,2)), false, 1),
    ('80000_to_119999', '80,000–119,999', CAST(80000.00 AS DECIMAL(18,2)), CAST(120000.00 AS DECIMAL(18,2)), false, 2),
    ('120000_to_149999', '120,000–149,999', CAST(120000.00 AS DECIMAL(18,2)), CAST(150000.00 AS DECIMAL(18,2)), true, 3),
    ('150000_to_199999', '150,000–199,999', CAST(150000.00 AS DECIMAL(18,2)), CAST(200000.00 AS DECIMAL(18,2)), false, 4),
    ('200000_plus', '200,000+', CAST(200000.00 AS DECIMAL(18,2)), CAST(999999999999.99 AS DECIMAL(18,2)), false, 5)
  AS b(bracket_id, bracket_label, lower_bound, upper_bound_exclusive, is_v1_baseline, sort_order)
) AS source
ON target.bracket_id = source.bracket_id
WHEN MATCHED THEN UPDATE SET
  bracket_label = source.bracket_label,
  lower_bound = source.lower_bound,
  upper_bound_exclusive = source.upper_bound_exclusive,
  is_v1_baseline = source.is_v1_baseline,
  sort_order = source.sort_order
WHEN NOT MATCHED THEN INSERT *;

CREATE OR REPLACE VIEW living_index.gold.income_search AS
SELECT
  p.census_geoid, p.geography_type, p.state_fips, p.county_fips, p.place_fips,
  p.geography_name, p.acs_vintage, p.median_household_income, p.total_population,
  p.source_id, p.loaded_at,
  CASE WHEN p.geography_type = 'place' THEN true ELSE false END AS is_city_search_surface,
  120000.00 AS income_baseline_v1,
  CASE WHEN p.median_household_income >= 120000 THEN true ELSE false END AS meets_income_v1,
  CASE WHEN p.median_household_income IS NULL THEN 'unavailable' ELSE 'available' END AS income_availability,
  b.bracket_id AS income_bracket_id,
  b.bracket_label AS income_bracket,
  b.is_v1_baseline AS is_v1_baseline_bracket,
  CASE WHEN p.median_household_income IS NOT NULL THEN
    percent_rank() OVER (PARTITION BY p.geography_type ORDER BY p.median_household_income)
  END AS income_percentile_within_geography
FROM living_index.silver.place_income p
LEFT JOIN living_index.gold.income_brackets b
  ON p.median_household_income >= b.lower_bound
 AND p.median_household_income < b.upper_bound_exclusive;

SELECT geography_type, count(*) AS records,
       count_if(median_household_income >= 120000) AS meeting_income_threshold,
       count_if(median_household_income IS NULL) AS income_unavailable,
       income_bracket,
       count(*) AS records_in_bracket
FROM living_index.gold.income_search
GROUP BY geography_type, income_bracket
ORDER BY geography_type, income_bracket;

CREATE OR REPLACE VIEW living_index.gold.income_bracket_summary AS
SELECT
  geography_type,
  income_bracket_id,
  income_bracket,
  is_v1_baseline_bracket,
  count(*) AS geography_count,
  sum(coalesce(total_population, 0)) AS population_sum,
  avg(median_household_income) AS average_median_household_income,
  min(median_household_income) AS min_median_household_income,
  max(median_household_income) AS max_median_household_income,
  count_if(is_city_search_surface) AS city_count
FROM living_index.gold.income_search
GROUP BY geography_type, income_bracket_id, income_bracket, is_v1_baseline_bracket;
