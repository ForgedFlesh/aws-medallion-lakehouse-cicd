locals {
  scripts = {
    batch_transform = "batch_transform.py"
    ml_transform    = "json_transform.py"
    ratings_iceberg = "ratings_to_iceberg.py"
    quality         = "curated_quality_checks.py"
  }
  common_args = {
    "--job-language"                 = "python"
    "--enable-metrics"               = "true"
    "--enable-observability-metrics" = "true"
    "--enable-glue-datacatalog"      = "true"
    "--datalake-formats"             = "iceberg"
    "--conf"                         = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=${var.lakehouse_path} --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
    "--extra-py-files"               = "s3://${var.scripts_bucket_name}/glue/common/glue_utils.zip"
    "--data_lake_bucket"             = var.data_lake_bucket_name
    "--audit_table"                  = var.audit_table_name
    "--curated_database"             = var.curated_database_name
    "--lakehouse_path"               = var.lakehouse_path
    "--run_id"                       = "manual"
    "--processing_date"              = "1970-01-01"
    "--run_mode"                     = "incremental"
  }
}
resource "aws_s3_object" "scripts" {
  for_each = local.scripts
  bucket   = var.scripts_bucket_name
  key      = "glue/transform/${each.value}"
  source   = "${path.root}/assets/transform_etl_jobs/${each.value}"
  etag     = filemd5("${path.root}/assets/transform_etl_jobs/${each.value}")
}
resource "aws_glue_job" "jobs" {
  for_each = {
    batch_transform = "batch-transform-job"
    ml_transform    = "ml-transform-job"
    ratings_iceberg = "ratings-iceberg-job"
    quality         = "curated-quality-job"
  }
  name              = "${var.project_name}-${each.value}"
  role_arn          = var.glue_role_arn
  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = each.key == "batch_transform" ? 5 : 2
  timeout           = 120
  max_retries       = 1
  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${var.scripts_bucket_name}/${aws_s3_object.scripts[each.key].key}"
  }
  default_arguments = local.common_args
}
