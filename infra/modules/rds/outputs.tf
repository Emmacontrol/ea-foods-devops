output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "database_name" {
  value = aws_db_instance.this.db_name
}

output "identifier" {
  value = aws_db_instance.this.identifier
}

output "security_group_id" {
  value = aws_security_group.db.id
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret (JSON with username/password) created and managed by RDS."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
