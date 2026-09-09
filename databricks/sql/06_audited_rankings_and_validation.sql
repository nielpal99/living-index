-- Additive audit-safe ranking layer.
-- This does not delete or overwrite silver observations or historical source rows.

CREATE OR REPLACE VIEW living_index.gold.district_rankings_audited AS
WITH source_scope AS (
  SELECT DISTINCT source_id, state_abbr, test_type, score_year,
    comparable_to_ga, comparability_status
  FROM living_index.gold.performance_metric_registry
),
district_scores AS (
  SELECT
    d.nces_district_id,
    d.district_name,
    d.state_abbr,
    d.enrollment,
    g.median_household_income,
    g.bachelors_or_higher_pct,
    max(CASE WHEN upper(p.test_type) = 'SAT' THEN p.metric_value END) AS sat_average,
    max(CASE WHEN upper(p.test_type) = 'ACT' THEN p.metric_value END) AS act_average,
    max(CASE WHEN upper(p.test_type) = 'SAT' THEN p.score_year END) AS sat_data_year,
    max(CASE WHEN upper(p.test_type) = 'ACT' THEN p.score_year END) AS act_data_year,
    max(CASE WHEN upper(p.test_type) = 'SAT' THEN p.students_tested END) AS sat_students_tested,
    max(CASE WHEN upper(p.test_type) = 'ACT' THEN p.students_tested END) AS act_students_tested,
    max(CASE WHEN upper(p.test_type) = 'SAT' THEN p.participation_rate END) AS sat_participation_rate,
    max(CASE WHEN upper(p.test_type) = 'ACT' THEN p.participation_rate END) AS act_participation_rate,
    max(CASE WHEN upper(p.test_type) = 'SAT' THEN s.comparability_status END) AS sat_comparability_status,
    max(CASE WHEN upper(p.test_type) = 'ACT' THEN s.comparability_status END) AS act_comparability_status,
    count(DISTINCT CASE WHEN upper(p.test_type) = 'SAT' THEN p.source_id END) AS sat_source_count,
    count(DISTINCT CASE WHEN upper(p.test_type) = 'ACT' THEN p.source_id END) AS act_source_count
  FROM living_index.silver.districts d
  LEFT JOIN living_index.silver.demographics g ON d.census_geoid = g.census_geoid
  LEFT JOIN living_index.silver.performance_observations p
    ON d.nces_district_id = p.nces_district_id
   AND lower(p.metric_name) = 'average_composite'
   AND p.source_id IN (SELECT source_id FROM source_scope)
  LEFT JOIN source_scope s
    ON p.source_id = s.source_id AND upper(p.test_type) = upper(s.test_type)
  GROUP BY d.nces_district_id, d.district_name, d.state_abbr, d.enrollment,
    g.median_household_income, g.bachelors_or_higher_pct
),
-- Rank only observed values. Window functions over the full district universe
-- would include NULLs in the denominator and understate every percentile.
sat_percentiles AS (
  SELECT nces_district_id,
         percent_rank() OVER (PARTITION BY state_abbr ORDER BY sat_average)
           AS sat_percentile_state_relative
  FROM district_scores
  WHERE sat_average IS NOT NULL
),
act_percentiles AS (
  SELECT nces_district_id,
         percent_rank() OVER (PARTITION BY state_abbr ORDER BY act_average)
           AS act_percentile_state_relative
  FROM district_scores
  WHERE act_average IS NOT NULL
),
income_percentiles AS (
  SELECT nces_district_id,
         percent_rank() OVER (ORDER BY median_household_income) AS income_percentile
  FROM district_scores
  WHERE median_household_income IS NOT NULL
),
education_percentiles AS (
  SELECT nces_district_id,
         percent_rank() OVER (ORDER BY bachelors_or_higher_pct) AS education_percentile
  FROM district_scores
  WHERE bachelors_or_higher_pct IS NOT NULL
),
state_percentiles AS (
  SELECT d.*, s.sat_percentile_state_relative, a.act_percentile_state_relative,
         i.income_percentile, e.education_percentile
  FROM district_scores d
  LEFT JOIN sat_percentiles s USING (nces_district_id)
  LEFT JOIN act_percentiles a USING (nces_district_id)
  LEFT JOIN income_percentiles i USING (nces_district_id)
  LEFT JOIN education_percentiles e USING (nces_district_id)
),
coverage AS (
  SELECT count(DISTINCT state_abbr) AS states_with_performance
  FROM district_scores
  WHERE sat_average IS NOT NULL OR act_average IS NOT NULL
),
national_percentiles AS (
  SELECT
    nces_district_id,
    CASE WHEN sat_average IS NOT NULL AND sat_comparability_status = 'national_comparable'
      THEN percent_rank() OVER (ORDER BY sat_average) END AS sat_percentile_national,
    CASE WHEN act_average IS NOT NULL AND act_comparability_status = 'national_comparable'
      THEN percent_rank() OVER (ORDER BY act_average) END AS act_percentile_national
  FROM state_percentiles
),
scored AS (
  SELECT
    s.*,
    n.sat_percentile_national,
    n.act_percentile_national,
    CASE
      WHEN s.sat_percentile_state_relative IS NOT NULL
       AND s.act_percentile_state_relative IS NOT NULL
        THEN (s.sat_percentile_state_relative + s.act_percentile_state_relative) / 2.0
      ELSE coalesce(s.sat_percentile_state_relative, s.act_percentile_state_relative)
    END AS academic_score,
    CASE WHEN s.income_percentile IS NOT NULL AND s.education_percentile IS NOT NULL
      THEN (s.income_percentile + s.education_percentile) / 2.0
      ELSE coalesce(s.income_percentile, s.education_percentile) END AS community_score,
    c.states_with_performance,
    CASE WHEN c.states_with_performance >= 10
      AND (n.sat_percentile_national IS NOT NULL OR n.act_percentile_national IS NOT NULL)
      THEN 'national-relative' ELSE 'state-relative' END AS percentile_scope,
    concat(s.state_abbr, ':state-relative') AS ranking_group,
    CASE
      WHEN c.states_with_performance = 1 THEN true
      WHEN c.states_with_performance >= 10
       AND (n.sat_percentile_national IS NOT NULL OR n.act_percentile_national IS NOT NULL)
        THEN true
      ELSE false
    END AS combined_ranking_eligible,
    CASE
      WHEN s.sat_average IS NOT NULL AND s.act_average IS NOT NULL
       AND coalesce(s.sat_students_tested,0) >= 30
       AND coalesce(s.act_students_tested,0) >= 30 THEN 'high'
      WHEN s.sat_average IS NOT NULL OR s.act_average IS NOT NULL THEN 'medium'
      ELSE 'low'
    END AS academic_data_confidence
  FROM state_percentiles s
  CROSS JOIN coverage c
  LEFT JOIN national_percentiles n ON s.nces_district_id = n.nces_district_id
),
final AS (
  SELECT
    *,
    academic_score - community_score AS academic_community_gap,
    greatest(sat_data_year, act_data_year) AS performance_data_year,
    academic_score * 0.600 + community_score * 0.400 AS overall_score
  FROM scored
)
SELECT
  *,
  CASE WHEN median_household_income >= 120000
    AND bachelors_or_higher_pct >= 30 THEN true ELSE false END
    AS meets_community_thresholds,
  CASE WHEN median_household_income >= 120000
    AND bachelors_or_higher_pct >= 30
    AND academic_score IS NOT NULL THEN true ELSE false END
    AS eligible_for_default_v1
FROM final;

-- 1. Observations by state, source, test, and year.
SELECT d.state_abbr, p.source_id, p.test_type, p.score_year,
       count(*) AS observations, count(DISTINCT p.nces_district_id) AS districts,
       min(p.metric_value) AS min_score, max(p.metric_value) AS max_score,
       avg(p.students_tested) AS avg_students_tested,
       avg(p.participation_rate) AS avg_participation_rate
FROM living_index.silver.performance_observations p
LEFT JOIN living_index.silver.districts d ON p.nces_district_id = d.nces_district_id
GROUP BY d.state_abbr, p.source_id, p.test_type, p.score_year
ORDER BY d.state_abbr, p.test_type, p.source_id, p.score_year;

-- 2. Metric-definition and comparability differences.
SELECT *
FROM living_index.gold.performance_metric_registry
ORDER BY test_type, state_abbr, score_year;

-- 3. District coverage: SAT, ACT, both, or neither.
SELECT
  CASE WHEN sat_average IS NOT NULL AND act_average IS NOT NULL THEN 'both'
       WHEN sat_average IS NOT NULL THEN 'SAT only'
       WHEN act_average IS NOT NULL THEN 'ACT only'
       ELSE 'neither' END AS performance_coverage,
  state_abbr, count(*) AS districts
FROM living_index.gold.district_rankings_audited
GROUP BY 1, 2
ORDER BY state_abbr, performance_coverage;

-- 4. State-relative and national-relative percentile cutoffs.
SELECT percentile_scope, state_abbr,
       percentile_approx(sat_percentile_state_relative, 0.75) AS sat_p75_percentile,
       percentile_approx(act_percentile_state_relative, 0.75) AS act_p75_percentile,
       max(sat_percentile_national) AS national_sat_percentile_available,
       max(act_percentile_national) AS national_act_percentile_available
FROM living_index.gold.district_rankings_audited
GROUP BY percentile_scope, state_abbr;

-- 5. Top qualifying districts.
SELECT district_name, state_abbr, overall_score, academic_score, community_score,
       academic_community_gap, performance_data_year, academic_data_confidence,
       median_household_income, bachelors_or_higher_pct, percentile_scope
FROM living_index.gold.district_rankings_audited
WHERE eligible_for_default_v1 = true
ORDER BY state_abbr, overall_score DESC
LIMIT 100;

-- 5b. Cross-state ranking is intentionally empty until comparability and coverage pass.
SELECT district_name, state_abbr, overall_score, ranking_group,
       combined_ranking_eligible, percentile_scope
FROM living_index.gold.district_rankings_audited
WHERE eligible_for_default_v1 = true
  AND combined_ranking_eligible = true
ORDER BY overall_score DESC
LIMIT 100;

-- 6. Largest positive and negative academic-community gaps.
SELECT district_name, state_abbr, academic_community_gap,
       academic_score, community_score, overall_score,
       median_household_income, bachelors_or_higher_pct
FROM living_index.gold.district_rankings_audited
WHERE academic_score IS NOT NULL
ORDER BY academic_community_gap DESC
LIMIT 25;

SELECT district_name, state_abbr, academic_community_gap,
       academic_score, community_score, overall_score,
       median_household_income, bachelors_or_higher_pct
FROM living_index.gold.district_rankings_audited
WHERE academic_score IS NOT NULL
ORDER BY academic_community_gap ASC
LIMIT 25;

-- 7. Missing enrollment, participation, and sample-size fields.
SELECT
  d.state_abbr,
  count_if(d.enrollment IS NULL) AS districts_missing_enrollment,
  count_if(p.participation_rate IS NULL) AS observations_missing_participation,
  count_if(p.students_tested IS NULL) AS observations_missing_sample_size,
  count(*) AS observations
FROM living_index.silver.performance_observations p
LEFT JOIN living_index.silver.districts d ON p.nces_district_id = d.nces_district_id
GROUP BY d.state_abbr
ORDER BY d.state_abbr;
