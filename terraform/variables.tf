variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "medallion-lakehouse"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  type = list(string)

  default = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]
}

variable "availability_zones" {
  type = list(string)

  default = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c"
  ]
}

variable "data_lake_bucket_name" {
  type = string
}

variable "scripts_bucket_name" {
  type = string
}

variable "source_data_bucket_name" {
  type = string
}

variable "ratings_source_prefix" {
  type    = string
  default = "ratings/"
}

variable "rds_username" {
  type      = string
  sensitive = true
}

variable "rds_password" {
  type      = string
  sensitive = true
}

variable "rds_database_name" {
  type    = string
  default = "classicmodels"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "rds_allocated_storage" {
  type    = number
  default = 20
}

variable "curated_database_name" {
  type    = string
  default = "curated_zone"
}

variable "presentation_database_name" {
  type    = string
  default = "presentation_zone"
}

variable "lakehouse_path" {
  type    = string
  default = ""
}

variable "athena_workgroup_name" {
  type    = string
  default = "medallion-lakehouse-workgroup"
}

variable "ml_user_name" {
  type    = string
  default = "ml_data_lake_user"
}

variable "enable_redshift" {
  type    = bool
  default = false
}

variable "redshift_namespace_name" {
  type    = string
  default = "medallion-lakehouse"
}

variable "redshift_workgroup_name" {
  type    = string
  default = "medallion-lakehouse"
}

variable "redshift_database_name" {
  type    = string
  default = "lakehouse"
}

variable "redshift_base_capacity" {
  type    = number
  default = 8
}

variable "enable_downstream_access" {
  type    = bool
  default = false
}

variable "enable_event_trigger" {
  type    = bool
  default = false
}

variable "redshift_public_subnet_cidrs" {
  type = list(string)

  default = [
    "10.0.11.0/24",
    "10.0.12.0/24",
    "10.0.13.0/24"
  ]
}

variable "redshift_allowed_cidr" {
  type        = string
  description = "Public IPv4 CIDR allowed to connect to Redshift"
}