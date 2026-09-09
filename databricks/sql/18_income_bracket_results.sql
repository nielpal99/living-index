-- Reusable inspection queries for the national income search surface.
-- The baseline remains configurable through income_baseline_v1 in the view.

-- 1) Coverage and availability by geography.
SELECT geography_type,
       acs_vintage,
       COUNT(*) AS records,
       COUNT_IF(median_household_income IS NOT NULL) AS income_available,
       COUNT_IF(median_household_income IS NULL) AS income_unavailable,
       COUNT_IF(meets_income_v1) AS meeting_v1_baseline,
       ROUND(100.0 * COUNT_IF(median_household_income IS NOT NULL) / COUNT(*), 2)
         AS availability_pct
FROM living_index.gold.income_search
GROUP BY geography_type, acs_vintage
ORDER BY geography_type;

-- 2) Top Census places meeting the $120,000 V1 baseline.
SELECT geography_name,
       state_fips,
       median_household_income,
       income_bracket,
       income_percentile_within_geography,
       total_population,
       acs_vintage
FROM living_index.gold.income_search
WHERE is_city_search_surface = true
  AND meets_income_v1 = true
ORDER BY median_household_income DESC, total_population DESC
LIMIT 100;

-- 3) Counts by bracket, including unavailable values.
SELECT geography_type,
       income_bracket_id,
       income_bracket,
       geography_count,
       city_count,
       is_v1_baseline_bracket
FROM living_index.gold.income_bracket_summary
ORDER BY geography_type, income_bracket_id;
