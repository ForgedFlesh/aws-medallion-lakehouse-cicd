from __future__ import annotations

from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import Window
from pyspark.sql import functions as F

from glue_utils import fail_audit, resolve, write_audit

ARGS = resolve([
    "data_lake_bucket", "audit_table", "run_id", "processing_date", "run_mode", "curated_database", "lakehouse_path"
])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(ARGS["JOB_NAME"], ARGS)
stage = "ratings_iceberg_merge"

try:
    write_audit(ARGS["audit_table"], ARGS["run_id"], stage, "RUNNING")
    batch = spark.table(f"glue_catalog.{ARGS['curated_database']}.ratings_for_ml").filter(
        F.col("processing_date") == ARGS["processing_date"]
    )
    window = Window.partitionBy("customerNumber", "productCode").orderBy(F.col("ratingTimestamp").desc(), F.col("ingest_ts").desc())
    latest = (
        batch.withColumn("row_number", F.row_number().over(window))
        .filter(F.col("row_number") == 1)
        .drop("row_number", "productName", "productLine", "processing_ts")
    )
    latest.createOrReplaceTempView("latest_ratings")
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS glue_catalog.{ARGS['curated_database']}.ratings (
            customerNumber BIGINT,
            productCode STRING,
            productRating INT,
            ratingTimestamp TIMESTAMP,
            ingest_ts TIMESTAMP,
            source STRING,
            processing_date STRING
        ) USING iceberg
        LOCATION '{ARGS['lakehouse_path'].rstrip('/')}/ratings/iceberg'
        TBLPROPERTIES ('format-version'='2')
    """)
    spark.sql(f"""
        MERGE INTO glue_catalog.{ARGS['curated_database']}.ratings t
        USING latest_ratings s
        ON t.customerNumber = s.customerNumber AND t.productCode = s.productCode
        WHEN MATCHED AND s.ratingTimestamp >= t.ratingTimestamp THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
    """)
    write_audit(
        ARGS["audit_table"], ARGS["run_id"], stage, "SUCCEEDED",
        {"processing_date": ARGS["processing_date"], "run_mode": ARGS["run_mode"], "merged_rows": latest.count()},
    )
    job.commit()
except Exception as exc:
    fail_audit(ARGS["audit_table"], ARGS["run_id"], stage, exc)
    raise
