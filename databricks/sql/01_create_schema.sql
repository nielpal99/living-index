-- Run in a Databricks SQL warehouse.
-- Replace the catalog name if your workspace uses a different default catalog.

CREATE CATALOG IF NOT EXISTS living_index;

CREATE SCHEMA IF NOT EXISTS living_index.bronze;
CREATE SCHEMA IF NOT EXISTS living_index.silver;
CREATE SCHEMA IF NOT EXISTS living_index.gold;

CREATE TABLE IF NOT EXISTS living_index.silver.districts (
  nces_district_id STRING,
  census_geoid STRING,
  district_name STRING,
  state_fips STRING,
  state_abbr STRING,
  district_type STRING,
  enrollment BIGINT,
  high_school_count INT,
  active_flag BOOLEAN,
  source_id STRING,
  loaded_at TIMESTAMP
) USING DELTA;

CREATE TABLE IF NOT EXISTS living_index.silver.schools (
  nces_school_id STRING,
  nces_district_id STRING,
  school_name STRING,
  state_abbr STRING,
  school_type STRING,
  enrollment BIGINT,
  grades_offered STRING,
  active_flag BOOLEAN,
  source_id STRING,
  loaded_at TIMESTAMP
) USING DELTA;

CREATE TABLE IF NOT EXISTS living_index.silver.demographics (
  census_geoid STRING,
  acs_vintage STRING,
  median_household_income DECIMAL(18,2),
  bachelors_or_higher_pct DECIMAL(7,3),
  population_25_plus BIGINT,
  income_margin_of_error DECIMAL(18,2),
  education_margin_of_error DECIMAL(7,3),
  source_id STRING,
  loaded_at TIMESTAMP
) USING DELTA;

CREATE TABLE IF NOT EXISTS living_index.silver.performance_observations (
  observation_id STRING,
  nces_school_id STRING,
  nces_district_id STRING,
  test_type STRING,
  metric_name STRING,
  metric_value DECIMAL(12,3),
  score_year STRING,
  students_tested BIGINT,
  participation_rate DECIMAL(7,3),
  aggregation_method STRING,
  source_type STRING,
  source_id STRING,
  confidence STRING,
  notes STRING,
  benchmark_attainment_rate DECIMAL(7,3),
  benchmark_definition STRING,
  performance_population STRING,
  score_percentile DECIMAL(7,5),
  percentile_scope STRING,
  loaded_at TIMESTAMP
) USING DELTA;

CREATE TABLE IF NOT EXISTS living_index.silver.sources (
  source_id STRING,
  source_url STRING,
  publisher STRING,
  source_type STRING,
  retrieval_date DATE,
  document_hash STRING,
  notes STRING
) USING DELTA;
