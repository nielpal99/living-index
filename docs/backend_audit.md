# Living Index backend audit

## Highest-risk gaps

1. **Source coverage is not yet national.** The district universe is national, but SAT/ACT performance is only loaded for GA, TN, and KY. The state registry now represents all 50 states plus DC and distinguishes `discovery_required`, `source_not_loaded`, and `loaded_review_quality`.
2. **There is no uniform national district SAT/ACT feed.** State files differ in tested population, score window, suppression rules, school-vs-district grain, and whether participation is reported. The warehouse must keep methodology groups separate until the registry proves comparability.
3. **Enrollment coverage is incomplete.** Current district rows have missing enrollment, so population-weighted coverage and enrollment-weighted rankings are not valid yet. The quality layer reports this explicitly rather than estimating it from test counts.
4. **Participation metadata is uneven.** Georgia and Kentucky currently lack participation rates; Tennessee has nearly complete participation locally. This limits national readiness and lowers confidence.
5. **Geography crosswalks need a resolution policy.** Exact NCES-name matches work for the current files, but future school-level files need a documented school-to-district crosswalk and an unmatched/suppressed exception table.

## Modeling safeguards

- SAT and ACT are ranked independently.
- State-relative percentiles rank only non-null observed values; missing values are never treated as zero.
- National-relative percentiles remain disabled unless coverage, participation, and comparability gates pass.
- Historical sources remain append-only; supersession is recorded in lineage.
- The existing score remains 60% academic and 40% community, with community split evenly between income and bachelor's attainment.
- Community percentiles now tolerate one missing demographic component without silently converting it to zero.

## Next improvements

- Add a canonical NCES district snapshot with enrollment and active-year fields.
- Add source-file manifests with retrieval timestamp, byte count, SHA-256, and publisher URL for every loaded artifact.
- Add explicit suppression and geographic-precision columns to normalized adapters.
- Add school-to-district aggregation tests using weighted and unweighted variants.
- Add retry/backoff and content-type/size guards to discovery.
- Schedule the batch discovery notebook before the configured ingestion task, then gate ingestion on `direct_file_candidate` plus a verified registry row.
- Add a coverage dashboard by state, district count, population covered, score year, participation completeness, and methodology group.

## What would block a trustworthy 50-state ranking

The blockers are data availability and methodological comparability—not storage or compute. A state can be onboarded automatically once its official source, vintage, population, grain, aggregation rule, and crosswalk are registered. Until then, it should remain visible as a coverage gap and must not enter the combined ranking.
