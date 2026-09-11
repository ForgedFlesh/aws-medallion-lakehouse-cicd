output "job_names" { value = { for k, v in aws_glue_job.jobs : k => v.name } }
