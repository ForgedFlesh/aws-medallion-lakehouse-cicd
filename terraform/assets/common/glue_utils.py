from __future__ import annotations

import sys
import traceback
from datetime import datetime, timezone
from typing import Any

import boto3
from awsglue.utils import getResolvedOptions


def resolve(required: list[str]) -> dict[str, str]:
    return getResolvedOptions(sys.argv, ["JOB_NAME", *required])


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_audit(
    table_name: str,
    run_id: str,
    stage: str,
    status: str,
    metrics: dict[str, Any] | None = None,
    error_message: str = "",
) -> None:

    now = utc_now()

    table = boto3.resource("dynamodb").Table(table_name)

    names = {
        "#status": "status",
    }

    values: dict[str, Any] = {
        ":status": status,
        ":updated_at": now,
    }

    # -------------------------------------------------
    # Job started / restarted
    # -------------------------------------------------

    if status == "RUNNING":

        values[":started_at"] = now

        table.update_item(
            Key={
                "run_id": run_id,
                "stage": stage,
            },
            UpdateExpression=(
                "SET #status = :status, "
                "updated_at = :updated_at, "
                "started_at = if_not_exists(started_at, :started_at) "
                "REMOVE completed_at, error_message"
            ),
            ExpressionAttributeNames=names,
            ExpressionAttributeValues=values,
        )

        return

    # -------------------------------------------------
    # Job completed
    # -------------------------------------------------

    values[":completed_at"] = now

    update_parts = [
        "#status = :status",
        "updated_at = :updated_at",
        "completed_at = :completed_at",
    ]

    # -------------------------------------------------
    # Optional metrics
    # -------------------------------------------------

    if metrics is not None:

        names["#metrics"] = "metrics"

        values[":metrics"] = {
            key: int(value)
            if isinstance(value, (bool, int))
            else str(value)
            for key, value in metrics.items()
        }

        update_parts.append("#metrics = :metrics")

    # -------------------------------------------------
    # Failure message
    # -------------------------------------------------

    if error_message:

        values[":error_message"] = error_message[:3000]

        update_parts.append(
            "error_message = :error_message"
        )

        update_expression = (
            "SET " + ", ".join(update_parts)
        )

    else:

        update_expression = (
            "SET "
            + ", ".join(update_parts)
            + " REMOVE error_message"
        )

    table.update_item(
        Key={
            "run_id": run_id,
            "stage": stage,
        },
        UpdateExpression=update_expression,
        ExpressionAttributeNames=names,
        ExpressionAttributeValues=values,
    )


def fail_audit(
    table_name: str,
    run_id: str,
    stage: str,
    exc: Exception,
) -> None:

    write_audit(
        table_name,
        run_id,
        stage,
        "FAILED",
        error_message=(
            f"{type(exc).__name__}: {exc}\n"
            f"{traceback.format_exc()}"
        ),
    )


def add_reject_reason(df, conditions):

    from pyspark.sql import functions as F

    reason = F.lit(None).cast("string")

    for condition, message in conditions:

        reason = (
            F.when(
                condition,
                F.lit(message),
            )
            .otherwise(reason)
        )

    return df.withColumn(
        "reject_reason",
        reason,
    )