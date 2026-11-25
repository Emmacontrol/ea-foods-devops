variable "name" {
  description = "Full resource name, e.g. ea-foods-staging-orders-api (IAM roles are prefixed with this)."
  type        = string
}

variable "service_name" {
  description = "Short service/container name, e.g. orders-api."
  type        = string
}

variable "cluster_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for the tasks."
  type        = list(string)
}

variable "image" {
  description = "Full image reference including tag, e.g. <acct>.dkr.ecr.<region>.amazonaws.com/ea-foods/orders-api:<git-sha>."
  type        = string
}

variable "ecr_repository_arn" {
  description = "The execution role may pull from this repository only."
  type        = string
}

variable "container_port" {
  type = number
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 4
}

variable "use_fargate_spot" {
  description = "Run on Fargate Spot (up to ~70% cheaper, can be interrupted). Fine for staging, not production."
  type        = bool
  default     = false
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "secrets" {
  description = "Env var name => Secrets Manager valueFrom (ARN, optionally with :json-key::). Injected at container start."
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "Secret ARNs the execution role may read (base ARNs of var.secrets)."
  type        = list(string)
  default     = []
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "listener_arn" {
  type = string
}

variable "listener_priority" {
  type = number
}

variable "path_patterns" {
  description = "ALB path patterns routed to this service, e.g. [\"/orders\", \"/orders/*\"]."
  type        = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "log_retention_days" {
  type = number
}
