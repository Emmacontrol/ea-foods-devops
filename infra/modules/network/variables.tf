variable "name" {
  type = string
}

variable "cidr_block" {
  type = string
}

variable "az_count" {
  type    = number
  default = 2
}

variable "single_nat_gateway" {
  description = "true: one shared NAT (cheaper, staging). false: one NAT per AZ (no cross-AZ single point of failure, production)."
  type        = bool
}
