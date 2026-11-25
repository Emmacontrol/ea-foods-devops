# One ECS Fargate service behind the shared ALB:
# log group, IAM roles, security group, target group + listener rule, task definition,
# service with circuit-breaker rollback, and CPU target-tracking autoscaling.

data "aws_region" "current" {}

# ---------------------------------------------------------------- logs

resource "aws_cloudwatch_log_group" "this" {
  #checkov:skip=CKV_AWS_158:Encrypted at rest with an AWS-owned key by default; a customer-managed KMS key adds cost with no extra benefit for these logs.
  #checkov:skip=CKV_AWS_338:Retention is a deliberate cost choice (7 days staging, 30 days production).
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------- IAM

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: used by the ECS agent (not the app) to pull the image,
# write logs and fetch secrets at container start. Scoped to exactly these resources.
resource "aws_iam_role" "execution" {
  name               = "${var.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # does not support resource-level scoping
  }
  statement {
    sid       = "PullThisRepoOnly"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
    resources = [var.ecr_repository_arn]
  }
  statement {
    sid       = "WriteThisLogGroupOnly"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }
  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []
    content {
      sid       = "ReadTheseSecretsOnly"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.secret_arns
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# Task role: the identity the APPLICATION runs as. Neither service calls AWS APIs,
# so it has no permissions at all — a compromised container gets no useful credentials.
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

# ---------------------------------------------------------------- network

resource "aws_security_group" "service" {
  name        = var.name
  description = "${var.service_name} tasks"
  vpc_id      = var.vpc_id
  tags        = { Name = var.name }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.service.id
  description                  = "App port from the ALB only"
  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

resource "aws_vpc_security_group_egress_rule" "alb_to_service" {
  security_group_id            = var.alb_security_group_id
  description                  = "ALB to ${var.service_name}"
  referenced_security_group_id = aws_security_group.service.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.service.id
  description       = "HTTPS to AWS APIs (ECR, Secrets Manager, CloudWatch Logs) via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# ---------------------------------------------------------------- ALB routing

resource "aws_lb_target_group" "this" {
  name                 = var.name
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip" # required for Fargate (awsvpc networking)
  vpc_id               = var.vpc_id
  deregistration_delay = 30 # drain in-flight requests on deploy, faster than the 300s default

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = var.listener_arn
  priority     = var.listener_priority

  condition {
    path_pattern {
      values = var.path_patterns
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# ---------------------------------------------------------------- task definition

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64" # Graviton: ~20% cheaper than x86 Fargate
  }

  # Writable scratch space, since the root filesystem is read-only.
  volume {
    name = "tmp"
  }

  container_definitions = jsonencode([{
    name                   = var.service_name
    image                  = var.image
    essential              = true
    readonlyRootFilesystem = true
    portMappings           = [{ containerPort = var.container_port, protocol = "tcp" }]
    environment            = [for k, v in var.environment_variables : { name = k, value = v }]
    secrets                = [for k, v in var.secrets : { name = k, valueFrom = v }]
    mountPoints            = [{ sourceVolume = "tmp", containerPath = "/tmp", readOnly = false }]
    linuxParameters = {
      initProcessEnabled = true # reap zombies, forward SIGTERM properly
      capabilities       = { drop = ["ALL"] }
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = var.service_name
      }
    }
  }])
}

# ---------------------------------------------------------------- service

resource "aws_ecs_service" "this" {
  name                              = var.service_name
  cluster                           = var.cluster_arn
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = var.desired_count
  health_check_grace_period_seconds = 30
  propagate_tags                    = "SERVICE"
  enable_ecs_managed_tags           = true

  # Rolling deploy: start new tasks before stopping old ones (no capacity dip).
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # If new tasks fail health checks, ECS stops the rollout and returns to the last good task definition.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # `terraform apply` only succeeds once the new version is actually healthy.
  wait_for_steady_state = true

  capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  lifecycle {
    ignore_changes = [desired_count] # owned by autoscaling after creation
  }

  depends_on = [aws_lb_listener_rule.this]
}

# ---------------------------------------------------------------- autoscaling

resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = "service/${split("/", var.cluster_arn)[1]}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
