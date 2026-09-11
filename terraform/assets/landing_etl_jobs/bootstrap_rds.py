import sys

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext


ARGS = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "connection_name",
        "bootstrap_sql_s3_uri",
    ],
)

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session

job = Job(glue_context)
job.init(ARGS["JOB_NAME"], ARGS)


def read_sql_from_s3(s3_uri):
    if not s3_uri.startswith("s3://"):
        raise ValueError("bootstrap_sql_s3_uri must start with s3://")

    path = s3_uri[5:]
    bucket, key = path.split("/", 1)

    s3 = boto3.client("s3")

    response = s3.get_object(
        Bucket=bucket,
        Key=key,
    )

    return response["Body"].read().decode("utf-8")


def split_sql_statements(sql_text):
    cleaned_lines = []

    for line in sql_text.splitlines():
        stripped = line.strip()

        if not stripped:
            continue

        if stripped.startswith("--"):
            continue

        cleaned_lines.append(line)

    cleaned_sql = "\n".join(cleaned_lines)

    return [
        statement.strip()
        for statement in cleaned_sql.split(";")
        if statement.strip()
    ]


connection = None
statement = None

try:
    # Get URL, username and password from the existing Glue JDBC connection.
    jdbc_conf = glue_context.extract_jdbc_conf(
        connection_name=ARGS["connection_name"]
    )

    jdbc_url = jdbc_conf["fullUrl"]
    username = jdbc_conf["user"]
    password = jdbc_conf["password"]

    print(f"Connecting to: {jdbc_url}")

    # Read our bootstrap SQL through the S3 Gateway VPC Endpoint.
    sql_text = read_sql_from_s3(
        ARGS["bootstrap_sql_s3_uri"]
    )

    sql_statements = split_sql_statements(sql_text)

    print(
        f"Bootstrap file contains "
        f"{len(sql_statements)} SQL statements"
    )

    # Glue already contains the MySQL JDBC driver.
    jvm = spark._jvm

    jvm.java.lang.Class.forName(
        "com.mysql.cj.jdbc.Driver"
    )

    connection = jvm.java.sql.DriverManager.getConnection(
        jdbc_url,
        username,
        password,
    )

    connection.setAutoCommit(False)

    statement = connection.createStatement()

    for index, sql in enumerate(sql_statements, start=1):
        print(
            f"Executing bootstrap SQL statement "
            f"{index}/{len(sql_statements)}"
        )

        statement.execute(sql)

    connection.commit()

    print("RDS bootstrap completed successfully.")

    job.commit()

except Exception:
    if connection is not None:
        try:
            connection.rollback()
        except Exception:
            pass

    raise

finally:
    if statement is not None:
        statement.close()

    if connection is not None:
        connection.close()