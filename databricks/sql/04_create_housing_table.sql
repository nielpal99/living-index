-- Zillow Economic Research metrics are maintained at their source geography.
-- They should be mapped to districts only through an explicit crosswalk.

CREATE TABLE IF NOT EXISTS living_index.silver.housing_metrics (
  geography_id STRING,
  geography_type STRING,
  geography_name STRING,
  metric_name STRING,
  metric_value DECIMAL(18,3),
  metric_unit STRING,
  metric_date DATE,
  source_id STRING,
  loaded_at TIMESTAMP
) USING DELTA;

INSERT INTO living_index.silver.sources
  (source_id, source_url, publisher, source_type, retrieval_date, document_hash, notes)
VALUES
  (
    'zillow_research_public_metrics',
    'https://www.zillow.com/research/data/',
    'Zillow Economic Research',
    'public_research_download',
    current_date(),
    NULL,
    'Public housing metrics; use with Zillow attribution and preserve source geography.'
  );
