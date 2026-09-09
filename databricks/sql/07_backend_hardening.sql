-- Additive backend hardening. Historical silver rows are never deleted or updated.

CREATE TABLE IF NOT EXISTS living_index.silver.geography_entities (
  geography_id STRING,
  geography_type STRING,
  geography_name STRING,
  state_abbr STRING,
  nces_district_id STRING,
  census_geoid STRING,
  source_id STRING,
  active_flag BOOLEAN,
  loaded_at TIMESTAMP
) USING DELTA;

INSERT INTO living_index.silver.geography_entities
SELECT
  concat('district:', nces_district_id), 'school_district', district_name,
  state_abbr, nces_district_id, census_geoid,
  'nces_ccd_2023_24_preliminary_directory', true, current_timestamp()
FROM living_index.silver.districts d
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.geography_entities g
  WHERE g.geography_id = concat('district:', d.nces_district_id)
);

CREATE TABLE IF NOT EXISTS living_index.silver.geography_crosswalks (
  source_geography_id STRING,
  source_geography_type STRING,
  canonical_geography_id STRING,
  canonical_geography_type STRING,
  crosswalk_method STRING,
  precision_level STRING,
  confidence STRING,
  source_id STRING,
  active_flag BOOLEAN,
  loaded_at TIMESTAMP
) USING DELTA;

INSERT INTO living_index.silver.geography_crosswalks
SELECT nces_district_id, 'nces_district', concat('district:', nces_district_id),
       'school_district', 'identity_nces_id', 'district', 'high', source_id, true,
       current_timestamp()
FROM living_index.silver.districts d
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.geography_crosswalks x
  WHERE x.source_geography_id = d.nces_district_id
    AND x.source_geography_type = 'nces_district'
);

INSERT INTO living_index.silver.geography_crosswalks
SELECT census_geoid, 'census_school_district', concat('district:', nces_district_id),
       'school_district', 'identity_census_geoid_on_nces_crosswalk', 'district', 'high',
       'nces_ccd_2023_24_preliminary_directory', true, current_timestamp()
FROM living_index.silver.districts d
WHERE census_geoid IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM living_index.silver.geography_crosswalks x
    WHERE x.source_geography_id = d.census_geoid
      AND x.source_geography_type = 'census_school_district'
  );

CREATE TABLE IF NOT EXISTS living_index.silver.metric_definitions (
  metric_id STRING,
  metric_name STRING,
  test_type STRING,
  unit STRING,
  population_definition STRING,
  geography_level STRING,
  vintage STRING,
  aggregation_method STRING,
  comparability_status STRING,
  confidence_default STRING,
  source_id STRING,
  notes STRING,
  registered_at TIMESTAMP
) USING DELTA;

INSERT INTO living_index.silver.metric_definitions
SELECT metric_id, metric_name, test_type, unit, population_definition, geography_level, vintage,
       aggregation_method, comparability_status, confidence_default, source_id, notes,
       current_timestamp()
FROM VALUES
 ('ga_act_average_composite_2024_25','average_composite','ACT','ACT composite points',
  'Georgia GOSA All Students; export score population/window pending formal verification.',
  'school_district','2024-25','official district average','state-relative-only','high',
  'georgia_goews_2024_25_scores_crosswalked','Not nationally comparable to Tennessee yet.'),
 ('ga_sat_average_composite_2024_25','average_composite','SAT','SAT combined points',
  'Georgia GOSA All Students; export definition retained in observation notes.',
  'school_district','2024-25','official district average','state-relative-only','high',
  'georgia_goews_2024_25_scores_crosswalked','SAT is ranked separately from ACT.'),
 ('tn_act_average_composite_2024_25','average_composite','ACT','ACT composite points',
  'Tennessee All Students; graduates; highest score earned in three years preceding graduation.',
  'school_district','2024-25','official district average','state-relative-only','high',
  'tennessee_act_2024_25_scores','Not comparable to Georgia pending equivalent population/window.'),
 ('ky_act_average_composite_2024_25','average_composite','ACT','ACT composite points',
  'Kentucky grade 11 students represented in the official district-total average; population/window differs from Tennessee.',
  'school_district','2024-25','official district total grade 11 average','state-relative-only','high',
  'kentucky_act_2024_25_scores','Not comparable to Georgia or Tennessee until population and aggregation definitions are aligned.'),
 ('acs_median_household_income_2023','median_household_income',NULL,'US dollars',
  'Civilian household population within Census school district geography.',
  'school_district','2023 ACS 5-year','Census published estimate','comparable_acs_vintage','high',
  'census_acs5_school_district_2023','ACS geography describes residents, not enrolled students.'),
 ('acs_bachelors_or_higher_pct_2023','bachelors_or_higher_pct',NULL,'percent',
  'Population age 25+ with bachelor''s degree or higher within Census school district geography.',
  'school_district','2023 ACS 5-year','derived from published education counts','comparable_acs_vintage','high',
  'census_acs5_school_district_2023','ACS geography describes residents, not enrolled students.')
AS m(metric_id, metric_name, test_type, unit, population_definition, geography_level, vintage,
     aggregation_method, comparability_status, confidence_default, source_id, notes)
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.metric_definitions d WHERE d.metric_id = m.metric_id
);

CREATE TABLE IF NOT EXISTS living_index.silver.observation_lineage (
  record_scope STRING,
  source_id STRING,
  record_status STRING,
  supersedes_source_id STRING,
  reason STRING,
  effective_date DATE,
  registered_at TIMESTAMP
) USING DELTA;

INSERT INTO living_index.silver.observation_lineage
SELECT record_scope, source_id, record_status, supersedes_source_id, reason,
       effective_date, current_timestamp()
FROM VALUES
 ('performance','georgia_goews_2024_25_scores','superseded',NULL,
  'Initial Georgia load retained for history; corrected crosswalked records are current.',current_date()),
 ('performance','georgia_goews_2024_25_scores_crosswalked','current','georgia_goews_2024_25_scores',
  'Corrected NCES district crosswalk; current Georgia observations.',current_date()),
 ('performance','tennessee_act_2024_25_scores','current',NULL,
  'Official Tennessee district ACT observations.',current_date()),
 ('performance','kentucky_act_2024_25_scores','current',NULL,
  'Official Kentucky district ACT observations; retained as a separate methodology group.',current_date())
AS l(record_scope, source_id, record_status, supersedes_source_id, reason, effective_date)
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.observation_lineage x
  WHERE x.record_scope = l.record_scope AND x.source_id = l.source_id
);

CREATE OR REPLACE VIEW living_index.gold.performance_observation_quality AS
SELECT
  p.observation_id,
  p.nces_school_id,
  p.nces_district_id,
  d.census_geoid,
  d.state_abbr,
  p.test_type,
  p.metric_name,
  p.metric_value,
  p.score_year,
  p.students_tested,
  p.participation_rate,
  p.aggregation_method,
  p.source_type,
  p.source_id,
  p.confidence,
  p.notes,
  p.benchmark_attainment_rate,
  p.benchmark_definition,
  p.performance_population,
  p.score_percentile,
  p.percentile_scope,
  coalesce(l.record_status,'unregistered') AS record_status,
  CASE WHEN l.record_status = 'current' THEN true ELSE false END AS is_current_record,
  CASE WHEN p.students_tested IS NULL THEN true ELSE false END AS missing_sample_size,
  CASE WHEN p.participation_rate IS NULL THEN true ELSE false END AS missing_participation_rate,
  CASE WHEN p.notes RLIKE '(?i)<10|suppressed|not reported|N/A' THEN true ELSE false END AS suppressed_or_unreported,
  CASE WHEN p.nces_district_id IS NOT NULL THEN 'school_district' ELSE 'unresolved' END AS geographic_precision,
  datediff(current_date(), coalesce(s.retrieval_date, current_date())) AS source_age_days,
  CASE WHEN datediff(current_date(), coalesce(s.retrieval_date, current_date())) <= 365
    THEN 'fresh' ELSE 'stale' END AS freshness_status,
  md.comparability_status,
  md.confidence_default
FROM living_index.silver.performance_observations p
LEFT JOIN living_index.silver.districts d ON p.nces_district_id = d.nces_district_id
LEFT JOIN living_index.silver.observation_lineage l
  ON l.record_scope = 'performance' AND l.source_id = p.source_id
LEFT JOIN living_index.silver.sources s ON s.source_id = p.source_id
LEFT JOIN living_index.silver.metric_definitions md
 ON md.source_id = p.source_id
 AND md.test_type = upper(p.test_type);

-- Backend validation summary.
SELECT 'geography_entities' AS object_name, count(*) AS row_count
FROM living_index.silver.geography_entities
UNION ALL SELECT 'geography_crosswalks', count(*)
FROM living_index.silver.geography_crosswalks
UNION ALL SELECT 'metric_definitions', count(*)
FROM living_index.silver.metric_definitions
UNION ALL SELECT 'observation_lineage', count(*)
FROM living_index.silver.observation_lineage;
