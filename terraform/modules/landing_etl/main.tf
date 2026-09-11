data "archive_file" "common" {
  type        = "zip"
  source_file = "${path.root}/assets/common/glue_utils.py"
  output_path = "${path.module}/glue_utils.zip"
}

resource "aws_s3_object" "common" {
  bucket = var.scripts_bucket_name
  key    = "glue/common/glue_utils.zip"
  source = data.archive_file.common.output_path
  etag   = filemd5(data.archive_file.common.output_path)
}
resource "aws_s3_object" "bootstrap_rds" {
  bucket = var.scripts_bucket_name
  key    = "glue/landing/bootstrap_rds.py"
  source = "${path.root}/assets/landing_etl_jobs/bootstrap_rds.py"

  etag = filemd5(
    "${path.root}/assets/landing_etl_jobs/bootstrap_rds.py"
  )
}

resource "aws_s3_object" "bootstrap_sql" {
  bucket = var.scripts_bucket_name

  key = "glue/bootstrap/classicmodels_bootstrap.sql"

  source = "${path.root}/assets/bootstrap/classicmodels_bootstrap.sql"

  etag = filemd5(
    "${path.root}/assets/bootstrap/classicmodels_bootstrap.sql"
  )
}
resource "aws_s3_object" "batch_ingress" {
  bucket = var.scripts_bucket_name
  key    = "glue/landing/batch_ingress.py"
  source = "${path.root}/assets/landing_etl_jobs/batch_ingress.py"
  etag   = filemd5("${path.root}/assets/landing_etl_jobs/batch_ingress.py")
}
resource "aws_s3_object" "json_ingress" {
  bucket = var.scripts_bucket_name
  key    = "glue/landing/json_ingress.py"
  source = "${path.root}/assets/landing_etl_jobs/json_ingress.py"
  etag   = filemd5("${path.root}/assets/landing_etl_jobs/json_ingress.py")
}
resource "aws_glue_connection" "rds" {
  name = "${var.project_name}-rds-connection"
  connection_properties = {
    JDBC_CONNECTION_URL = var.jdbc_connection_url
    USERNAME            = var.rds_username
    PASSWORD            = var.rds_password
  }
  physical_connection_requirements {
    availability_zone      = var.glue_availability_zone
    security_group_id_list = var.glue_security_group_ids
    subnet_id              = var.glue_subnet_id
  }
}
locals {
  common_args = {
    "--job-language"                 = "python"
    "--enable-metrics"               = "true"
    "--enable-observability-metrics" = "true"
    "--extra-py-files"               = "s3://${var.scripts_bucket_name}/glue/common/glue_utils.zip"
    "--data_lake_bucket"             = var.data_lake_bucket_name
    "--audit_table"                  = var.audit_table_name
    "--run_id"                       = "manual"
    "--processing_date"              = "1970-01-01"
    "--run_mode"                     = "incremental"
  }
}
resource "aws_glue_job" "rds" {
  name              = "${var.project_name}-rds-ingestion-job"
  role_arn          = var.glue_role_arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 60
  connections       = [aws_glue_connection.rds.name]
  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${var.scripts_bucket_name}/${aws_s3_object.batch_ingress.key}"
  }
  default_arguments = merge(local.common_args, {
    "--connection_name" = aws_glue_connection.rds.name
  })
}
resource "aws_glue_job" "json" {
  name              = "${var.project_name}-json-ingestion-job"
  role_arn          = var.glue_role_arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 30
  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${var.scripts_bucket_name}/${aws_s3_object.json_ingress.key}"
  }
  default_arguments = merge(local.common_args, {
    "--source_bucket" = var.source_data_bucket_name
    "--source_prefix" = var.ratings_source_prefix
  })
}

resource "aws_glue_job" "bootstrap_rds" {
  name     = "${var.project_name}-bootstrap-rds-job"
  role_arn = var.glue_role_arn

  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 30

  connections = [
    aws_glue_connection.rds.name
  ]

  command {
    name           = "glueetl"
    python_version = "3"

    script_location = "s3://${var.scripts_bucket_name}/${aws_s3_object.bootstrap_rds.key}"
  }

  default_arguments = {
    "--job-language"   = "python"
    "--enable-metrics" = "true"

    "--connection_name" = aws_glue_connection.rds.name

    "--bootstrap_sql_s3_uri" = "s3://${var.scripts_bucket_name}/${aws_s3_object.bootstrap_sql.key}"
  }
}