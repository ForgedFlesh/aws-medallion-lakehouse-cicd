from __future__ import annotations

import json
import os
from urllib.parse import unquote_plus

import boto3

GLUE_JOB_NAME = os.environ["GLUE_JOB_NAME"]
AUDIT_TABLE = os.environ["AUDIT_TABLE"]
DATA_LAKE_BUCKET = os.environ["DATA_LAKE_BUCKET"]

glue = boto3.client("glue")


def lambda_handler(event, context):
    failures = []
    for record in event.get("Records", []):
        message_id = record.get("messageId", "unknown")
        try:
            body = json.loads(record["body"])
            s3_event = json.loads(body.get("Message", record["body"])) if "Message" in body else body
            for item in s3_event.get("Records", []):
                bucket = item["s3"]["bucket"]["name"]
                key = unquote_plus(item["s3"]["object"]["key"])
                event_time = item.get("eventTime", "")
                processing_date = event_time[:10]
                glue.start_job_run(
                    JobName=GLUE_JOB_NAME,
                    Arguments={
                        "--source_bucket": bucket,
                        "--source_prefix": key,
                        "--data_lake_bucket": DATA_LAKE_BUCKET,
                        "--audit_table": AUDIT_TABLE,
                        "--run_id": f"s3-{context.aws_request_id}",
                        "--processing_date": processing_date,
                    },
                )
        except Exception:
            failures.append({"itemIdentifier": message_id})
    return {"batchItemFailures": failures}
