from __future__ import annotations

from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from awsglue.job import Job
import boto3
from pyspark.context import SparkContext
from pyspark.sql import Window
from pyspark.sql import functions as F

from glue_utils import fail_audit, resolve, write_audit
"""
landing_zone/rds/<table>/
        ↓
read CSV
        ↓
cast schema
        ↓
business-rule validation
        ↓
deduplicate by primary key
        ↓
valid rows → curated_zone as Parquet
bad rows   → rejected_zone
        ↓
update Glue Catalog
        ↓
audit DynamoDB
"""

ARGS = resolve([
    "data_lake_bucket", "audit_table", "run_id", "processing_date", "run_mode", "curated_database"
])

TABLE_RULES = {
    "customers": [("customerNumber", "bigint"), ("customerName", "string"), ("creditLimit", "double")],
    "employees": [("employeeNumber", "bigint"), ("lastName", "string"), ("firstName", "string")],
    "offices": [("officeCode", "string"), ("city", "string"), ("country", "string")],
    "orderdetails": [("orderNumber", "bigint"), ("productCode", "string"), ("quantityOrdered", "int"), ("priceEach", "double"), ("orderLineNumber", "int")],
    "orders": [("orderNumber", "bigint"), ("orderDate", "date"), ("status", "string"), ("customerNumber", "bigint")],
    "payments": [("customerNumber", "bigint"), ("checkNumber", "string"), ("paymentDate", "date"), ("amount", "double")],
    "productlines": [("productLine", "string"), ("textDescription", "string")],
    "products": [("productCode", "string"), ("productName", "string"), ("productLine", "string"), ("quantityInStock", "int"), ("buyPrice", "double"), ("MSRP", "double")],
}
PRIMARY_KEYS = {
    "customers": ["customerNumber"], "employees": ["employeeNumber"],
    "offices": ["officeCode"], "orderdetails": ["orderNumber", "orderLineNumber"],
    "orders": ["orderNumber"], "payments": ["customerNumber", "checkNumber"],
    "productlines": ["productLine"], "products": ["productCode"],
}

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(ARGS["JOB_NAME"], ARGS)
stage = "batch_transform"
s3 = boto3.client("s3")


def delete_s3_prefix(bucket: str, prefix: str) -> None:
    paginator = s3.get_paginator("list_objects_v2")

    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        objects = [
            {"Key": obj["Key"]}
            for obj in page.get("Contents", [])
        ]

        if objects:
            s3.delete_objects(
                Bucket=bucket,
                Delete={"Objects": objects}
            )

try:
    write_audit(ARGS["audit_table"], ARGS["run_id"], stage, "RUNNING")
    valid_total = 0
    rejected_total = 0
#reading the tables from landing zone and then casting the schema, validating the business rules,
#  deduplicating by primary key, and writing valid rows to curated zone and bad rows to rejected zone
    for table, schema in TABLE_RULES.items():
        source = (
            f"s3://{ARGS['data_lake_bucket']}/landing_zone/rds/{table}/"
            f"processing_date={ARGS['processing_date']}/"
        )
        df = spark.read.option("header", True).csv(source)
        for column, data_type in schema:
            if column in df.columns:
                df = df.withColumn(column, F.col(column).cast(data_type))
        if "ingest_ts" in df.columns:
            df = df.withColumn("ingest_ts", F.col("ingest_ts").cast("timestamp"))

        if "updated_at" in df.columns:
            df = df.withColumn("updated_at", F.col("updated_at").cast("timestamp"))

        invalid = F.lit(False)
        reasons = []
        for key in PRIMARY_KEYS[table]:
            invalid = invalid | F.col(key).isNull()
            reasons.append(F.when(F.col(key).isNull(), F.lit(f"{key} is null")))
        if table == "orderdetails":
            invalid = invalid | F.col("quantityOrdered").isNull() | F.col("priceEach").isNull()
            invalid = invalid | (F.col("quantityOrdered") <= 0) | (F.col("priceEach") < 0)
            reasons.extend([
                F.when(F.col("quantityOrdered").isNull(), F.lit("quantityOrdered is null or not numeric")),
                F.when(F.col("priceEach").isNull(), F.lit("priceEach is null or not numeric")),
                F.when(F.col("quantityOrdered") <= 0, F.lit("quantityOrdered must be positive")),
                F.when(F.col("priceEach") < 0, F.lit("priceEach cannot be negative")),
            ])
        if table == "payments":
            invalid = invalid | F.col("amount").isNull() | (F.col("amount") < 0)
            reasons.extend([
                F.when(F.col("amount").isNull(), F.lit("amount is null or not numeric")),
                F.when(F.col("amount") < 0, F.lit("amount cannot be negative")),
            ])
        if table == "products":
            invalid = invalid | F.col("quantityInStock").isNull() | F.col("buyPrice").isNull() | F.col("MSRP").isNull()
            invalid = invalid | (F.col("quantityInStock") < 0) | (F.col("buyPrice") < 0) | (F.col("MSRP") < 0)
            reasons.extend([
                F.when(F.col("quantityInStock").isNull(), F.lit("quantityInStock is null or not numeric")),
                F.when(F.col("buyPrice").isNull(), F.lit("buyPrice is null or not numeric")),
                F.when(F.col("MSRP").isNull(), F.lit("MSRP is null or not numeric")),
                F.when(F.col("quantityInStock") < 0, F.lit("quantityInStock cannot be negative")),
                F.when(F.col("buyPrice") < 0, F.lit("buyPrice cannot be negative")),
                F.when(F.col("MSRP") < 0, F.lit("MSRP cannot be negative")),
            ])

        business_rejected = (
            df.filter(invalid)
            .withColumn("reject_reason", F.concat_ws("; ", *reasons) if reasons else F.lit("business rule failed"))
        )
        candidates = df.filter(~invalid)
        tie_breaker_columns = [F.coalesce(F.col(column).cast("string"), F.lit("")) for column in sorted(df.columns)]
        duplicate_window = Window.partitionBy(*PRIMARY_KEYS[table]).orderBy(
            F.col("ingest_ts").desc_nulls_last(),
            F.xxhash64(*tie_breaker_columns).desc(),
        )
        ranked = candidates.withColumn("_row_number", F.row_number().over(duplicate_window))
        valid_df = ranked.filter(F.col("_row_number") == 1).drop("_row_number")
        duplicate_rejected = (
            ranked.filter(F.col("_row_number") > 1)
            .drop("_row_number")
            .withColumn("reject_reason", F.lit("duplicate business key in the same batch"))
        )
        rejected_df = (
            business_rejected.unionByName(duplicate_rejected, allowMissingColumns=True)
            .withColumn("rejected_at", F.current_timestamp())
        )
        valid_count = valid_df.count()
        rejected_count = rejected_df.count()
        valid_total += valid_count
        rejected_total += rejected_count

        if rejected_count:
            rejected_df.write.mode("overwrite").parquet(
                f"s3://{ARGS['data_lake_bucket']}/rejected_zone/{table}/"
                f"processing_date={ARGS['processing_date']}/run_id={ARGS['run_id']}/"
            )

        enriched = (
            valid_df.withColumn("processing_date", F.lit(ARGS["processing_date"]))
            .withColumn("curated_ts", F.current_timestamp())
            .withColumn("source", F.lit("landing_rds"))
        )
        curated_partition_prefix = (
            f"curated_zone/{table}/"
            f"processing_date={ARGS['processing_date']}/"
        )

        delete_s3_prefix(
            ARGS["data_lake_bucket"],
            curated_partition_prefix,
        )
        
        dynamic_frame = DynamicFrame.fromDF(enriched, glue_context, f"{table}_curated")
        sink = glue_context.getSink(
            connection_type="s3",
            path=f"s3://{ARGS['data_lake_bucket']}/curated_zone/{table}/",
            enableUpdateCatalog=True,
            updateBehavior="UPDATE_IN_DATABASE",
            partitionKeys=["processing_date"],
            transformation_ctx=f"sink_{table}",
        )
        sink.setCatalogInfo(catalogDatabase=ARGS["curated_database"], catalogTableName=table)
        sink.setFormat("glueparquet", compression="snappy")
        sink.writeFrame(dynamic_frame)

    status = "SUCCEEDED" if rejected_total == 0 else "SUCCEEDED_WITH_REJECTS"
    write_audit(
        ARGS["audit_table"], ARGS["run_id"], stage, status,
        {
            "processing_date": ARGS["processing_date"],
            "run_mode": ARGS["run_mode"],
            "valid_rows": valid_total,
            "rejected_rows": rejected_total,
        },
    )
    job.commit()
except Exception as exc:
    fail_audit(ARGS["audit_table"], ARGS["run_id"], stage, exc)
    raise
