# Living Index

Living Index is a transparent place-intelligence prototype for discovering U.S. communities that fit a person’s priorities.

It combines Census geography, ACS household and education measures, and optional housing context. School data is retained as a secondary enrichment path, but it is not the product’s primary focus. The goal is to make the inputs, limitations, and tradeoffs visible.

## What is here

- A local interactive community finder with map filtering, income brackets, population controls, education thresholds, and Zillow links.
- A Databricks bronze/silver/gold data foundation for raw artifacts, standardized entities, provenance, quality checks, and search views.
- Reusable Python ingestion and normalization scripts for ACS, NCES, and state education sources.
- A secondary school-data foundation with separate SAT and ACT metrics and explicit methodology fields.
- Append-only source lineage and validation SQL designed to preserve historical observations.

## Current product behavior

The prototype searches Census places using 2024 ACS 5-year data. The default view uses $120,000+ median household income, 30%+ bachelor’s attainment among residents age 25+, and 2,000+ residents by default with a 1,000-resident floor. Incorporated places and CDPs remain distinct.

Housing and demographic fields are descriptive context. They do not change the V1 score. School performance remains optional context and is shown only where an official observation and a defensible geography relationship exist.

## Workflow

```text
Official sources / APIs
          ↓
Bronze: immutable raw artifacts and manifests
          ↓
Silver: canonical geography, normalized metrics, lineage, quality fields
          ↓
Gold: guarded search, percentiles, scoring, and coverage views
          ↓
Local finder / future API
```

The important work is standardization: an “average ACT score” is only comparable when its population, test year, aggregation method, and participation context align. Until then, the warehouse preserves the value but keeps it out of combined national rankings.

## Run the local prototype

From the repository root:

```bash
python3 -m http.server 8765 --bind 127.0.0.1
```

Open <http://127.0.0.1:8765/app/index.html>.

## Databricks workflow

Run the SQL files in dependency order:

1. Create `living_index` and the bronze, silver, and gold schemas.
2. Load NCES and source artifacts into bronze.
3. Normalize ACS, state performance, housing, and crosswalk inputs into silver.
4. Register provenance, metric definitions, vintages, aggregation methods, and confidence.
5. Apply current-record and quality gates before promotion.
6. Build guarded gold views and inspect coverage and comparability outputs.

The main controls are in `databricks/sql/12_current_record_and_quality_gates.sql`, `14_income_quality_and_search.sql`, `15_finops_guardrails.sql`, `19_place_housing_context.sql`, and `06_audited_rankings_and_validation.sql`.

Databricks is currently a governed SQL warehouse and batch-processing environment—not yet a production API, streaming system, or fully scheduled national pipeline.

## Repository layout

| Path | Purpose |
| --- | --- |
| `app/` | Interactive local discovery prototype |
| `config/` | Source adapter and ingestion configuration |
| `databricks/notebooks/` | Batch discovery, ingestion, and normalization jobs |
| `databricks/sql/` | Schemas, tables, views, quality gates, scoring, and validation |
| `scripts/` | Local API fetchers, converters, crosswalk builders, and validators |
| `docs/` | Architecture, audit findings, and data policy |
| `work/raw/` | Reproducible local extracts and source-derived artifacts |

## Limitations

- ACS estimates include sampling uncertainty and may be suppressed or open-ended.
- City is represented as a Census place; a CDP is not an incorporated city.
- Area overlap is not the same as a school attendance boundary.
- SAT and ACT remain separate metrics.
- National-relative percentiles are withheld until coverage and comparability are adequate.
- Zillow links lead to current external listings; listing data is not stored here.

## Roadmap

1. Finish canonical geography and source registration across all states.
2. Add transparent user-weighted scoring.
3. Add licensed housing inventory and affordability signals.
4. Optionally deepen school-performance coverage by methodology group.

See [`docs/architecture.md`](docs/architecture.md), [`docs/data-policy.md`](docs/data-policy.md), and [`docs/backend_audit.md`](docs/backend_audit.md) for the detailed design.
