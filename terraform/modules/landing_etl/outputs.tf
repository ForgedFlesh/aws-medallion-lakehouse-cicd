output "rds_ingestion_job_name" { value = aws_glue_job.rds.name }
output "json_ingestion_job_name" { value = aws_glue_job.json.name }
output "connection_name" { value = aws_glue_connection.rds.name }
output "bootstrap_rds_job_name" {
  value = aws_glue_job.bootstrap_rds.name
}