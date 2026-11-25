variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-west-1"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to assume the CI roles via OIDC."
  type        = string
  default     = "Emmacontrol/ea-foods-devops"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one (only one per issuer is allowed)."
  type        = bool
  default     = true
}

variable "environments" {
  description = "Deployment environments; each gets its own deploy role and state key prefix."
  type        = set(string)
  default     = ["staging", "production"]
}

variable "services" {
  description = "Services that get an ECR repository."
  type        = set(string)
  default     = ["orders-api", "notify-svc"]
}

variable "ecr_keep_images" {
  description = "Number of images kept per ECR repository (rollback window)."
  type        = number
  default     = 30
}
