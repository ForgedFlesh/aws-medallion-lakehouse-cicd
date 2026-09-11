resource "aws_lakeformation_resource" "data_lake" {
  arn                     = var.data_lake_bucket_arn
  use_service_linked_role = true
}

resource "aws_lakeformation_permissions" "glue_data_location" {
  principal   = var.glue_role_arn
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = aws_lakeformation_resource.data_lake.arn
  }
}

resource "aws_glue_catalog_database" "curated" {
  name = var.curated_database_name
}

resource "aws_glue_catalog_database" "presentation" {
  name = var.presentation_database_name
}

resource "aws_lakeformation_permissions" "glue_curated" {
  principal = var.glue_role_arn

  permissions = [
    "CREATE_TABLE",
    "ALTER",
    "DESCRIBE"
  ]

  database {
    name = aws_glue_catalog_database.curated.name
  }
}

resource "aws_lakeformation_permissions" "glue_presentation" {
  principal = var.glue_role_arn

  permissions = [
    "CREATE_TABLE",
    "ALTER",
    "DESCRIBE"
  ]

  database {
    name = aws_glue_catalog_database.presentation.name
  }
}