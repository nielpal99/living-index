-- Current-record selection and explicit score eligibility gates.
-- Historical observations remain untouched.

CREATE OR REPLACE VIEW living_index.silver.current_performance_observations AS
WITH ranked AS (
  SELECT
    p.*,
    row_number() OVER (
      PARTITION BY p.nces_district_id, upper(p.test_type), p.score_year
      ORDER BY p.loaded_at DESC, p.observation_id DESC
    ) AS rn
  FROM living_index.silver.performance_observations p
  LEFT JOIN living_index.silver.observation_lineage l
    ON l.record_scope = 'performance' AND l.source_id = p.source_id
  WHERE coalesce(l.record_status, 'current') <> 'superseded'
)
SELECT * FROM ranked WHERE rn = 1;

CREATE OR REPLACE VIEW living_index.gold.performance_score_quality AS
SELECT
  p.observation_id,
  p.nces_district_id,
  p.test_type,
  p.metric_value,
  p.score_year,
  p.students_tested,
  p.participation_rate,
  p.source_id,
  p.confidence,
  CASE WHEN p.metric_value IS NULL THEN 'blocked_missing_score'
       WHEN p.students_tested IS NULL OR p.students_tested < 30 THEN 'warning_small_or_missing_sample'
       WHEN p.participation_rate IS NULL THEN 'warning_missing_participation'
       WHEN p.confidence NOT IN ('high','medium') THEN 'warning_low_confidence'
       ELSE 'eligible' END AS quality_status,
  CASE WHEN p.metric_value IS NOT NULL
         AND p.students_tested >= 30
         AND p.confidence IN ('high','medium')
       THEN true ELSE false END AS score_eligible,
  CASE WHEN datediff(current_date(), s.retrieval_date) > 730 THEN true ELSE false END AS stale_source_flag
FROM living_index.silver.current_performance_observations p
LEFT JOIN living_index.silver.sources s ON s.source_id = p.source_id;

SELECT quality_status, count(*) AS observations
FROM living_index.gold.performance_score_quality
GROUP BY quality_status
ORDER BY quality_status;
