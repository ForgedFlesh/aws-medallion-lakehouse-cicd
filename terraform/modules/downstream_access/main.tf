resource "aws_iam_user" "ml" {
  name = var.ml_user_name
}

data "aws_iam_policy_document" "ml" {
  statement {
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults"
    ]

    resources = [
      "arn:aws:athena:*:*:workgroup/${var.athena_workgroup_name}"
    ]
  }

  statement {
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetPartitions",
      "lakeformation:GetDataAccess"
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]

    resources = [
      var.data_lake_bucket_arn
    ]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [
      "${var.data_lake_bucket_arn}/athena_results/ml/*"
    ]
  }
}

resource "aws_iam_user_policy" "ml" {
  user   = aws_iam_user.ml.name
  policy = data.aws_iam_policy_document.ml.json
}

resource "aws_lakeformation_permissions" "database" {
  principal   = aws_iam_user.ml.arn
  permissions = ["DESCRIBE"]

  database {
    name = var.presentation_database_name
  }
}

resource "aws_lakeformation_permissions" "table" {
  principal   = aws_iam_user.ml.arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = var.presentation_database_name
    name          = "ratings_for_ml"
  }
}