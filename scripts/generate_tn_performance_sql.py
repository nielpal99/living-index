import csv
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / "work/raw/tn/tn_act_performance_observations.csv"
output = root / "work/raw/tn/tn_act_performance_insert.sql"


def sql_string(value):
    return "NULL" if value == "" else "'" + value.replace("'", "''") + "'"


rows = []
with source.open(newline="") as handle:
    for row in csv.DictReader(handle):
        rows.append("(" + ", ".join([
            sql_string(row["observation_id"]),
            "NULL",
            sql_string(row["nces_district_id"]),
            sql_string(row["test_type"]),
            sql_string(row["metric_name"]),
            row["metric_value"],
            sql_string(row["score_year"]),
            row["students_tested"] if row["students_tested"] else "NULL",
            row["participation_rate"] if row["participation_rate"] else "NULL",
            sql_string(row["aggregation_method"]),
            sql_string(row["source_type"]),
            sql_string(row["source_id"]),
            sql_string(row["confidence"]),
            sql_string(row["notes"]),
            "current_timestamp()",
        ]) + ")")

output.write_text(
    "INSERT INTO living_index.silver.performance_observations VALUES\n"
    + ",\n".join(rows)
    + ";\n"
)
print(f"Wrote {len(rows):,} insert rows to {output}")
