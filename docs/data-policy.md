# Data policy

## Provenance

Every promoted metric should retain its source ID, URL, retrieval date, score year, definition, population, aggregation method, and confidence.

## History

Source artifacts and observations are append-only. Corrections create a new record and identify the earlier record as superseded; historical records are not deleted.

## Quality

Missingness, suppression, participation, sample size, geographic precision, freshness, and comparability are explicit fields. A missing score is unavailable, not zero.

## Privacy and credentials

Do not commit `.env` files, API keys, access tokens, or private credentials. Raw files should be limited to reproducible source-derived artifacts that are appropriate to retain and redistribute.

## Cost control

Prefer local validation and small API requests before using Databricks compute. Use append-only loads, bounded queries, explicit filters, and the FinOps guardrails before broad refreshes.
