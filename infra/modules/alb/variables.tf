variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "domain_name" {
  description = "Hostname served by the ALB, e.g. api.staging.example.com. Gets a DNS-validated ACM certificate."
  type        = string
}

variable "route53_zone_id" {
  description = "Hosted zone that owns domain_name (for certificate validation and the alias record)."
  type        = string
}

variable "deletion_protection" {
  type    = bool
  default = false
}
