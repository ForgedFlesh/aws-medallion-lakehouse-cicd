from __future__ import annotations

from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F

from glue_utils import fail_audit, resolve, write_audit

ARGS = resolve(
    [
        "data_lake_bucket",
        "audit_table",
        "run_id",
        "processing_date",
        "run_mode",
        "curated_database",
    ]
)

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session

job = Job(glue_context)
job.init(ARGS["JOB_NAME"], ARGS)

stage = "curated_quality_checks"

try:
    write_audit(
        ARGS["audit_table"],
        ARGS["run_id"],
        stage,
        "RUNNING",
    )

    current_date = ARGS["processing_date"]

    # ---------------------------------------------------------
    # Read only the rows processed/changed in the current run
    # ---------------------------------------------------------

    customers_today = (
        spark.table(
            f"{ARGS['curated_database']}.customers"
        )
        .filter(
            F.col("processing_date") == current_date
        )
    )

    products_today = (
        spark.table(
            f"{ARGS['curated_database']}.products"
        )
        .filter(
            F.col("processing_date") == current_date
        )
    )

    orders_today = (
        spark.table(
            f"{ARGS['curated_database']}.orders"
        )
        .filter(
            F.col("processing_date") == current_date
        )
    )

    details_today = (
        spark.table(
            f"{ARGS['curated_database']}.orderdetails"
        )
        .filter(
            F.col("processing_date") == current_date
        )
    )

    ratings_today = (
        spark.table(
            f"glue_catalog.{ARGS['curated_database']}.ratings_for_ml"
        )
        .filter(
            F.col("processing_date") == current_date
        )
    )

    # ---------------------------------------------------------
    # Reference keys known up to the current processing date
    # ---------------------------------------------------------

    known_customers = (
        spark.table(
            f"{ARGS['curated_database']}.customers"
        )
        .filter(
            F.col("processing_date") <= current_date
        )
        .select("customerNumber")
        .filter(
            F.col("customerNumber").isNotNull()
        )
        .distinct()
    )

    known_products = (
        spark.table(
            f"{ARGS['curated_database']}.products"
        )
        .filter(
            F.col("processing_date") <= current_date
        )
        .select("productCode")
        .filter(
            F.col("productCode").isNotNull()
        )
        .distinct()
    )

    # ---------------------------------------------------------
    # Data quality checks
    # ---------------------------------------------------------

    checks = {
        "customers_pk_null": (
            customers_today
            .filter(
                F.col("customerNumber").isNull()
            )
            .count()
        ),

        "products_pk_null": (
            products_today
            .filter(
                F.col("productCode").isNull()
            )
            .count()
        ),

        "orders_pk_null": (
            orders_today
            .filter(
                F.col("orderNumber").isNull()
            )
            .count()
        ),

        "negative_order_values": (
            details_today
            .filter(
                (F.col("quantityOrdered") <= 0)
                | (F.col("priceEach") < 0)
            )
            .count()
        ),

        "invalid_rating_range": (
            ratings_today
            .filter(
                ~F.col("productRating").between(1, 5)
            )
            .count()
        ),

        "orphan_order_customer": (
            orders_today
            .join(
                known_customers,
                "customerNumber",
                "left_anti",
            )
            .count()
        ),

        "orphan_order_product": (
            details_today
            .join(
                known_products,
                "productCode",
                "left_anti",
            )
            .count()
        ),
    }

    # ---------------------------------------------------------
    # Find failed checks
    # ---------------------------------------------------------

    failures = [
        name
        for name, count in checks.items()
        if count > 0
    ]

    # ---------------------------------------------------------
    # Store quality-check results in S3
    # ---------------------------------------------------------

    result_rows = [
        (
            name,
            count,
            "FAILED" if count else "PASSED",
            ARGS["run_id"],
            ARGS["processing_date"],
        )
        for name, count in checks.items()
    ]

    result_df = spark.createDataFrame(
        result_rows,
        [
            "check_name",
            "failure_count",
            "status",
            "run_id",
            "processing_date",
        ],
    )

    result_df.write.mode("overwrite").json(
        f"s3://{ARGS['data_lake_bucket']}/"
        f"quality_results/"
        f"processing_date={ARGS['processing_date']}/"
        f"run_id={ARGS['run_id']}/"
    )

    # ---------------------------------------------------------
    # Fail pipeline if any critical quality check fails
    # ---------------------------------------------------------

    if failures:
        write_audit(
            ARGS["audit_table"],
            ARGS["run_id"],
            stage,
            "FAILED",
            {
                "processing_date": ARGS["processing_date"],
                "run_mode": ARGS["run_mode"],
                **checks,
            },
        )

        raise ValueError(
            f"Critical data-quality checks failed: "
            f"{', '.join(failures)}"
        )

    # ---------------------------------------------------------
    # Success
    # ---------------------------------------------------------

    write_audit(
        ARGS["audit_table"],
        ARGS["run_id"],
        stage,
        "SUCCEEDED",
        {
            "processing_date": ARGS["processing_date"],
            "run_mode": ARGS["run_mode"],
            **checks,
        },
    )

    job.commit()

except Exception as exc:
    fail_audit(
        ARGS["audit_table"],
        ARGS["run_id"],
        stage,
        exc,
    )
    raise