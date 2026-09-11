resource "aws_dynamodb_table" "audit" {
  name         = "${var.project_name}-pipeline-audit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "run_id"
  range_key    = "stage"
  attribute {
    name = "run_id"
    type = "S"
  }

  attribute {
    name = "stage"
    type = "S"
  }

  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }
}
