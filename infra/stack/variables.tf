# Everything that differs between staging and production is a variable here;
# envs/staging and envs/production set them. Same code, different configuration.

variable "environment" {
  type = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "image_tag" {
  description = "Image tag (git SHA) to deploy for both services. Set by the pipeline."
  type        = string
}

# ---- networking / DNS
variable "vpc_cidr" {
  type = string
}

variable "single_nat_gateway" {
  type = bool
}

variable "domain_name" {
  type = string
}

variable "route53_zone_id" {
  type = string
}

# ---- compute
variable "task_cpu" {
  type = number
}

variable "task_memory" {
  type = number
}

variable "min_tasks" {
  type = number
}

variable "max_tasks" {
  type = number
}

variable "use_fargate_spot" {
  type = bool
}

variable "container_insights" {
  type = bool
}

# ---- database
variable "db_instance_class" {
  type = string
}

variable "db_multi_az" {
  type = bool
}

variable "db_backup_retention_days" {
  type = number
}

# ---- safety / ops
variable "deletion_protection" {
  description = "Protect the ALB and database from deletion (and take a final DB snapshot)."
  type        = bool
}

variable "log_retention_days" {
  type = number
}

variable "alarm_email" {
  type    = string
  default = ""
}
