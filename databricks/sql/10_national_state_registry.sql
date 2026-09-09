-- National source-discovery control plane.
-- This is intentionally additive: it records the work needed for every state
-- without pretending that a source exists or that metrics are comparable.

CREATE TABLE IF NOT EXISTS living_index.silver.state_source_registry (
  state_abbr STRING,
  state_name STRING,
  official_agency STRING,
  discovery_query STRING,
  source_url STRING,
  source_format STRING,
  target_test_types STRING,
  target_population STRING,
  target_aggregation STRING,
  comparability_group STRING,
  source_status STRING,
  priority INT,
  last_checked TIMESTAMP,
  notes STRING,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
) USING DELTA;

-- All 50 states plus DC are represented up front. URLs remain NULL until
-- verified from an official publisher; this prevents fabricated endpoints.
MERGE INTO living_index.silver.state_source_registry AS target
USING (
  VALUES
    ('AL','Alabama','Alabama State Department of Education'),
    ('AK','Alaska','Alaska Department of Education and Early Development'),
    ('AZ','Arizona','Arizona Department of Education'),
    ('AR','Arkansas','Arkansas Division of Elementary and Secondary Education'),
    ('CA','California','California Department of Education'),
    ('CO','Colorado','Colorado Department of Education'),
    ('CT','Connecticut','Connecticut State Department of Education'),
    ('DE','Delaware','Delaware Department of Education'),
    ('FL','Florida','Florida Department of Education'),
    ('GA','Georgia Governor''s Office of Student Achievement'),
    ('HI','Hawaii','Hawaii State Department of Education'),
    ('ID','Idaho','Idaho State Department of Education'),
    ('IL','Illinois','Illinois State Board of Education'),
    ('IN','Indiana','Indiana Department of Education'),
    ('IA','Iowa','Iowa Department of Education'),
    ('KS','Kansas','Kansas State Department of Education'),
    ('KY','Kentucky','Kentucky Department of Education'),
    ('LA','Louisiana','Louisiana Department of Education'),
    ('ME','Maine','Maine Department of Education'),
    ('MD','Maryland','Maryland State Department of Education'),
    ('MA','Massachusetts','Massachusetts Department of Elementary and Secondary Education'),
    ('MI','Michigan','Michigan Department of Education'),
    ('MN','Minnesota','Minnesota Department of Education'),
    ('MS','Mississippi','Mississippi Department of Education'),
    ('MO','Missouri','Missouri Department of Elementary and Secondary Education'),
    ('MT','Montana','Montana Office of Public Instruction'),
    ('NE','Nebraska','Nebraska Department of Education'),
    ('NV','Nevada','Nevada Department of Education'),
    ('NH','New Hampshire','New Hampshire Department of Education'),
    ('NJ','New Jersey','New Jersey Department of Education'),
    ('NM','New Mexico','New Mexico Public Education Department'),
    ('NY','New York','New York State Education Department'),
    ('NC','North Carolina','North Carolina Department of Public Instruction'),
    ('ND','North Dakota','North Dakota Department of Public Instruction'),
    ('OH','Ohio','Ohio Department of Education and Workforce'),
    ('OK','Oklahoma','Oklahoma State Department of Education'),
    ('OR','Oregon','Oregon Department of Education'),
    ('PA','Pennsylvania','Pennsylvania Department of Education'),
    ('RI','Rhode Island','Rhode Island Department of Education'),
    ('SC','South Carolina','South Carolina Department of Education'),
    ('SD','South Dakota','South Dakota Department of Education'),
    ('TN','Tennessee','Tennessee Department of Education'),
    ('TX','Texas','Texas Education Agency'),
    ('UT','Utah','Utah State Board of Education'),
    ('VT','Vermont','Vermont Agency of Education'),
    ('VA','Virginia','Virginia Department of Education'),
    ('WA','Washington','Washington Office of Superintendent of Public Instruction'),
    ('WV','West Virginia','West Virginia Department of Education'),
    ('WI','Wisconsin','Wisconsin Department of Public Instruction'),
    ('WY','Wyoming','Wyoming Department of Education'),
    ('DC','District of Columbia','District of Columbia Office of the State Superintendent of Education')
  ) AS source(state_abbr,state_name,official_agency)
ON target.state_abbr = source.state_abbr
WHEN MATCHED THEN UPDATE SET
  target.state_name = source.state_name,
  target.official_agency = source.official_agency,
  target.updated_at = current_timestamp()
WHEN NOT MATCHED THEN INSERT (
  state_abbr,state_name,official_agency,discovery_query,source_url,source_format,
  target_test_types,target_population,target_aggregation,comparability_group,
  source_status,priority,last_checked,notes,created_at,updated_at
) VALUES (
  source.state_abbr,source.state_name,source.official_agency,
  concat(source.official_agency, ' district SAT ACT average score data download'),
  NULL,NULL,'SAT,ACT',NULL,NULL,NULL,'discovery_required',99,NULL,
  'Populate only after verifying an official publisher, vintage, population, and geography.',
  current_timestamp(),current_timestamp()
);

-- Surface the first wave without deleting the original priority queue.
MERGE INTO living_index.silver.source_discovery_queue AS target
USING (
  VALUES
    ('CA',1,'ACT_or_SAT_district','Large population and migration interest','candidate',''),
    ('TX',2,'ACT_or_SAT_district','Large population and migration interest','candidate',''),
    ('FL',3,'ACT_or_SAT_district','Large population and migration interest','candidate',''),
    ('NY',4,'SAT_or_ACT_district','Large population and migration interest','candidate',''),
    ('NC',5,'ACT_or_SAT_district','Migration interest and official reporting depth','candidate',''),
    ('VA',6,'ACT_or_SAT_district','Migration interest and geography coverage','candidate',''),
    ('PA',7,'SAT_or_ACT_district','Large population and migration interest','candidate',''),
    ('OH',8,'ACT_or_SAT_district','Large population and district universe','candidate',''),
    ('MA',9,'SAT_or_ACT_district','High education signal and migration interest','candidate',''),
    ('WA',10,'SAT_or_ACT_district','Migration interest and place intelligence','candidate','')
  ) AS source(state_abbr,priority,target_metric_group,rationale,discovery_status,notes)
ON target.state_abbr = source.state_abbr
WHEN MATCHED THEN UPDATE SET target.priority=source.priority, target.rationale=source.rationale
WHEN NOT MATCHED THEN INSERT (state_abbr,priority,target_metric_group,rationale,discovery_status,last_checked,notes)
VALUES (source.state_abbr,source.priority,source.target_metric_group,source.rationale,source.discovery_status,NULL,source.notes);

CREATE OR REPLACE VIEW living_index.gold.state_source_coverage AS
SELECT
  r.state_abbr, r.state_name, r.official_agency, r.source_status, r.priority,
  r.source_url, r.source_format, r.target_test_types, r.target_population,
  r.target_aggregation, r.comparability_group, r.last_checked,
  coalesce(c.observation_count,0) AS observation_count,
  coalesce(c.district_count,0) AS district_count,
  CASE WHEN coalesce(c.observation_count,0) > 0 THEN 'loaded' ELSE r.source_status END AS effective_status,
  CASE WHEN r.source_url IS NULL THEN 'needs_official_source_url'
       WHEN coalesce(c.observation_count,0) = 0 THEN 'source_not_loaded'
       ELSE 'loaded_review_quality' END AS next_action
FROM living_index.silver.state_source_registry r
LEFT JOIN (
  SELECT d.state_abbr, count(*) AS observation_count, count(DISTINCT p.nces_district_id) AS district_count
  FROM living_index.silver.performance_observations p
  JOIN living_index.silver.districts d ON d.nces_district_id=p.nces_district_id
  GROUP BY d.state_abbr
) c ON c.state_abbr=r.state_abbr;

SELECT source_status, count(*) AS states
FROM living_index.gold.state_source_coverage
GROUP BY source_status
ORDER BY source_status;
