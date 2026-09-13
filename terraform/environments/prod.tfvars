aws_region   = "us-east-1"
project_name = "medallion-lakehouse"
environment  = "prod"

vpc_cidr = "10.20.0.0/16"

private_subnet_cidrs = [
  "10.20.1.0/24",
  "10.20.2.0/24",
  "10.20.3.0/24"
]

availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c"
]

data_lake_bucket_name   = "gamebred6296599796-prod-datalake"
scripts_bucket_name     = "gamebred6296599796-prod-scripts"
source_data_bucket_name = "gamebred6296599796-prod-source-ratings"

ratings_source_prefix = "ratings/"

rds_database_name = "classicmodels"

rds_instance_class    = "db.t3.micro"
rds_allocated_storage = 20

curated_database_name      = "curated_zone_prod"
presentation_database_name = "presentation_zone_prod"

athena_workgroup_name = "medallion-lakehouse-prod-workgroup"

ml_user_name = "ml_data_lake_user_prod"

enable_redshift          = false
enable_downstream_access = false
enable_event_trigger     = false

redshift_namespace_name = "medallion-lakehouse-prod"
redshift_workgroup_name = "medallion-lakehouse-prod"
redshift_database_name  = "lakehouse"
redshift_base_capacity  = 4

redshift_public_subnet_cidrs = [
  "10.20.11.0/24",
  "10.20.12.0/24",
  "10.20.13.0/24"
]