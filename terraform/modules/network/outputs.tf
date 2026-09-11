output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "glue_security_group_id" {
  value = aws_security_group.glue.id
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

/*
output "redshift_security_group_id" {
  value = aws_security_group.redshift.id
}

output "redshift_public_subnet_ids" {
  value = aws_subnet.redshift_public[*].id
}
*/