CREATE OR REPLACE VIEW living_index.gold.district_search AS
WITH district_scores AS (
  SELECT
    nces_district_id,
    max(CASE WHEN upper(test_type) = 'SAT' THEN metric_value END) AS sat_average,
    max(CASE WHEN upper(test_type) = 'ACT' THEN metric_value END) AS act_average,
    max(CASE WHEN upper(test_type) = 'SAT' THEN score_year END) AS sat_data_year,
    max(CASE WHEN upper(test_type) = 'ACT' THEN score_year END) AS act_data_year
  FROM living_index.silver.performance_observations
  WHERE lower(metric_name) = 'average_composite'
    AND source_id = 'georgia_goews_2024_25_scores_crosswalked'
  GROUP BY nces_district_id
), quartiles AS (
  SELECT
    percentile_approx(sat_average, 0.75) AS sat_p75,
    percentile_approx(act_average, 0.75) AS act_p75
  FROM district_scores
)
SELECT
  d.nces_district_id,
  d.district_name,
  d.state_abbr,
  d.enrollment,
  g.median_household_income,
  g.bachelors_or_higher_pct,
  p.sat_average,
  p.act_average,
  p.sat_data_year,
  p.act_data_year,
  CASE WHEN p.sat_average >= q.sat_p75 THEN true ELSE false END AS sat_top_quartile,
  CASE WHEN p.act_average >= q.act_p75 THEN true ELSE false END AS act_top_quartile
FROM living_index.silver.districts d
LEFT JOIN living_index.silver.demographics g
  ON d.census_geoid = g.census_geoid
LEFT JOIN district_scores p
  ON d.nces_district_id = p.nces_district_id
CROSS JOIN quartiles q
WHERE g.median_household_income >= 120000
  AND g.bachelors_or_higher_pct >= 30;
