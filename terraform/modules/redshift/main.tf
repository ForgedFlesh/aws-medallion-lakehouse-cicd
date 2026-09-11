data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"

      identifiers = [
        "redshift.amazonaws.com",
        "redshift-serverless.amazonaws.com"
      ]
    }
  }
}
resource "aws_iam_role" "spectrum" {
  name               = "${var.project_name}-redshift-spectrum-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}
data "aws_iam_policy_document" "spectrum" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.data_lake_bucket_arn, "${var.data_lake_bucket_arn}/*"]
  }
  statement {
    actions   = ["glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:GetPartitions", "lakeformation:GetDataAccess"]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "spectrum" {
  role   = aws_iam_role.spectrum.id
  policy = data.aws_iam_policy_document.spectrum.json
}
resource "aws_redshiftserverless_namespace" "this" {
  namespace_name        = var.namespace_name
  db_name               = var.database_name
  manage_admin_password = true
  iam_roles             = [aws_iam_role.spectrum.arn]
  default_iam_role_arn  = aws_iam_role.spectrum.arn
}
resource "aws_redshiftserverless_workgroup" "this" {
  namespace_name       = aws_redshiftserverless_namespace.this.namespace_name
  workgroup_name       = var.workgroup_name
  base_capacity        = var.base_capacity
  subnet_ids           = var.subnet_ids
  security_group_ids   = var.security_group_ids
  publicly_accessible  = true
  enhanced_vpc_routing = true
}

resource "aws_lakeformation_permissions" "spectrum_data_location" {
  principal   = aws_iam_role.spectrum.arn
  permissions = ["DATA_LOCATION_ACCESS"]
  data_location {
    arn = var.data_lake_bucket_arn
  }
}

resource "aws_lakeformation_permissions" "spectrum_database" {
  principal   = aws_iam_role.spectrum.arn
  permissions = ["DESCRIBE"]
  database {
    name = var.curated_database_name
  }
}

resource "aws_lakeformation_permissions" "spectrum_tables" {
  principal   = aws_iam_role.spectrum.arn
  permissions = ["SELECT", "DESCRIBE"]
  table {
    database_name = var.curated_database_name
    wildcard      = true
  }
}
