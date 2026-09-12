#this itself is not any policy,it is just a document,when we create the actual policy we will pass itthis policy document
#and the actions will be adapted by the policy
#here this one is the trust policy,we are allowing glue to assume this role
data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

#creating the glue role which will be assumed by our glue jobs attaching the trust policy 
resource "aws_iam_role" "glue" {
  name               = "${var.project_name}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
}

#we are attaching the basic glue inbuilt policies 
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

#this is again a document type
data "aws_iam_policy_document" "glue_data" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      var.data_lake_bucket_arn,
      "${var.data_lake_bucket_arn}/*",
      var.scripts_bucket_arn,
      "${var.scripts_bucket_arn}/*",
      "arn:aws:s3:::${var.source_bucket_name}",
      "arn:aws:s3:::${var.source_bucket_name}/*"
    ]
  }

  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem"
    ]

    resources = [
      var.audit_table_arn
    ]
  }

  statement {
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartitions",
      "glue:BatchCreatePartition",
      "lakeformation:GetDataAccess"
    ]

    resources = ["*"]
  }
}

#this is a real policy,that has the permissions we have declared in the document
resource "aws_iam_policy" "glue_data" {
  name   = "${var.project_name}-glue-data-policy"
  policy = data.aws_iam_policy_document.glue_data.json
}
#attaching the above policy to the glue role
resource "aws_iam_role_policy_attachment" "glue_data" {
  role       = aws_iam_role.glue.name
  policy_arn = aws_iam_policy.glue_data.arn
}
