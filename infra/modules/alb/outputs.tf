output "arn_suffix" {
  description = "Used as the LoadBalancer dimension in CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  value = aws_lb.this.dns_name
}

output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}

output "security_group_id" {
  value = aws_security_group.alb.id
}

output "url" {
  value = "https://${var.domain_name}"
}
