variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "image_tag" {
  description = "Git SHA of the images to deploy (set by the pipeline: -var image_tag=<sha>)."
  type        = string
}

variable "domain_name" {
  type = string
}

variable "route53_zone_id" {
  type = string
}

variable "alarm_email" {
  type    = string
  default = ""
}
