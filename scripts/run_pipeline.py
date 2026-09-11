from __future__ import annotations

import argparse
import time
from typing import Iterable

import boto3

LANDING_JOBS = [
    "medallion-lakehouse-rds-ingestion-job",
    "medallion-lakehouse-json-ingestion-job",
]
TRANSFORM_JOBS = [
    "medallion-lakehouse-batch-transform-job",
    "medallion-lakehouse-ml-transform-job",
    "medallion-lakehouse-ratings-iceberg-job",
    "medallion-lakehouse-curated-quality-job",
]


def start_and_wait(glue, job_name: str, arguments: dict[str, str]) -> None:
    response = glue.start_job_run(JobName=job_name, Arguments=arguments)
    job_run_id = response["JobRunId"]
    print(f"Started {job_name}: {job_run_id}")
    while True:
        run = glue.get_job_run(JobName=job_name, RunId=job_run_id)["JobRun"]
        state = run["JobRunState"]
        print(f"{job_name}: {state}")
        if state in {"SUCCEEDED", "FAILED", "STOPPED", "TIMEOUT", "ERROR"}:
            if state != "SUCCEEDED":
                raise RuntimeError(f"{job_name} failed with state {state}: {run.get('ErrorMessage', '')}")
            return
        time.sleep(20)


def run_jobs(glue, jobs: Iterable[str], arguments: dict[str, str]) -> None:
    for job in jobs:
        start_and_wait(glue, job, arguments)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--aws-region", default="us-east-1")
    parser.add_argument("--data-lake-bucket-name", required=True)
    parser.add_argument("--audit-table", default="medallion-lakehouse-pipeline-audit")
    parser.add_argument("--processing-date", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-mode", choices=["incremental", "backfill"], default="incremental")
    parser.add_argument("--skip-presentation", action="store_true")
    args = parser.parse_args()

    glue = boto3.client("glue", region_name=args.aws_region)
    common = {
        "--data_lake_bucket": args.data_lake_bucket_name,
        "--audit_table": args.audit_table,
        "--processing_date": args.processing_date,
        "--run_id": args.run_id,
        "--run_mode": args.run_mode,
    }
    run_jobs(glue, LANDING_JOBS, common)
    run_jobs(glue, TRANSFORM_JOBS, common)
    print("Glue pipeline completed successfully")


if __name__ == "__main__":
    main()
