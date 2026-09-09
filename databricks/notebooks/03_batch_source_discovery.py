"""Batch discovery control loop for the national state-source registry.

This notebook does not guess URLs or ingest unverified files. It checks every
verified URL in the registry, records endpoint metadata append-only, and emits
the states that still need official-source configuration. That makes the
workflow self-driving once a source candidate is verified.
"""

import hashlib
from datetime import datetime, timezone

import requests
from pyspark.sql import functions as F


spark.sql("""
CREATE TABLE IF NOT EXISTS living_index.silver.source_discovery_runs (
  checked_at TIMESTAMP,
  source_id STRING,
  source_url STRING,
  http_status INT,
  content_type STRING,
  response_bytes BIGINT,
  response_sha256 STRING,
  discovery_status STRING,
  reason STRING
) USING DELTA
""")

registry = spark.table("living_index.silver.state_source_registry").collect()
checked_at = datetime.now(timezone.utc).replace(tzinfo=None)
results = []
pending = []

for state in registry:
    url = state["source_url"]
    if not url:
        pending.append((state["state_abbr"], state["official_agency"], state["discovery_query"]))
        continue
    source_id = f"state_source_candidate_{state['state_abbr'].lower()}"
    try:
        response = requests.get(
            url, timeout=30, headers={"User-Agent": "LivingIndexSourceMonitor/1.0"}, allow_redirects=True
        )
        body = response.content
        content_type = response.headers.get("content-type", "")[:200]
        if response.status_code >= 400:
            status, reason = "blocked", f"HTTP {response.status_code}"
        elif "text/html" in content_type.lower():
            status, reason = "landing_page", "Reachable official page; file locator still required."
        else:
            status, reason = "direct_file_candidate", "Reachable non-HTML endpoint."
        results.append((checked_at, source_id, url, response.status_code, content_type, len(body),
                        hashlib.sha256(body).hexdigest(), status, reason))
    except Exception as exc:
        results.append((checked_at, source_id, url, None, None, 0, None, "error", str(exc)[:1000]))

if results:
    spark.createDataFrame(
        results,
        "checked_at timestamp, source_id string, source_url string, http_status int, content_type string, "
        "response_bytes long, response_sha256 string, discovery_status string, reason string",
    ).write.mode("append").saveAsTable("living_index.silver.source_discovery_runs")

print(f"Checked {len(results)} configured state source endpoint(s).")
print(f"{len(pending)} states still need an official source URL and verified metric definition.")
for state_abbr, agency, query in pending:
    print(f"PENDING {state_abbr}: {agency} | {query}")
