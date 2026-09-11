variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

#we will be passing a list with subnet cidrs and az's as a list,3 each 
variable "private_subnet_cidrs" {
  type = list(string)
}

variable "availability_zones" {
  type = list(string)
}

/*
variable "redshift_public_subnet_cidrs" {
  type = list(string)
}

variable "redshift_allowed_cidr" {
  type = string
}
*/