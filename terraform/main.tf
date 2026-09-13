locals {

  resource_prefix          = "${var.project_name}-${var.environment}"
  effective_lakehouse_path = var.lakehouse_path != "" ? var.lakehouse_path : "s3://${var.data_lake_bucket_name}/curated_zone"
}

module "storage" {
  source                  = "./modules/storage"
  data_lake_bucket_name   = var.data_lake_bucket_name
  scripts_bucket_name     = var.scripts_bucket_name
  source_data_bucket_name = var.source_data_bucket_name
}

module "audit" {
  source       = "./modules/audit"
  project_name = local.resource_prefix
}

module "network" {
  source = "./modules/network"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  # redshift_public_subnet_cidrs = var.redshift_public_subnet_cidrs
  # redshift_allowed_cidr        = var.redshift_allowed_cidr
}


module "rds" {
  source = "./modules/rds"

  project_name = var.project_name
  environment  = var.environment

  subnet_ids = module.network.private_subnet_ids

  security_group_id = module.network.rds_security_group_id

  database_name = var.rds_database_name
  username      = var.rds_username
  password      = var.rds_password

  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage
}


module "iam" {
  source                     = "./modules/iam"
  project_name               = local.resource_prefix
  data_lake_bucket_arn       = module.storage.data_lake_bucket_arn
  scripts_bucket_arn         = module.storage.scripts_bucket_arn
  source_bucket_name         = var.source_data_bucket_name
  audit_table_arn            = module.audit.audit_table_arn
  curated_database_name      = var.curated_database_name
  presentation_database_name = var.presentation_database_name
}

module "landing_etl" {
  source              = "./modules/landing_etl"
  project_name        = local.resource_prefix
  scripts_bucket_name = module.storage.scripts_bucket_name
  glue_role_arn       = module.iam.glue_role_arn
  jdbc_connection_url = module.rds.jdbc_url
  rds_username        = var.rds_username
  rds_password        = var.rds_password
  glue_subnet_id      = module.network.private_subnet_ids[0]

  glue_security_group_ids = [
    module.network.glue_security_group_id
  ]

  glue_availability_zone  = var.availability_zones[0]
  source_data_bucket_name = var.source_data_bucket_name
  ratings_source_prefix   = var.ratings_source_prefix
  data_lake_bucket_name   = module.storage.data_lake_bucket_name
  audit_table_name        = module.audit.audit_table_name
}

module "lakeformation" {
  source                     = "./modules/lakeformation"
  data_lake_bucket_arn       = module.storage.data_lake_bucket_arn
  glue_role_arn              = module.iam.glue_role_arn
  curated_database_name      = var.curated_database_name
  presentation_database_name = var.presentation_database_name
}

module "transform_etl" {
  source                = "./modules/transform_etl"
  project_name          = local.resource_prefix
  scripts_bucket_name   = module.storage.scripts_bucket_name
  glue_role_arn         = module.iam.glue_role_arn
  data_lake_bucket_name = module.storage.data_lake_bucket_name
  audit_table_name      = module.audit.audit_table_name
  curated_database_name = var.curated_database_name
  lakehouse_path        = local.effective_lakehouse_path
  depends_on            = [module.lakeformation, module.landing_etl]
}

module "presentation" {
  source                     = "./modules/presentation"
  project_name               = local.resource_prefix
  data_lake_bucket_name      = var.data_lake_bucket_name
  curated_database_name      = var.curated_database_name
  scripts_bucket_name        = module.storage.scripts_bucket_name
  presentation_database_name = var.presentation_database_name
  athena_workgroup_name      = var.athena_workgroup_name
  depends_on                 = [module.lakeformation]
}

/*
module "redshift" {
  count          = var.enable_redshift ? 1 : 0
  source         = "./modules/redshift"
  project_name   = var.project_name
  namespace_name = var.redshift_namespace_name
  workgroup_name = var.redshift_workgroup_name
  database_name  = var.redshift_database_name
  base_capacity  = var.redshift_base_capacity
  subnet_ids     = module.network.redshift_public_subnet_ids

  security_group_ids = [
    module.network.redshift_security_group_id
  ]
  data_lake_bucket_arn  = module.storage.data_lake_bucket_arn
  curated_database_name = var.curated_database_name
  depends_on            = [module.lakeformation]
}
*/

module "downstream_access" {
  count                      = var.enable_downstream_access ? 1 : 0
  source                     = "./modules/downstream_access"
  ml_user_name               = var.ml_user_name
  data_lake_bucket_arn       = module.storage.data_lake_bucket_arn
  presentation_database_name = var.presentation_database_name
  athena_workgroup_name      = var.athena_workgroup_name
  depends_on                 = [module.presentation, module.lakeformation]
}

module "event_trigger" {
  count                   = var.enable_event_trigger ? 1 : 0
  source                  = "./modules/event_trigger"
  project_name            = local.resource_prefix
  source_bucket_name      = var.source_data_bucket_name
  source_prefix           = var.ratings_source_prefix
  json_ingestion_job_name = module.landing_etl.json_ingestion_job_name
  data_lake_bucket_name   = module.storage.data_lake_bucket_name
  audit_table_name        = module.audit.audit_table_name
}
