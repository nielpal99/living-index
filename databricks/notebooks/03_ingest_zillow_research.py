# Databricks notebook source
# Load an official Zillow Research CSV uploaded to the Unity Catalog volume.
# Keep the source geography intact; mapping to districts requires a separate crosswalk.

from pathlib import Path
from pyspark.sql import functions as F

ZILLOW_ROOT = "/Volumes/workspace/default/raw_sources/zillow"
SOURCE_ID = "zillow_research_public_metrics"

files = [p.path for p in dbutils.fs.ls(ZILLOW_ROOT) if p.path.lower().endswith((".csv", ".csv.gz"))]
if not files:
    raise RuntimeError("Upload an official Zillow Research CSV into the raw_sources/zillow volume folder first.")

raw = spark.read.option("header", "true").option("inferSchema", "true").csv(files[0])
print("Loaded:", files[0])
print("Columns:", raw.columns)
display(raw.limit(20))

# The Zillow Research catalog contains multiple products with different schemas.
# Normalize each selected product into housing_metrics only after its geography and
# metric columns have been confirmed above.
