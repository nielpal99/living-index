-- Official Census TIGER/Line 2023 place-to-unified-school-district overlap layer.
-- Keep this many-to-many and do not treat area overlap as attendance share.

CREATE TABLE IF NOT EXISTS living_index.silver.place_school_crosswalk (
  place_geoid STRING,
  place_name STRING,
  state_fips STRING,
  district_geoid STRING,
  district_name STRING,
  place_area_share_pct DECIMAL(7,3),
  match_method STRING,
  confidence STRING,
  validation_status STRING,
  notes STRING,
  loaded_at TIMESTAMP
) USING DELTA;

CREATE OR REPLACE TEMP VIEW place_school_crosswalk_raw
USING CSV
OPTIONS (
  path '/Volumes/workspace/default/raw_sources/place_unified_school_district_spatial_crosswalk_2023.csv',
  header 'true',
  inferSchema 'false'
);

INSERT INTO living_index.silver.place_school_crosswalk
SELECT place_geoid, place_name, state_fips, district_geoid, district_name,
       try_cast(place_area_share_pct AS DECIMAL(7,3)), match_method, confidence,
       validation_status, notes, current_timestamp()
FROM place_school_crosswalk_raw r
WHERE NOT EXISTS (
  SELECT 1 FROM living_index.silver.place_school_crosswalk x
  WHERE x.place_geoid = r.place_geoid AND x.district_geoid = r.district_geoid
);

SELECT state_fips,
       count(DISTINCT place_geoid) AS places_with_links,
       count(DISTINCT district_geoid) AS districts_with_links,
       count(*) AS links,
       count_if(confidence = 'medium') AS medium_confidence_links,
       count_if(confidence = 'low') AS low_confidence_links
FROM living_index.silver.place_school_crosswalk
GROUP BY state_fips
ORDER BY state_fips;
