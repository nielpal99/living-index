-- V1 configurable scoring layer.
-- Raw metrics remain in silver; this layer only defines transparent rankings.

CREATE TABLE IF NOT EXISTS living_index.gold.scoring_profiles (
  profile_id STRING,
  profile_name STRING,
  academic_weight DECIMAL(6,3),
  community_weight DECIMAL(6,3),
  income_weight DECIMAL(6,3),
  education_weight DECIMAL(6,3),
  income_minimum DECIMAL(18,2),
  education_minimum DECIMAL(7,3),
  active_flag BOOLEAN,
  notes STRING,
  created_at TIMESTAMP
) USING DELTA;

MERGE INTO living_index.gold.scoring_profiles AS target
USING (
  SELECT
    'default_v1' AS profile_id,
    'Academic-forward V1' AS profile_name,
    CAST(0.600 AS DECIMAL(6,3)) AS academic_weight,
    CAST(0.400 AS DECIMAL(6,3)) AS community_weight,
    CAST(0.500 AS DECIMAL(6,3)) AS income_weight,
    CAST(0.500 AS DECIMAL(6,3)) AS education_weight,
    CAST(120000.00 AS DECIMAL(18,2)) AS income_minimum,
    CAST(30.000 AS DECIMAL(7,3)) AS education_minimum,
    true AS active_flag,
    'Initial personal profile; later users can create their own weights.' AS notes,
    current_timestamp() AS created_at
) AS source
ON target.profile_id = source.profile_id
WHEN MATCHED THEN UPDATE SET
  profile_name = source.profile_name,
  academic_weight = source.academic_weight,
  community_weight = source.community_weight,
  income_weight = source.income_weight,
  education_weight = source.education_weight,
  income_minimum = source.income_minimum,
  education_minimum = source.education_minimum,
  active_flag = source.active_flag,
  notes = source.notes
WHEN NOT MATCHED THEN INSERT *;

CREATE OR REPLACE VIEW living_index.gold.district_rankings AS
WITH profile AS (
  SELECT *
  FROM living_index.gold.scoring_profiles
  WHERE profile_id = 'default_v1' AND active_flag = true
),
performance AS (
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
),
academic_ranked AS (
  SELECT
    coalesce(s.nces_district_id, a.nces_district_id) AS nces_district_id,
    s.sat_average,
    a.act_average,
    s.sat_data_year,
    a.act_data_year,
    s.sat_percentile,
    a.act_percentile
  FROM (
    SELECT
      nces_district_id,
      sat_average,
      sat_data_year,
      percent_rank() OVER (ORDER BY sat_average) AS sat_percentile
    FROM performance
    WHERE sat_average IS NOT NULL
  ) s
  FULL OUTER JOIN (
    SELECT
      nces_district_id,
      act_average,
      act_data_year,
      percent_rank() OVER (ORDER BY act_average) AS act_percentile
    FROM performance
    WHERE act_average IS NOT NULL
  ) a
    ON s.nces_district_id = a.nces_district_id
),
community_ranked AS (
  SELECT
    d.nces_district_id,
    d.district_name,
    d.state_abbr,
    d.enrollment,
    g.median_household_income,
    g.bachelors_or_higher_pct,
    a.sat_average,
    a.act_average,
    a.sat_data_year,
    a.act_data_year,
    a.sat_percentile,
    a.act_percentile,
    CASE
      WHEN a.sat_percentile IS NOT NULL AND a.act_percentile IS NOT NULL
        THEN (a.sat_percentile + a.act_percentile) / 2.0
      ELSE coalesce(a.sat_percentile, a.act_percentile)
    END AS academic_score,
    percent_rank() OVER (ORDER BY g.median_household_income) AS income_percentile,
    percent_rank() OVER (ORDER BY g.bachelors_or_higher_pct) AS education_percentile
  FROM living_index.silver.districts d
  LEFT JOIN living_index.silver.demographics g
    ON d.census_geoid = g.census_geoid
  LEFT JOIN academic_ranked a
    ON d.nces_district_id = a.nces_district_id
),
scored AS (
  SELECT
    c.*,
    (c.income_percentile * p.income_weight
      + c.education_percentile * p.education_weight) AS community_score,
    p.academic_weight,
    p.community_weight,
    p.income_minimum,
    p.education_minimum,
    p.profile_id,
    CASE
      WHEN c.academic_score IS NOT NULL
        THEN c.academic_score * p.academic_weight
          + (c.income_percentile * p.income_weight
            + c.education_percentile * p.education_weight) * p.community_weight
    END AS overall_score,
    CASE
      WHEN c.sat_average IS NOT NULL AND c.act_average IS NOT NULL THEN 'high'
      WHEN c.sat_average IS NOT NULL OR c.act_average IS NOT NULL THEN 'medium'
      ELSE 'low'
    END AS academic_data_confidence
  FROM community_ranked c
  CROSS JOIN profile p
)
SELECT
  *,
  CASE WHEN median_household_income >= income_minimum
    AND bachelors_or_higher_pct >= education_minimum THEN true ELSE false END
    AS meets_community_thresholds,
  CASE WHEN median_household_income >= income_minimum
    AND bachelors_or_higher_pct >= education_minimum
    AND academic_score IS NOT NULL THEN true ELSE false END
    AS eligible_for_default_v1
FROM scored;
