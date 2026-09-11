from __future__ import annotations

import argparse
import time

import boto3


def wait(client, statement_id: str) -> None:
    while True:
        status = client.describe_statement(Id=statement_id)
        if status["Status"] in {"FINISHED", "FAILED", "ABORTED"}:
            if status["Status"] != "FINISHED":
                raise RuntimeError(status.get("Error", status["Status"]))
            return
        time.sleep(2)


def main() -> None:
    parser = argparse.ArgumentParser(description="Create the Spectrum external schema")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--workgroup", required=True)
    parser.add_argument("--database", default="lakehouse")
    parser.add_argument("--curated-database", default="curated_zone")
    parser.add_argument("--iam-role-arn", required=True)
    args = parser.parse_args()

    sql_statements = [
        f"""
        create external schema if not exists lakehouse_external
        from data catalog
        database '{args.curated_database}'
        iam_role '{args.iam_role_arn}'
        region '{args.region}'
        create external database if not exists
        """,
        "create schema if not exists staging",
        "create schema if not exists analytics",
    ]
    client = boto3.client("redshift-data", region_name=args.region)
    response = client.batch_execute_statement(
        WorkgroupName=args.workgroup,
        Database=args.database,
        Sqls=sql_statements,
    )
    wait(client, response["Id"])
    print("Redshift Spectrum and dbt schemas are ready")


if __name__ == "__main__":
    main()
