-- Formal comparability groups and an explicit national-ranking readiness gate.

CREATE TABLE IF NOT EXISTS living_index.silver.metric_comparability_groups (
  comparability_group STRING,
  test_type STRING,
  required_population_definition STRING,
  required_aggregation_method STRING,
  minimum_states INT,
  minimum_participation_coverage_pct DECIMAL(7,2),
  approved_for_national_ranking BOOLEAN,
  rationale STRING,
  registered_at TIMESTAMP
) USING DELTA;

INSERT INTO living_index.silver.metric_comparability_groups
SELECT comparability_group, test_type, required_population_definition,
       required_aggregation_method, minimum_states,
       minimum_participation_coverage_pct, approved_for_national_ranking,
       rationale, current_timestamp()
FROM VALUES
 ('national_act_comparable','ACT','Same student population and score window across states',
  'Same official district aggregation rule',10,80.00,false,
  'National ranking requires sufficient state coverage and participation metadata.'),
 ('national_sat_comparable','SAT','Same student population and SAT version/vintage across states',
  'Same official district aggregation rule',10,80.00,false,
  'SAT remains separate from ACT and requires version/population alignment.')
AS g(comparability_group, test_type, required_population_definition,
     required_aggregation_method, minimum_states, minimum_participation_coverage_pct,
     approved_for_national_ranking, rationale)
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.metric_comparability_groups x
  WHERE x.comparability_group = g.comparability_group
);

CREATE OR REPLACE VIEW living_index.gold.national_ranking_readiness AS
WITH current_obs AS (
  SELECT p.test_type, p.source_id, d.state_abbr,
         count(*) AS observation_count,
         sum(CASE WHEN p.participation_rate IS NOT NULL THEN 1 ELSE 0 END) AS participation_rows
  FROM living_index.silver.performance_observations p
  JOIN living_index.silver.districts d ON d.nces_district_id = p.nces_district_id
  JOIN living_index.silver.observation_lineage l
    ON l.record_scope='performance' AND l.source_id=p.source_id AND l.record_status='current'
  GROUP BY p.test_type, p.source_id, d.state_abbr
), by_test AS (
  SELECT test_type,
         count(DISTINCT state_abbr) AS states_with_data,
         sum(observation_count) AS observations,
         sum(participation_rows) AS participation_rows
  FROM current_obs
  GROUP BY test_type
)
SELECT
  g.comparability_group, g.test_type, g.minimum_states,
  g.minimum_participation_coverage_pct,
  coalesce(b.states_with_data,0) AS states_with_data,
  coalesce(b.observations,0) AS observations,
  CASE WHEN coalesce(b.observations,0)>0
       THEN round(100.0*b.participation_rows/b.observations,2) ELSE 0 END AS participation_coverage_pct,
  CASE WHEN coalesce(b.states_with_data,0) >= g.minimum_states
         AND coalesce(b.observations,0) > 0
         AND 100.0*b.participation_rows/b.observations >= g.minimum_participation_coverage_pct
         AND g.approved_for_national_ranking
       THEN true ELSE false END AS national_ranking_enabled,
  CASE WHEN coalesce(b.states_with_data,0) < g.minimum_states THEN 'insufficient_state_coverage'
       WHEN coalesce(b.observations,0)=0 THEN 'no_observations'
       WHEN 100.0*b.participation_rows/b.observations < g.minimum_participation_coverage_pct THEN 'insufficient_participation_metadata'
       WHEN NOT g.approved_for_national_ranking THEN 'comparability_group_not_approved'
       ELSE 'ready' END AS readiness_reason
FROM living_index.silver.metric_comparability_groups g
LEFT JOIN by_test b ON b.test_type=g.test_type;

SELECT * FROM living_index.gold.national_ranking_readiness;
