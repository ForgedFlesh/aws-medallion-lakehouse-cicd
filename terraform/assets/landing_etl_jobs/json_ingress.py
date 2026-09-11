from __future__ import annotations

from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F

from glue_utils import fail_audit, resolve, write_audit

ARGS = resolve([
    "source_bucket",
    "source_prefix",
    "data_lake_bucket",
    "audit_table",
    "run_id",
    "processing_date",
    "run_mode",
])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(ARGS["JOB_NAME"], ARGS)
stage = "ratings_json_landing"

try:
    write_audit(ARGS["audit_table"], ARGS["run_id"], stage, "RUNNING")
    source = (
    f"s3://{ARGS['source_bucket']}/{ARGS['source_prefix'].strip('/')}/"
    f"processing_date={ARGS['processing_date']}/"
    )
    df = (
        spark.read.option("multiLine", True).json(source)
        .withColumn("ingest_ts", F.current_timestamp())
        .withColumn("source", F.input_file_name())
        .withColumn("processing_date", F.lit(ARGS["processing_date"]))
        .withColumn("run_id", F.lit(ARGS["run_id"]))
    )
    row_count = df.count()
    target = (
        f"s3://{ARGS['data_lake_bucket']}/landing_zone/json/ratings/"
        f"processing_date={ARGS['processing_date']}/"
    )
    df.write.mode("overwrite").json(target)
    write_audit(
        ARGS["audit_table"], ARGS["run_id"], stage, "SUCCEEDED",
        {"processing_date": ARGS["processing_date"], "run_mode": ARGS["run_mode"], "row_count": row_count},
    )
    job.commit()
except Exception as exc:
    fail_audit(ARGS["audit_table"], ARGS["run_id"], stage, exc)
    raise
