"""Static contract checks for the state-adapter pipeline."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
config = json.loads((ROOT / "config/source_adapters.json").read_text())
required_config = {"source_id", "state_abbr", "path", "adapter_key", "crosswalk_rule", "comparability_group"}
errors = []
seen = set()
for source in config:
    missing = required_config - source.keys()
    if missing:
        errors.append(f"{source.get('source_id', '<unknown>')}: missing config {sorted(missing)}")
    if source.get("source_id") in seen:
        errors.append(f"duplicate source_id: {source['source_id']}")
    seen.add(source.get("source_id"))
    if not (ROOT / source["path"]).exists():
        errors.append(f"{source['source_id']}: missing artifact {source['path']}")

sql = (ROOT / "databricks/sql/06_audited_rankings_and_validation.sql").read_text()
for required in ("sat_percentile_state_relative", "act_percentile_state_relative", "academic_community_gap", "eligible_for_default_v1"):
    if required not in sql:
        errors.append(f"ranking contract missing {required}")

if errors:
    raise SystemExit("\n".join(errors))
print(f"Backend contract passed for {len(config)} configured source adapters.")
