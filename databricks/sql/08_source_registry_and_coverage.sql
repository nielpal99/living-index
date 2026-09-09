-- Source registry for configuration-driven, additive state onboarding.
-- This table describes how a source should be interpreted; it does not replace history.

CREATE TABLE IF NOT EXISTS living_index.silver.source_discovery_queue (
  state_abbr STRING,
  priority INT,
  target_metric_group STRING,
  rationale STRING,
  discovery_status STRING,
  last_checked DATE,
  notes STRING
) USING DELTA;

INSERT INTO living_index.silver.source_discovery_queue
SELECT state_abbr, priority, target_metric_group, rationale, discovery_status, NULL, notes
FROM VALUES
 ('CA',1,'ACT_or_SAT_district','Large population and high migration interest','candidate','Begin with official state assessment exports.'),
 ('TX',2,'ACT_or_SAT_district','Large population and high migration interest','candidate','Prefer district-level official averages with participation.'),
 ('FL',3,'ACT_or_SAT_district','Large population and high migration interest','candidate','Prioritize official district files and stable annual vintage.'),
 ('NY',4,'SAT_or_ACT_district','Large population and high migration interest','candidate','Check state assessment and public reporting portals.'),
 ('NC',5,'ACT_or_SAT_district','Migration interest and likely official reporting depth','candidate','Seek district-level measure with explicit tested population.'),
 ('VA',6,'ACT_or_SAT_district','Migration interest and strong district geography coverage','candidate','Prefer comparable district aggregate and participation.'),
 ('PA',7,'SAT_or_ACT_district','Large population and migration interest','candidate','Verify district-level availability before ingestion.'),
 ('OH',8,'ACT_or_SAT_district','Large population and broad district universe','candidate','Verify source methodology and current vintage.'),
 ('MA',9,'SAT_or_ACT_district','High education signal and migration interest','candidate','Look for district-level college-readiness measures.'),
 ('WA',10,'SAT_or_ACT_district','Migration interest and high-value place intelligence','candidate','Verify public district score availability.')
AS q(state_abbr, priority, target_metric_group, rationale, discovery_status, notes)
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.source_discovery_queue x WHERE x.state_abbr=q.state_abbr
);

CREATE TABLE IF NOT EXISTS living_index.silver.source_registry (
  source_id STRING,
  geography_scope STRING,
  state_abbr STRING,
  publisher STRING,
  source_url STRING,
  source_type STRING,
  file_format STRING,
  source_path STRING,
  crosswalk_rule STRING,
  source_status STRING,
  score_year STRING,
  test_type STRING,
  metric_name STRING,
  population_definition STRING,
  aggregation_method STRING,
  comparability_group STRING,
  comparability_status STRING,
  loader_key STRING,
  refresh_cadence STRING,
  priority INT,
  active_flag BOOLEAN,
  registered_at TIMESTAMP
) USING DELTA;

CREATE TABLE IF NOT EXISTS living_index.gold.source_quality_snapshots (
  run_id TIMESTAMP,
  source_id STRING,
  state_abbr STRING,
  observation_count BIGINT,
  district_count BIGINT,
  base_district_count BIGINT,
  district_coverage_pct DECIMAL(7,2),
  missing_sample_size BIGINT,
  missing_participation_rate BIGINT,
  source_metadata_present BOOLEAN,
  registry_status STRING,
  quality_status STRING,
  quality_reason STRING,
  created_at TIMESTAMP
) USING DELTA;

INSERT INTO living_index.silver.source_registry
SELECT source_id, geography_scope, state_abbr, publisher, source_url, source_type,
       file_format, source_path, crosswalk_rule, source_status, score_year, test_type, metric_name,
       population_definition, aggregation_method, comparability_group,
       comparability_status, loader_key, refresh_cadence, priority,
       active_flag, current_timestamp()
FROM VALUES
 ('georgia_goews_2024_25_scores_crosswalked','school_district','GA','Georgia Governor''s Office of Student Achievement',
  'https://gosa.georgia.gov/dashboards-data-reporting/test-scores','official_state_export','csv','/Volumes/workspace/default/raw_sources/ga_performance_observations_v2.csv','exact_nces_district_name','loaded','2024-25','ACT',
  'average_composite','Georgia All Students; state export population retained in source notes.',
  'official_district_average','state_act_district_average','state-relative-only','state_csv_adapter','annual',1,true,
  'exact_nces_district_name','loaded'),
 ('tennessee_act_2024_25_scores','school_district','TN','Tennessee Department of Education',
  'https://www.tn.gov/education/districts/federal-programs-and-oversight/data/data-downloads.html','official_state_export','csv',
  '/Volumes/workspace/default/raw_sources/tn_act_performance_observations.csv','exact_nces_district_name','loaded','2024-25','ACT','average_composite',
  'All Students; graduates; highest score earned in three years preceding graduation.',
  'official_district_average','state_act_graduate_window','state-relative-only','state_csv_adapter','annual',2,true,
  'exact_nces_district_name','loaded'),
 ('kentucky_act_2024_25_scores','school_district','KY','Kentucky Department of Education',
  'https://www.education.ky.gov/Open-House/data/Pages/Supplemental-Data-Assessment-and-Accountability.aspx','official_state_export','csv',
  '/Volumes/workspace/default/raw_sources/ky_act_performance_observations.csv','exact_nces_district_name_with_unmatched_exclusions','loaded','2024-25','ACT','average_composite',
  'Grade 11 students represented in official district-total average.',
  'official_district_total_grade_11_average','state_act_grade11_district_total','state-relative-only','state_csv_adapter','annual',3,true,
  'exact_nces_district_name_with_unmatched_exclusions','loaded')
AS r(source_id, geography_scope, state_abbr, publisher, source_url, source_type,
     file_format, source_path, crosswalk_rule, source_status, score_year, test_type, metric_name,
     population_definition, aggregation_method, comparability_group,
     comparability_status, loader_key, refresh_cadence, priority, active_flag)
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.source_registry x WHERE x.source_id = r.source_id
);

CREATE OR REPLACE VIEW living_index.gold.source_coverage_dashboard AS
SELECT
  r.source_id, r.state_abbr, r.publisher, r.test_type, r.score_year,
  r.population_definition, r.aggregation_method, r.comparability_group,
  r.comparability_status, r.loader_key, r.priority, r.active_flag,
  coalesce(s.retrieval_date, current_date()) AS retrieval_date,
  datediff(current_date(), coalesce(s.retrieval_date, current_date())) AS source_age_days,
  CASE WHEN s.source_id IS NULL THEN 'not_registered_in_sources'
       WHEN datediff(current_date(), s.retrieval_date) <= 365 THEN 'fresh'
       ELSE 'stale' END AS freshness_status,
  coalesce(o.observation_count, 0) AS observation_count,
  coalesce(o.district_count, 0) AS district_count,
  coalesce(o.missing_sample_size, 0) AS missing_sample_size,
  coalesce(o.missing_participation_rate, 0) AS missing_participation_rate,
  coalesce(b.base_district_count, 0) AS base_district_count,
  CASE WHEN b.base_district_count > 0 THEN round(100.0 * coalesce(o.district_count, 0) / b.base_district_count, 2) END AS district_coverage_pct,
  CASE WHEN o.enrollment_covered IS NULL THEN 'unavailable' ELSE 'available' END AS population_coverage_status,
  o.enrollment_covered
FROM living_index.silver.source_registry r
LEFT JOIN living_index.silver.sources s ON s.source_id = r.source_id
LEFT JOIN (
  SELECT source_id, count(*) AS observation_count,
         count(DISTINCT nces_district_id) AS district_count,
         sum(CASE WHEN students_tested IS NULL THEN 1 ELSE 0 END) AS missing_sample_size,
         sum(CASE WHEN participation_rate IS NULL THEN 1 ELSE 0 END) AS missing_participation_rate,
         nullif(sum(d.enrollment), 0) AS enrollment_covered
  FROM living_index.silver.performance_observations
  LEFT JOIN living_index.silver.districts d USING (nces_district_id)
  GROUP BY source_id
) o ON o.source_id = r.source_id
LEFT JOIN (
  SELECT state_abbr, count(DISTINCT nces_district_id) AS base_district_count
  FROM living_index.silver.districts
  GROUP BY state_abbr
) b ON b.state_abbr = r.state_abbr;

CREATE OR REPLACE VIEW living_index.gold.source_quality_gate AS
SELECT
  c.*,
  CASE
    WHEN c.observation_count = 0 THEN 'blocked'
    WHEN c.comparability_status NOT IN ('national-comparable', 'national_comparable')
      AND c.missing_participation_rate = c.observation_count THEN 'warning'
    WHEN c.comparability_status NOT IN ('national-comparable', 'national_comparable') THEN 'state-relative-only'
    ELSE 'ready-for-comparison'
  END AS quality_status,
  CASE
    WHEN c.observation_count = 0 THEN 'No observations loaded.'
    WHEN c.comparability_status NOT IN ('national-comparable', 'national_comparable')
      AND c.missing_participation_rate = c.observation_count THEN 'Participation is unavailable; state-relative use only.'
    WHEN c.comparability_status NOT IN ('national-comparable', 'national_comparable') THEN 'Metric is not approved for national comparison.'
    ELSE 'Source passes current registry checks.'
  END AS quality_reason
FROM living_index.gold.source_coverage_dashboard c;

SELECT * FROM living_index.gold.source_coverage_dashboard ORDER BY priority;
