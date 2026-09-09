"""Check configured source endpoints and append discovery results.

This intentionally checks landing pages and direct files without changing
source records. Download/normalization remains a separate adapter step.
"""

import hashlib
from datetime import datetime, timezone

import requests


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

checked_at = datetime.now(timezone.utc).replace(tzinfo=None)
registry = spark.table("living_index.silver.source_registry").where("active_flag = true").collect()
results = []

for source in registry:
    try:
        response = requests.get(
            source["source_url"],
            timeout=30,
            headers={"User-Agent": "LivingIndexSourceMonitor/1.0"},
            allow_redirects=True,
        )
        body = response.content
        content_type = response.headers.get("content-type", "")[:200]
        if response.status_code >= 400:
            status, reason = "blocked", f"HTTP {response.status_code}"
        elif "text/html" in content_type.lower():
            status, reason = "landing_page", "Source page reachable; file locator required."
        else:
            status, reason = "direct_file_candidate", "Endpoint reachable and not HTML."
        results.append((checked_at, source["source_id"], source["source_url"], response.status_code,
                        content_type, len(body), hashlib.sha256(body).hexdigest(), status, reason))
    except Exception as exc:
        results.append((checked_at, source["source_id"], source["source_url"], None, None, 0, None,
                        "error", str(exc)[:1000]))

spark.createDataFrame(
    results,
    "checked_at timestamp, source_id string, source_url string, http_status int, content_type string, "
    "response_bytes long, response_sha256 string, discovery_status string, reason string",
).write.mode("append").saveAsTable("living_index.silver.source_discovery_runs")

print(f"Checked {len(results)} configured source endpoint(s); results appended.")
