output "data_lake_bucket_name" { value = module.storage.data_lake_bucket_name }
output "scripts_bucket_name" { value = module.storage.scripts_bucket_name }
output "audit_table_name" { value = module.audit.audit_table_name }
output "glue_role_arn" { value = module.iam.glue_role_arn }
output "athena_workgroup_name" { value = module.presentation.athena_workgroup_name }
/*
output "redshift_endpoint" {
  value = var.enable_redshift ? module.redshift[0].endpoint : null
}

output "redshift_spectrum_role_arn" {
  value = var.enable_redshift ? module.redshift[0].spectrum_role_arn : null
}
*/