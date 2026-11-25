variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets in at least two AZs."
  type        = list(string)
}

variable "database_name" {
  type    = string
  default = "orders"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  type    = number
  default = 20
}

variable "max_allocated_storage_gb" {
  description = "Storage autoscaling ceiling — avoids an outage when the disk fills."
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Synchronous standby in a second AZ with automatic failover (~1-2 min)."
  type        = bool
}

variable "backup_retention_days" {
  description = "Automated backup + point-in-time-restore window (0-35 days)."
  type        = number
}

variable "deletion_protection" {
  type = bool
}

variable "log_retention_days" {
  type = number
}
