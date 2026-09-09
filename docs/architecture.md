# Architecture

## Data flow

1. Source adapters identify an official download or API and record retrieval metadata.
2. Bronze preserves the source artifact and manifest without mutation.
3. Silver normalizes identifiers, units, vintages, populations, aggregation methods, and quality fields.
4. Gold selects current records, applies quality gates, calculates separate percentiles, and exposes search surfaces.
5. The local app consumes exported place extracts while Databricks remains the system of record.

## Core entities

- `canonical_geography`: stable place, district, county, and state identifiers.
- `geography_crosswalk`: explicit relationships with relationship type and confidence.
- `source_registry`: source URL, owner, retrieval date, cadence, and status.
- `metric_definition`: unit, population, vintage, aggregation, comparability group, and confidence.
- `observation`: append-only measured values with source and quality metadata.
- `gold` views: current, eligible, percentile, and scored records.

## Comparability rule

Metrics are combined only within a declared comparability group. State-relative results can be shown when national coverage is insufficient; national-relative results require adequate coverage and aligned definitions.

## Scoring rule

The preserved V1 model is academic 60% and community 40%, with community split 50% income percentile and 50% bachelor’s attainment percentile. Missing academic values remain unavailable and are never converted to zero.
