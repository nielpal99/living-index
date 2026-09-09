# Databricks notebook source
# Load the locally fetched ACS CSV after uploading it to the Unity Catalog volume.

from pyspark.sql import functions as F

ACS_FILE = "/Volumes/workspace/default/raw_sources/acs5_school_district_unified_2023.csv"

raw = spark.read.option("header", "true").option("inferSchema", "true").csv(ACS_FILE)

demographics = (
    raw
    .withColumn("census_geoid", F.concat(
        F.lit("9700000US"),
        F.col("state").cast("string"),
        F.col("school district (unified)").cast("string"),
    ))
    .withColumn("population_25_plus", F.col("B15003_001E").cast("long"))
    .withColumn(
        "bachelors_or_higher_pct",
        F.when(
            F.col("B15003_001E") > 0,
            (
                (F.col("B15003_022E") + F.col("B15003_023E")
                 + F.col("B15003_024E") + F.col("B15003_025E"))
                / F.col("B15003_001E") * 100
            ).cast("decimal(7,3)")
        )
    )
    .select(
        "census_geoid",
        F.lit("2023").alias("acs_vintage"),
        F.col("B19013_001E").cast("decimal(18,2)").alias("median_household_income"),
        "bachelors_or_higher_pct",
        "population_25_plus",
        F.lit(None).cast("decimal(18,2)").alias("income_margin_of_error"),
        F.lit(None).cast("decimal(7,3)").alias("education_margin_of_error"),
        F.lit("acs5_2023_school_district_unified").alias("source_id"),
        F.current_timestamp().alias("loaded_at"),
    )
    .dropDuplicates(["census_geoid"])
)

demographics.write.mode("overwrite").saveAsTable("living_index.silver.demographics")
print("ACS demographic rows written:", demographics.count())
display(demographics.orderBy(F.desc("median_household_income")).limit(20))
