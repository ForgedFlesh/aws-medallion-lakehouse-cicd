from __future__ import annotations

import argparse
import pathlib
import time

import boto3

ORDERED_SQL_FILES = [
    "ratings.sql.tftpl",
    "ratings_for_ml.sql.tftpl",
    "sales_report.sql.tftpl",
    "ratings_per_product.sql.tftpl",
]


def wait_for_query(athena, execution_id: str) -> None:
    while True:
        execution = athena.get_query_execution(QueryExecutionId=execution_id)["QueryExecution"]
        state = execution["Status"]["State"]
        if state in {"SUCCEEDED", "FAILED", "CANCELLED"}:
            if state != "SUCCEEDED":
                reason = execution["Status"].get("StateChangeReason", "")
                raise RuntimeError(f"Athena query {execution_id} ended as {state}: {reason}")
            return
        time.sleep(3)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--aws-region", default="us-east-1")
    parser.add_argument("--workgroup", required=True)
    parser.add_argument("--data-lake-bucket-name", required=True)
    parser.add_argument("--curated-database-name", default="curated_zone")
    parser.add_argument("--presentation-database-name", default="presentation_zone")
    args = parser.parse_args()

    athena = boto3.client("athena", region_name=args.aws_region)
    sql_dir = pathlib.Path(__file__).resolve().parents[1] / "presentation_sql"
    values = {
        "data_lake_bucket_name": args.data_lake_bucket_name,
        "curated_database_name": args.curated_database_name,
        "presentation_database_name": args.presentation_database_name,
    }

    for filename in ORDERED_SQL_FILES:
        sql = (sql_dir / filename).read_text(encoding="utf-8")
        for key, value in values.items():
            sql = sql.replace("${" + key + "}", value)
        table_name = filename.split(".")[0]
        statements = [statement.strip() for statement in sql.split(";") if statement.strip()]
        for statement in statements:
            response = athena.start_query_execution(
                QueryString=statement,
                QueryExecutionContext={"Database": args.presentation_database_name},
                WorkGroup=args.workgroup,
            )
            wait_for_query(athena, response["QueryExecutionId"])
            print(f"Completed {table_name}: {response['QueryExecutionId']}")


if __name__ == "__main__":
    main()
