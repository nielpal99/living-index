# Living Index — V1

An evidence-backed, configurable index of U.S. places and school districts. V1 starts with a national district universe, Census ACS demographics, and SAT/ACT performance observations.

## V1 scope

- Public school districts from NCES/CCD, keyed by NCES district ID and Census GEOID.
- ACS 5-year median household income and bachelor's degree-or-higher attainment.
- Optional Zillow Economic Research housing metrics, stored at their original geography.
- SAT and ACT average composite scores when an official or secondary source is available.
- Separate SAT and ACT percentile rankings.
- Source provenance, freshness, aggregation method, and confidence labels.

V1 treats the user's current thresholds as a query profile, not as permanent product rules.

## Data layers

- `bronze`: raw files, API responses, and research artifacts.
- `silver`: standardized districts, schools, demographics, performance observations, housing metrics, and sources.
- `gold`: filtered and ranked views intended for search and dashboards.

## First Databricks steps

1. Create the catalog and schemas with `databricks/sql/01_create_schema.sql`.
2. Load NCES district and school directory files into `bronze`.
3. Run `databricks/notebooks/02_ingest_acs_demographics.py` with the chosen ACS vintage.
4. Add the first state SAT/ACT files as raw observations.
5. Build the derived query view with `databricks/sql/03_create_gold_views.sql`.
6. Create the optional housing table with `databricks/sql/04_create_housing_table.sql` and load only official Zillow Research downloads.
7. Create the configurable V1 scoring layer with `databricks/sql/05_create_scoring_layer.sql`.
8. Use `databricks/sql/06_audited_rankings_and_validation.sql` for guarded percentiles, comparability checks, and validation output.
9. Run `databricks/sql/07_backend_hardening.sql` to add canonical geography, metric definitions, lineage, and observation-quality fields.
10. Load Kentucky's normalized official ACT district observations with `databricks/notebooks/05_ingest_ky_act.py`.
11. Run `databricks/sql/10_national_state_registry.sql` once to create the national state-source control plane.
12. Add verified official URLs and metric definitions to `living_index.silver.state_source_registry`; the batch discovery notebook then checks every configured state in one run.
13. Run `databricks/sql/11_data_foundation_hardening.sql` and load an official NCES membership extract with `databricks/notebooks/06_refresh_nces_enrollment.py`.
14. Run `databricks/sql/12_current_record_and_quality_gates.sql` before promoting any new state source into scoring.
15. Run `databricks/notebooks/07_ingest_place_income.py` to load 2024 ACS 5-year median income for all 50 states, DC, counties, and Census places directly through the Census API.
16. Run `databricks/sql/14_income_quality_and_search.sql` to register ACS provenance and create the income search surface.
17. Run `databricks/sql/18_income_bracket_results.sql` to inspect nationwide coverage, `$120,000+` places, and bracket distributions.
18. Run `scripts/fetch_acs_place_education.py` to add place-level bachelor's-or-higher attainment from ACS table B15003; the local finder joins it to income by Census place GEOID.
19. Run `scripts/build_place_school_crosswalk_candidates.py` to create a conservative NCES school-mailing-city candidate layer. These 15,353 candidates are explicitly low-confidence and are not used to assign school performance to places until an official boundary/spatial crosswalk is validated.
20. Run `scripts/build_spatial_place_school_crosswalk.py` to create the stronger Census TIGER/Line 2023 polygon-overlap layer. It retains 36,162 many-to-many links across 30,243 places and 10,359 unified districts, with overlap share and confidence recorded; area overlap is not treated as enrollment share.
21. Run `scripts/fetch_acs_place_demographics.py` to add descriptive ACS composition signals—race/ethnicity, foreign-born share, and age structure. These are displayed as context and are not part of V1 scoring.
22. Run `databricks/sql/13g_place_demographics.sql` to append the same demographic layer into `living_index.silver.place_demographics` with coverage and missingness validation.
23. Run `scripts/build_place_school_performance_context.py` and then `databricks/sql/13h_place_school_performance_context.sql` to expose loaded official district scores beside place overlaps without collapsing many-to-many geography into a false place score.
24. Run `scripts/fetch_acs_place_housing.py` to add 2024 ACS place-level median home value, median gross rent, and renter cost-burden context; load it append-only with `databricks/sql/19_place_housing_context.sql`.

## Interactive discovery surface

The local prototype at `app/index.html` is now the first consumer of the warehouse-style place layer. It supports:

- a nationwide Census-place income and bachelor's-attainment search using the 2024 ACS 5-year extracts;
- explicit income brackets and the `$120,000` baseline;
- a sourced U.S. state-boundary map that highlights matching states and filters the results when clicked;
- click-through community profiles with provenance and data-gap language;
- no invented composite score while schools and housing are not yet joined at place level.

The product roadmap is intentionally layered: (1) place-level income and geography, (2) place-level education and school crosswalks, (3) transparent user-adjustable scoring, (4) boundary-aware community profiles, and only then (5) licensed live housing/listing feeds. The map is a discovery surface, not a claim that the current places are neighborhoods or that live listings are available.

## Important interpretation notes

- ACS values describe residents inside a district boundary, not necessarily enrolled students.
- SAT and ACT are ranked separately in V1.
- A district score calculated from school scores must identify its aggregation method.
- Niche can be used as a discovery or secondary source, but official state and district sources are preferred.
- Zillow metrics must retain their source geography; do not imply district-level precision without a documented crosswalk.
- The default score is academic-forward, but weights and eligibility thresholds live in `living_index.gold.scoring_profiles` so they can become user-specific later.
- National-relative percentiles are intentionally withheld until the coverage and metric registry support them; state-relative results are labeled explicitly.
- Kentucky's grade-11 district-total ACT measure remains a separate methodology group from Georgia and Tennessee until the published population and aggregation definitions align.
- All 50 states and DC are represented in the source registry before ingestion. A state remains `discovery_required` until an official source URL, population definition, vintage, and aggregation rule are verified; this is deliberate and prevents an invented or incomparable national ranking.
- The scalable unit of work is now a registry row plus an adapter configuration, not a bespoke notebook per state. States without official district-level SAT/ACT data remain visible as coverage gaps rather than silently dropping out.
- Every configured ingestion run records an append-only artifact manifest. Current-record selection excludes superseded lineage records, and score eligibility requires a non-null score, a sample of at least 30, and medium/high confidence.
- “City” is operationalized as a Census place (incorporated places and CDPs), with the geography type retained so state, county, and place statistics are never conflated.
- The income search surface exposes the current V1 baseline ($120,000), explicit income brackets, availability status, and within-geography percentile without changing the underlying ACS values.
- The demographic context currently uses ACS broad categories such as “Asian alone”; that is not an Indian-specific measure. A future detailed-subgroup layer can add Indian ancestry/origin signals without changing the V1 quality score.
- Income brackets are Under 80,000; 80,000–119,999; 120,000–149,999 (the V1 baseline band); 150,000–199,999; 200,000–249,999; and 250,000+. ACS values reported as $250,000+ are open-ended and should not be interpreted as exact estimates.
- V2 housing context is descriptive only: median home value, median gross rent, and the share of renter households paying at least 30% of income toward rent. It does not alter the V1 score until a user-configurable affordability model is defined.
