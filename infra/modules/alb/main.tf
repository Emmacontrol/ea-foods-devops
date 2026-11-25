# Internet-facing ALB in the public subnets. TLS terminates here with an ACM certificate;
# path-based listener rules (created by each ecs-service module) route /orders and /notify.

# ---------------------------------------------------------------- certificate (DNS validated)

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true # renew/replace without an outage
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => dvo
  }
  zone_id = var.route53_zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ---------------------------------------------------------------- security group

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public ALB: HTTP/HTTPS in from the internet"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  #checkov:skip=CKV_AWS_260:Port 80 only serves a 301 redirect to HTTPS.
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere (redirected to HTTPS only)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}
# Egress is added per service by the ecs-service module (ALB -> that service's port only).

# ---------------------------------------------------------------- load balancer + listeners

resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_28:WAF (AWS managed rule groups + rate limiting) is the first item under next steps in README.
  #checkov:skip=CKV_AWS_91:Access logs need an S3 bucket with an ELB delivery policy; listed under next steps in README.
  #checkov:skip=CKV_AWS_150:Enabled in production via var.deletion_protection.
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true # mitigate HTTP desync / request smuggling
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = 60
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # TLS 1.2+ only, modern ciphers
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn

  # Anything not matched by a service rule gets a 404 from the ALB itself.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"not found\"}"
      status_code  = "404"
    }
  }
}

# Friendly hostname -> ALB.
resource "aws_route53_record" "alias" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
