output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "database_name" {
  value = var.database_name
}

output "jdbc_url" {
  value = "jdbc:mysql://${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.database_name}"
}