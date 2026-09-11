resource "aws_athena_workgroup" "main" {
  name          = var.athena_workgroup_name
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${var.scripts_bucket_name}/athena_results/main/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}
locals {
  query_files = {
    ratings             = "ratings.sql.tftpl"
    ratings_for_ml      = "ratings_for_ml.sql.tftpl"
    sales_report        = "sales_report.sql.tftpl"
    ratings_per_product = "ratings_per_product.sql.tftpl"
  }

  rendered_queries = {
    for name, filename in local.query_files : name => templatefile(
      "${path.root}/../presentation_sql/${filename}",
      {
        data_lake_bucket_name      = var.data_lake_bucket_name
        curated_database_name      = var.curated_database_name
        presentation_database_name = var.presentation_database_name
      }
    )
  }

  query_steps = merge([
    for query_name, sql_text in local.rendered_queries : {
      for step_index, statement in split(";", sql_text) :
      "${query_name}-${format("%02d", step_index + 1)}" => trimspace(statement)
      if trimspace(statement) != ""
    }
  ]...)
}

resource "aws_athena_named_query" "presentation" {
  for_each  = local.query_steps
  name      = "${var.project_name}-${each.key}"
  database  = var.presentation_database_name
  workgroup = aws_athena_workgroup.main.id
  query     = each.value
}
