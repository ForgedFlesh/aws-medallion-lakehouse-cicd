variable "project_name" { type = string }
variable "scripts_bucket_name" { type = string }
variable "glue_role_arn" { type = string }
variable "jdbc_connection_url" { type = string }
variable "rds_username" {
  type      = string
  sensitive = true
}

variable "rds_password" {
  type      = string
  sensitive = true
}
variable "glue_subnet_id" { type = string }
variable "glue_security_group_ids" { type = list(string) }
variable "glue_availability_zone" { type = string }
variable "source_data_bucket_name" { type = string }
variable "ratings_source_prefix" { type = string }
variable "data_lake_bucket_name" { type = string }
variable "audit_table_name" { type = string }
