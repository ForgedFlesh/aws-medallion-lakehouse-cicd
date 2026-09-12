### resource created in the main.tf was all 3 buckets,we just want them as output so that we can refer them from other modules

output "data_lake_bucket_name" { value = aws_s3_bucket.data_lake.id }
output "data_lake_bucket_arn" { value = aws_s3_bucket.data_lake.arn }
output "scripts_bucket_name" { value = aws_s3_bucket.scripts.id }
output "scripts_bucket_arn" { value = aws_s3_bucket.scripts.arn }
output "source_bucket_name" { value = aws_s3_bucket.source_data.id }
output "source_bucket_arn" { value = aws_s3_bucket.source_data.arn }
