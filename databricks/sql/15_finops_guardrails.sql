-- FinOps guardrails for a personal-credit-card Databricks workspace.
-- These are control-plane records, not billing changes.

CREATE TABLE IF NOT EXISTS living_index.gold.finops_policy (
  policy_id STRING,
  max_runs_per_source_per_day INT,
  refresh_window_days INT,
  max_source_endpoints_per_run INT,
  enabled BOOLEAN,
  notes STRING,
  updated_at TIMESTAMP
) USING DELTA;

INSERT INTO living_index.gold.finops_policy
SELECT 'default_personal_workspace', 1, 30, 60, true,
       'Prefer cached data and one scheduled run per source per day.', current_timestamp()
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.gold.finops_policy
  WHERE policy_id = 'default_personal_workspace'
);

CREATE TABLE IF NOT EXISTS living_index.gold.finops_run_events (
  run_id TIMESTAMP,
  pipeline_name STRING,
  source_id STRING,
  action STRING,
  rows_read BIGINT,
  rows_written BIGINT,
  api_requests BIGINT,
  skipped_reason STRING,
  created_at TIMESTAMP
) USING DELTA;

CREATE OR REPLACE VIEW living_index.gold.finops_daily_summary AS
SELECT
  date(created_at) AS run_date,
  pipeline_name,
  count(*) AS run_events,
  sum(coalesce(rows_read,0)) AS rows_read,
  sum(coalesce(rows_written,0)) AS rows_written,
  sum(coalesce(api_requests,0)) AS api_requests,
  count_if(action = 'skipped') AS skipped_events,
  count_if(action = 'loaded') AS loaded_events
FROM living_index.gold.finops_run_events
GROUP BY date(created_at), pipeline_name;

SELECT * FROM living_index.gold.finops_daily_summary
WHERE run_date >= date_sub(current_date(), 30)
ORDER BY run_date DESC, pipeline_name;
