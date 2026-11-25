# RDS MySQL in private subnets. Not publicly accessible; reachable only from
# security groups the caller explicitly allows (see stack: orders-api -> 3306).

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "RDS MySQL - ingress added per client service"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-db" }
}

# Enforce TLS for every client connection.
resource "aws_db_parameter_group" "this" {
  name   = var.name
  family = "mysql8.4"

  parameter {
    name  = "require_secure_transport"
    value = "1"
  }
}

# Pre-create the log groups RDS exports to, so they get a retention policy
# (RDS would otherwise create them with "never expire").
resource "aws_cloudwatch_log_group" "exports" {
  #checkov:skip=CKV_AWS_158:Encrypted at rest with an AWS-owned key by default.
  #checkov:skip=CKV_AWS_338:Retention is a deliberate cost choice (7 days staging, 30 days production).
  for_each          = toset(["error", "slowquery"])
  name              = "/aws/rds/instance/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_157:Multi-AZ is enabled in production via var.multi_az; staging is single-AZ to save cost.
  #checkov:skip=CKV_AWS_293:Deletion protection is enabled in production via var.deletion_protection.
  #checkov:skip=CKV_AWS_161:App authenticates with the RDS-managed secret; IAM DB auth listed under next steps.
  #checkov:skip=CKV_AWS_118:Enhanced monitoring listed under next steps (extra cost; basic CloudWatch metrics + alarms cover this exercise).
  identifier     = var.name
  engine         = "mysql"
  engine_version = "8.4" # current MySQL LTS; minor versions auto-upgrade in the maintenance window
  instance_class = var.instance_class
  db_name        = var.database_name
  username       = "orders_admin"

  # RDS generates the password and stores it in Secrets Manager (with rotation support).
  # It never appears in Terraform code, plan output or state.
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.this.name
  multi_az               = var.multi_az

  # Backups: daily snapshot + transaction logs every 5 min => point-in-time restore
  # to any second within the retention window. Times are UTC (03:00-04:00 EAT).
  backup_retention_period  = var.backup_retention_days
  backup_window            = "00:00-01:00"
  maintenance_window       = "sun:01:30-sun:02:30"
  copy_tags_to_snapshot    = true
  delete_automated_backups = false # keep backups if the instance is deleted by mistake

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${var.name}-final" : null

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  apply_immediately               = !var.deletion_protection # production changes wait for the maintenance window

  depends_on = [aws_cloudwatch_log_group.exports]
}
