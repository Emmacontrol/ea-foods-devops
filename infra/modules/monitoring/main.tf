# Alarms -> SNS topic. Per service: 5xx error RATE, high CPU, unhealthy targets.
# Plus ALB-generated 5xx (e.g. 503 when no healthy target exists) and RDS CPU/storage.

resource "aws_sns_topic" "alarms" {
  #checkov:skip=CKV_AWS_26:CloudWatch alarms cannot publish to a topic encrypted with the AWS-managed SNS key (needs a CMK); messages contain alarm metadata only.
  name = "${var.name}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  actions = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------- per service

resource "aws_cloudwatch_metric_alarm" "target_5xx_rate" {
  for_each = var.services

  alarm_name          = "${var.name}-${each.key}-5xx-rate"
  alarm_description   = "${each.key}: >${var.error_rate_threshold_pct}% of requests returned 5xx in 3 of the last 5 minutes."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.error_rate_threshold_pct
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  metric_query {
    id          = "error_rate"
    label       = "5xx rate (%)"
    expression  = "IF(requests >= ${var.min_requests_for_error_rate}, 100 * errors / requests, 0)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      stat        = "Sum"
      period      = 60
      dimensions  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = each.value.target_group_arn_suffix }
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      stat        = "Sum"
      period      = 60
      dimensions  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = each.value.target_group_arn_suffix }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  for_each = var.services

  alarm_name          = "${var.name}-${each.key}-unhealthy-targets"
  alarm_description   = "${each.key}: at least one target failing ALB health checks for 3 consecutive minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = each.value.target_group_arn_suffix }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = var.services

  alarm_name          = "${var.name}-${each.key}-cpu-high"
  alarm_description   = "${each.key}: average CPU above ${var.cpu_threshold_pct}% in 3 of the last 5 minutes (autoscaling targets 60%, so this means scaling is not keeping up)."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = { ClusterName = var.cluster_name, ServiceName = each.value.service_name }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_threshold_pct
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# ---------------------------------------------------------------- load balancer

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name}-alb-5xx"
  alarm_description   = "ALB itself returned >10 5xx in 5 minutes (502/503/504: no healthy targets, timeouts)."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# ---------------------------------------------------------------- database

resource "aws_cloudwatch_metric_alarm" "db_cpu_high" {
  alarm_name          = "${var.name}-db-cpu-high"
  alarm_description   = "RDS CPU above ${var.cpu_threshold_pct}% for 10 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.cpu_threshold_pct
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

resource "aws_cloudwatch_metric_alarm" "db_storage_low" {
  alarm_name          = "${var.name}-db-storage-low"
  alarm_description   = "RDS free storage below 2 GiB (storage autoscaling may be at its ceiling)."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 2 * 1024 * 1024 * 1024
  alarm_actions       = local.actions
  ok_actions          = local.actions
}
