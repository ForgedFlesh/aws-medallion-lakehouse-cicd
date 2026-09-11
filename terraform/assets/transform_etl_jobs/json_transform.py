from __future__ import annotations

from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import Window
from pyspark.sql import functions as F
from pyspark.sql.types import IntegerType, LongType, StringType, StructField, StructType, TimestampType

from glue_utils import fail_audit, resolve, write_audit

ARGS = resolve([
    "data_lake_bucket", "audit_table", "run_id", "processing_date", "run_mode", "curated_database", "lakehouse_path"
])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(ARGS["JOB_NAME"], ARGS)
stage = "ratings_for_ml_transform"

try:
    write_audit(ARGS["audit_table"], ARGS["run_id"], stage, "RUNNING")
    ratings = spark.read.json(
        f"s3://{ARGS['data_lake_bucket']}/landing_zone/json/ratings/"
        f"processing_date={ARGS['processing_date']}/"
    )
    typed = (
        ratings
        .withColumn("customerNumber", F.col("customerNumber").cast("bigint"))
        .withColumn("productCode", F.trim(F.col("productCode")).cast("string"))
        .withColumn("productRating", F.col("productRating").cast("int"))
        .withColumn("ratingTimestamp", F.coalesce(F.col("ratingTimestamp").cast("timestamp"), F.col("ingest_ts").cast("timestamp")))
        .withColumn("ingest_ts", F.col("ingest_ts").cast("timestamp"))
        .withColumn("processing_date", F.lit(ARGS["processing_date"]))
    )
    invalid = (
        F.col("customerNumber").isNull()
        | F.col("productCode").isNull()
        | ~F.col("productRating").between(1, 5)
    )
    rejected = (
        typed.filter(invalid)
        .withColumn(
            "reject_reason",
            F.when(F.col("customerNumber").isNull(), "customerNumber is null")
             .when(F.col("productCode").isNull(), "productCode is null")
             .otherwise("productRating must be between 1 and 5"),
        )
    )
    candidates = typed.filter(~invalid)
    duplicate_window = Window.partitionBy("customerNumber", "productCode", "ratingTimestamp").orderBy(
        F.col("ingest_ts").desc_nulls_last(), F.col("source").desc_nulls_last()
    )
    ranked = candidates.withColumn("_row_number", F.row_number().over(duplicate_window))
    valid = ranked.filter(F.col("_row_number") == 1).drop("_row_number")
    duplicate_rejected = (
        ranked.filter(F.col("_row_number") > 1)
        .drop("_row_number")
        .withColumn("reject_reason", F.lit("duplicate rating event in the same batch"))
    )

    customer_window = Window.partitionBy(
        "customerNumber"
    ).orderBy(
        F.col("processing_date").desc(),
        F.col("ingest_ts").desc_nulls_last()
    )

    customers = (
        spark.table(
            f"{ARGS['curated_database']}.customers"
        )
        .withColumn(
            "_row_number",
            F.row_number().over(customer_window)
        )
        .filter(F.col("_row_number") == 1)
        .drop("_row_number")
    )
    product_window = Window.partitionBy(
            "productCode"
        ).orderBy(F.col("processing_date").desc(),F.col("ingest_ts").desc_nulls_last())
    products = (
        spark.table(
            f"{ARGS['curated_database']}.products"
        )
        .withColumn(
            "_row_number",
            F.row_number().over(product_window)
        )
        .filter(F.col("_row_number") == 1)
        .drop("_row_number")
    )
    known = valid.join(customers.select("customerNumber"), "customerNumber", "inner")
    known = known.join(products.select("productCode", "productName", "productLine"), "productCode", "inner")
    unknown = valid.join(customers.select("customerNumber"), "customerNumber", "left_anti")
    unknown = unknown.unionByName(
        valid.join(products.select("productCode"), "productCode", "left_anti"), allowMissingColumns=True
    ).dropDuplicates(["customerNumber", "productCode", "ratingTimestamp"])
    unknown = unknown.withColumn("reject_reason", F.lit("customer or product not found in curated master data"))
    all_rejected = (
        rejected.unionByName(duplicate_rejected, allowMissingColumns=True)
        .unionByName(unknown, allowMissingColumns=True)
    )

    rejected_count = all_rejected.count()
    if rejected_count:
        all_rejected.write.mode("overwrite").parquet(
            f"s3://{ARGS['data_lake_bucket']}/rejected_zone/ratings/"
            f"processing_date={ARGS['processing_date']}/run_id={ARGS['run_id']}/"
        )

    known.createOrReplaceTempView("ratings_for_ml_batch")
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS glue_catalog.{ARGS['curated_database']}.ratings_for_ml (
            customerNumber BIGINT,
            productCode STRING,
            productName STRING,
            productLine STRING,
            productRating INT,
            ratingTimestamp TIMESTAMP,
            ingest_ts TIMESTAMP,
            source STRING,
            processing_date STRING,
            processing_ts TIMESTAMP
        ) USING iceberg
        LOCATION '{ARGS['lakehouse_path'].rstrip('/')}/ratings_for_ml/iceberg'
        PARTITIONED BY (processing_date)
        TBLPROPERTIES ('format-version'='2')
    """)
    spark.sql(f"""
        MERGE INTO glue_catalog.{ARGS['curated_database']}.ratings_for_ml t
        USING (
            SELECT customerNumber, productCode, productName, productLine,
                   productRating, ratingTimestamp, cast(ingest_ts as timestamp) ingest_ts,
                   source, processing_date, current_timestamp() processing_ts
            FROM ratings_for_ml_batch
        ) s
        ON t.customerNumber = s.customerNumber
       AND t.productCode = s.productCode
       AND t.ratingTimestamp = s.ratingTimestamp
        WHEN MATCHED THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
    """)
    write_audit(
        ARGS["audit_table"], ARGS["run_id"], stage,
        "SUCCEEDED" if rejected_count == 0 else "SUCCEEDED_WITH_REJECTS",
        {
            "processing_date": ARGS["processing_date"],
            "run_mode": ARGS["run_mode"],
            "valid_rows": known.count(),
            "rejected_rows": rejected_count,
        },
    )
    job.commit()
except Exception as exc:
    fail_audit(ARGS["audit_table"], ARGS["run_id"], stage, exc)
    raise
