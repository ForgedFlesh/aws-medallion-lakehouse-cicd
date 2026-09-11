from __future__ import annotations


import sys
from datetime import datetime, timedelta
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F

from glue_utils import fail_audit, resolve, write_audit

ARGS = resolve([
    "connection_name",
    "data_lake_bucket",
    "audit_table",
    "run_id",
    "processing_date",
    "run_mode",
])
TABLES = [
    "customers", "employees", "offices", "orderdetails",
    "orders", "payments", "productlines", "products",
]

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(ARGS["JOB_NAME"], ARGS)

stage = "rds_landing"

window_start = datetime.strptime(
    ARGS["processing_date"],
    "%Y-%m-%d"
)

window_end = window_start + timedelta(days=1)

window_start_sql = window_start.strftime("%Y-%m-%d %H:%M:%S")
window_end_sql = window_end.strftime("%Y-%m-%d %H:%M:%S")


try:
    total_rows = 0
    write_audit(ARGS["audit_table"], ARGS["run_id"], stage, "RUNNING")
    for table in TABLES:
        sample_query=(
            f"SELECT * FROM {table} WHERE updated_at >= '{window_start_sql}' AND updated_at < '{window_end_sql}'"
        )
        dynamic_frame = glue_context.create_dynamic_frame.from_options(
            connection_type="mysql",
            connection_options={
                "useConnectionProperties": "true",
                "connectionName": ARGS["connection_name"],
                "dbtable": table,
                "sampleQuery": sample_query,
            },
            transformation_ctx=f"read_{table}",
        )
        df = (
            dynamic_frame.toDF()
            .withColumn("ingest_ts", F.current_timestamp())
            .withColumn("source", F.lit("mysql_rds"))
            .withColumn("processing_date", F.lit(ARGS["processing_date"]))
            .withColumn("run_id", F.lit(ARGS["run_id"]))
        )
        count = df.count()
        total_rows += count
        path = (
            f"s3://{ARGS['data_lake_bucket']}/landing_zone/rds/{table}/"
            f"processing_date={ARGS['processing_date']}/"
        )
        df.write.mode("overwrite").option("header", True).csv(path)

    write_audit(
        ARGS["audit_table"], ARGS["run_id"], stage, "SUCCEEDED",
        {"processing_date": ARGS["processing_date"], "run_mode": ARGS["run_mode"], "table_count": len(TABLES), "row_count": total_rows},
    )
    job.commit()
except Exception as exc:
    fail_audit(ARGS["audit_table"], ARGS["run_id"], stage, exc)
    raise
