variable "name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "services" {
  description = "Services to alarm on, keyed by short name."
  type = map(object({
    service_name            = string
    target_group_arn_suffix = string
  }))
}

variable "db_identifier" {
  type = string
}

variable "alarm_email" {
  description = "Optional email subscribed to alarms (must confirm the subscription). Empty = no subscription."
  type        = string
  default     = ""
}

variable "error_rate_threshold_pct" {
  description = "Alarm when more than this % of requests return 5xx."
  type        = number
  default     = 5
}

variable "min_requests_for_error_rate" {
  description = "Ignore the error rate in minutes with fewer requests than this (1 failure out of 1 request is not 100% down)."
  type        = number
  default     = 10
}

variable "cpu_threshold_pct" {
  type    = number
  default = 80
}
