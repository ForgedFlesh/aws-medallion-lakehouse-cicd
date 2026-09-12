#these are the variables that i am expecting to receive from the root main.tf module "storage" 

variable "data_lake_bucket_name" { type = string }
variable "scripts_bucket_name" { type = string }
variable "source_data_bucket_name" {
  type = string
}