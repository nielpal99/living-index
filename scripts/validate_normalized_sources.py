"""Run a common quality gate over normalized state performance files."""

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config/source_adapters.json"
REQUIRED = {
    "observation_id", "nces_district_id", "test_type", "metric_name", "metric_value",
    "score_year", "students_tested", "participation_rate", "aggregation_method",
    "source_type", "source_id", "confidence",
}


def main() -> None:
    for source in json.loads(CONFIG.read_text()):
        source_id = source["source_id"]
        path = ROOT / source["path"]
        if not path.exists():
            print(f"{source_id}: MISSING FILE {path}")
            continue
        with path.open(newline="") as handle:
            reader = csv.DictReader(handle)
            rows = list(reader)
        missing_columns = sorted(REQUIRED - set(reader.fieldnames or []))
        ids = [row.get("observation_id", "") for row in rows]
        by_test = {}
        for row in rows:
            test = row.get("test_type", "UNKNOWN")
            stats = by_test.setdefault(test, {"scores": [], "missing_sample": 0, "missing_participation": 0})
            try:
                stats["scores"].append(float(row["metric_value"]))
            except (TypeError, ValueError):
                pass
            stats["missing_sample"] += not bool(row.get("students_tested"))
            stats["missing_participation"] += not bool(row.get("participation_rate"))
        test_summary = []
        for test, stats in sorted(by_test.items()):
            scores = stats["scores"]
            score_range = f"{min(scores):.3f}..{max(scores):.3f}" if scores else "none"
            test_summary.append(
                f"{test}:rows={sum(1 for row in rows if row.get('test_type') == test)} "
                f"range={score_range} missing_sample={stats['missing_sample']} "
                f"missing_participation={stats['missing_participation']}"
            )
        invalid_ids = sum(not bool(row.get("nces_district_id")) for row in rows)
        invalid_tests = sum(row.get("test_type") not in {"SAT", "ACT"} for row in rows)
        invalid_sources = sum(row.get("source_id") != source_id for row in rows)
        print(
            f"{source_id}: rows={len(rows)} districts={len(set(ids))} "
            f"duplicate_ids={len(ids) - len(set(ids))} "
            f"adapter={source['adapter_key']} crosswalk={source['crosswalk_rule']} "
            f"group={source['comparability_group']} "
            f"missing_columns={','.join(missing_columns) or 'none'} "
            f"invalid_nces={invalid_ids} invalid_test={invalid_tests} "
            f"wrong_source_id={invalid_sources} | " + " | ".join(test_summary)
        )


if __name__ == "__main__":
    main()
