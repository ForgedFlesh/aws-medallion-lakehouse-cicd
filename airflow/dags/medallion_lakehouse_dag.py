from __future__ import annotations

import os
from datetime import datetime, timedelta

import boto3
import pendulum

from airflow import DAG
from airflow.decorators import task
from airflow.exceptions import AirflowException
from airflow.models.param import Param
from airflow.operators.bash import BashOperator
from airflow.operators.python import get_current_context
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.utils.state import TaskInstanceState
from airflow.utils.trigger_rule import TriggerRule


# =========================================================
# ENVIRONMENT / PROJECT CONFIG
# =========================================================

AWS_REGION = os.getenv(
    "AWS_DEFAULT_REGION",
    "us-east-1",
)

DATA_LAKE_BUCKET = os.environ[
    "DATA_LAKE_BUCKET"
]

SCRIPTS_BUCKET = os.environ[
    "SCRIPTS_BUCKET"
]

AUDIT_TABLE = os.getenv(
    "AUDIT_TABLE",
    "medallion-lakehouse-pipeline-audit",
)

CURATED_DATABASE = os.getenv(
    "CURATED_DATABASE",
    "curated_zone",
)

PRESENTATION_DATABASE = os.getenv(
    "PRESENTATION_DATABASE",
    "presentation_zone",
)

ATHENA_WORKGROUP = os.getenv(
    "ATHENA_WORKGROUP",
    "medallion-lakehouse-workgroup",
)


# =========================================================
# AWS GLUE JOB NAMES
# =========================================================

JOB_RDS_INGESTION = (
    "medallion-lakehouse-rds-ingestion-job"
)

JOB_JSON_INGESTION = (
    "medallion-lakehouse-json-ingestion-job"
)

JOB_BATCH_TRANSFORM = (
    "medallion-lakehouse-batch-transform-job"
)

JOB_ML_TRANSFORM = (
    "medallion-lakehouse-ml-transform-job"
)

JOB_RATINGS_ICEBERG = (
    "medallion-lakehouse-ratings-iceberg-job"
)

JOB_QUALITY = (
    "medallion-lakehouse-curated-quality-job"
)


# =========================================================
# PROCESSING DATE
#
# Scheduled run:
#   2026-09-10 02:00 IST
#
# Processes:
#   2026-09-09
#
# Manual run:
#   params.processing_date can override this.
# =========================================================

PROCESSING_DATE_TEMPLATE = (
    "{{ params.processing_date if params.processing_date "
    "else "
    "(data_interval_end - macros.timedelta(days=1))"
    ".strftime('%Y-%m-%d') }}"
)


# =========================================================
# PIPELINE AUDIT
# =========================================================

def _audit(
    dag_run_id: str,
    status: str,
    message: str = "",
) -> None:

    table = boto3.resource(
        "dynamodb",
        region_name=AWS_REGION,
    ).Table(AUDIT_TABLE)

    now = (
        datetime.utcnow()
        .isoformat(timespec="seconds")
        + "Z"
    )

    values = {
        ":status": status,
        ":updated_at": now,
        ":message": message[:1000],
    }

    updates = [
        "#status = :status",
        "updated_at = :updated_at",
        "message = :message",
    ]

    if status == "RUNNING":

        values[":started_at"] = now

        updates.append(
            "started_at = "
            "if_not_exists(started_at, :started_at)"
        )

    else:

        values[":completed_at"] = now

        updates.append(
            "completed_at = :completed_at"
        )

    table.update_item(
        Key={
            "run_id": dag_run_id,
            "stage": "airflow_dag",
        },
        UpdateExpression=(
            "SET " + ", ".join(updates)
        ),
        ExpressionAttributeNames={
            "#status": "status",
        },
        ExpressionAttributeValues=values,
    )


# =========================================================
# DAG
# =========================================================

with DAG(

    dag_id="medallion_lakehouse",

    description=(
        "RDS and ratings JSON to S3, "
        "Iceberg, Athena and dbt marts"
    ),

    start_date=pendulum.datetime(
        2025,
        1,
        1,
        2,
        0,
        tz="Asia/Kolkata",
    ),

    # Every day at 02:00 AM IST.
    # Processes previous calendar day.
    schedule="0 2 * * *",

    catchup=False,

    max_active_runs=1,

    default_args={
        "owner": "data-engineering",
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
        "execution_timeout": timedelta(hours=2),
    },

    params={

        "processing_date": Param(
            default="",
            type="string",
            description=(
                "Optional YYYY-MM-DD override. "
                "Blank means previous calendar day "
                "for scheduled runs."
            ),
        ),

        "run_mode": Param(
            default="incremental",
            enum=[
                "incremental",
                "backfill",
            ],
            description=(
                "Incremental daily run "
                "or explicit backfill"
            ),
        ),
    },

    tags=[
        "aws",
        "glue",
        "iceberg",
        "athena",
        "dbt",
    ],

) as dag:


    # =====================================================
    # PIPELINE START AUDIT
    # =====================================================

    @task
    def mark_started(
        dag_run_id: str,
    ) -> None:

        _audit(
            dag_run_id,
            "RUNNING",
        )

    # =====================================================
    # PIPELINE END AUDIT
    # =====================================================

    @task(
        trigger_rule=TriggerRule.ALL_DONE
    )
    def mark_finished(
        dag_run_id: str,
    ) -> None:

        context = get_current_context()
        dag_run = context["dag_run"]

        failed_tasks = [
            task_instance.task_id
            for task_instance in dag_run.get_task_instances()
            if task_instance.task_id != "mark_finished"
            and task_instance.state
            in {
                TaskInstanceState.FAILED,
                TaskInstanceState.UPSTREAM_FAILED,
            }
        ]

        if failed_tasks:

            message = (
                "Failed or upstream-failed tasks: "
                + ", ".join(sorted(failed_tasks))
            )

            _audit(
                dag_run_id,
                "FAILED",
                message,
            )

            raise AirflowException(message)

        _audit(
            dag_run_id,
            "SUCCEEDED",
            "All pipeline stages completed successfully",
        )


    # =====================================================
    # COMMON GLUE ARGUMENTS
    # =====================================================

    common_args = {

        "--run_id":
            "{{ run_id }}",

        "--processing_date":
            PROCESSING_DATE_TEMPLATE,

        "--run_mode":
            "{{ params.run_mode }}",

        "--data_lake_bucket":
            DATA_LAKE_BUCKET,

        "--audit_table":
            AUDIT_TABLE,
    }


    # =====================================================
    # START
    # =====================================================

    started = mark_started(
        dag_run_id="{{ run_id }}"
    )


    # =====================================================
    # RDS INCREMENTAL INGESTION
    # =====================================================

    ingest_rds = GlueJobOperator(

        task_id="ingest_rds_tables",

        job_name=JOB_RDS_INGESTION,

        script_args=common_args,

        wait_for_completion=True,

        region_name=AWS_REGION,

        verbose=True,
    )


    # =====================================================
    # JSON RATINGS INGESTION
    # =====================================================

    ingest_ratings = GlueJobOperator(

        task_id="ingest_ratings_json",

        job_name=JOB_JSON_INGESTION,

        script_args=common_args,

        wait_for_completion=True,

        region_name=AWS_REGION,

        verbose=True,
    )


    # =====================================================
    # RELATIONAL TRANSFORMATION
    # =====================================================

    transform_relational = GlueJobOperator(

        task_id="transform_relational_tables",

        job_name=JOB_BATCH_TRANSFORM,

        script_args={
            **common_args,

            "--curated_database":
                CURATED_DATABASE,
        },

        wait_for_completion=True,

        region_name=AWS_REGION,

        verbose=True,
    )


    # =====================================================
    # RATINGS FOR ML ICEBERG
    # =====================================================

    build_ratings_for_ml = GlueJobOperator(

        task_id="build_ratings_for_ml",

        job_name=JOB_ML_TRANSFORM,

        script_args={
            **common_args,

            "--curated_database":
                CURATED_DATABASE,
        },

        wait_for_completion=True,

        region_name=AWS_REGION,

        verbose=True,
    )


    # =====================================================
    # CURRENT-STATE RATINGS ICEBERG
    # =====================================================

    merge_ratings_iceberg = GlueJobOperator(

        task_id="merge_ratings_iceberg",

        job_name=JOB_RATINGS_ICEBERG,

        script_args={
            **common_args,

            "--curated_database":
                CURATED_DATABASE,
        },

        wait_for_completion=True,

        region_name=AWS_REGION,

        verbose=True,
    )


    # =====================================================
    # CURATED DATA QUALITY
    # =====================================================

    quality_checks = GlueJobOperator(

        task_id="curated_quality_checks",

        job_name=JOB_QUALITY,

        script_args={
            **common_args,

            "--curated_database":
                CURATED_DATABASE,
        },

        wait_for_completion=True,

        region_name=AWS_REGION,

        verbose=True,
    )


    # =====================================================
    # ATHENA PRESENTATION LAYER
    # =====================================================

    refresh_athena_presentation = BashOperator(

        task_id="refresh_athena_presentation",

        bash_command=(

            "python "
            "/opt/airflow/scripts/"
            "run_presentation_queries.py "

            '--aws-region '
            '"$AWS_DEFAULT_REGION" '

            '--workgroup '
            '"$ATHENA_WORKGROUP" '

            '--data-lake-bucket-name '
            '"$DATA_LAKE_BUCKET" '

            '--curated-database-name '
            '"$CURATED_DATABASE" '

            '--presentation-database-name '
            '"$PRESENTATION_DATABASE"'
        ),

        env={
            "AWS_DEFAULT_REGION":
                AWS_REGION,

            "ATHENA_WORKGROUP":
                ATHENA_WORKGROUP,

            "DATA_LAKE_BUCKET":
                DATA_LAKE_BUCKET,

            "CURATED_DATABASE":
                CURATED_DATABASE,

            "PRESENTATION_DATABASE":
                PRESENTATION_DATABASE,
        },

        append_env=True,
    )


    # =====================================================
    # DBT ATHENA BUILD
    # =====================================================

    dbt_build = BashOperator(

        task_id="dbt_build_athena_star_schema",

        bash_command=(

            "cd /opt/airflow/dbt && "

            "dbt deps "
            "--profiles-dir . && "

            "dbt build "
            "--profiles-dir . "
            "--target prod "

            "--vars "
            "'{processing_date: \""

            + PROCESSING_DATE_TEMPLATE

            + "\"}'"
        ),

        env={
            "AWS_DEFAULT_REGION":
                AWS_REGION,

            "ATHENA_WORKGROUP":
                ATHENA_WORKGROUP,

            "DATA_LAKE_BUCKET":
                DATA_LAKE_BUCKET,

            "SCRIPTS_BUCKET":
                SCRIPTS_BUCKET,
        },

        append_env=True,
    )


    # =====================================================
    # FINISH
    # =====================================================

    finished = mark_finished(
        dag_run_id="{{ run_id }}"
    )


    # =====================================================
    # TASK DEPENDENCIES
    # =====================================================

    started >> [
        ingest_rds,
        ingest_ratings,
    ]

    [
        ingest_rds,
        ingest_ratings,
    ] >> transform_relational

    (
        transform_relational
        >> build_ratings_for_ml
        >> merge_ratings_iceberg
        >> quality_checks
        >> refresh_athena_presentation
        >> dbt_build
        >> finished
    )