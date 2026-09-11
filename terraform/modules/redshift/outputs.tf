output "endpoint" { value = aws_redshiftserverless_workgroup.this.endpoint[0].address }
output "workgroup_name" { value = aws_redshiftserverless_workgroup.this.workgroup_name }
output "namespace_name" { value = aws_redshiftserverless_namespace.this.namespace_name }
output "spectrum_role_arn" { value = aws_iam_role.spectrum.arn }
