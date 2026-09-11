data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.root}/assets/lambda/s3_to_glue.py"
  output_path = "${path.module}/s3_to_glue.zip"
}
resource "aws_sqs_queue" "dlq" {
  name = "${var.project_name}-ratings-dlq"
}
resource "aws_sqs_queue" "events" {
  name           = "${var.project_name}-ratings-events"
  redrive_policy = jsonencode({ deadLetterTargetArn = aws_sqs_queue.dlq.arn, maxReceiveCount = 3 })
}

data "aws_iam_policy_document" "s3_to_sqs" {
  statement {
    sid       = "AllowSourceBucketNotifications"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.events.arn]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:s3:::${var.source_bucket_name}"]
    }
  }
}

resource "aws_sqs_queue_policy" "events" {
  queue_url = aws_sqs_queue.events.id
  policy    = data.aws_iam_policy_document.s3_to_sqs.json
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-s3-glue-trigger-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["glue:StartJobRun"], Resource = "*" },
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.events.arn }
    ]
  })
}
resource "aws_lambda_function" "trigger" {
  function_name    = "${var.project_name}-s3-to-glue"
  role             = aws_iam_role.lambda.arn
  handler          = "s3_to_glue.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 60
  environment {
    variables = {
      GLUE_JOB_NAME    = var.json_ingestion_job_name
      DATA_LAKE_BUCKET = var.data_lake_bucket_name
      AUDIT_TABLE      = var.audit_table_name
    }
  }
}
resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn        = aws_sqs_queue.events.arn
  function_name           = aws_lambda_function.trigger.arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}
# The source bucket may already be managed outside this stack. Add its S3 event
# notification to this queue manually or import the bucket before defining
# aws_s3_bucket_notification. This avoids Terraform overwriting existing rules.
