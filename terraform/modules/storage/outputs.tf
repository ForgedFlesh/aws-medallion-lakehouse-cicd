output "data_lake_bucket_name" { value = aws_s3_bucket.data_lake.id }
output "data_lake_bucket_arn" { value = aws_s3_bucket.data_lake.arn }
output "scripts_bucket_name" { value = aws_s3_bucket.scripts.id }
output "scripts_bucket_arn" { value = aws_s3_bucket.scripts.arn }
output "source_bucket_name" { value = aws_s3_bucket.source_data.id }
output "source_bucket_arn" { value = aws_s3_bucket.source_data.arn }
