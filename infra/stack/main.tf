# Composition of one complete environment. Instantiated by envs/staging and envs/production.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name         = "ea-foods-${var.environment}"
  ecr_registry = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com"
  ecr_arn_base = "arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository"
  rds_ca_path  = "/app/certs/rds-global-bundle.pem" # baked into the orders-api image
}

# ---------------------------------------------------------------- network + load balancer

module "network" {
  source             = "../modules/network"
  name               = local.name
  cidr_block         = var.vpc_cidr
  az_count           = 2
  single_nat_gateway = var.single_nat_gateway
}

module "alb" {
  source              = "../modules/alb"
  name                = local.name
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  domain_name         = var.domain_name
  route53_zone_id     = var.route53_zone_id
  deletion_protection = var.deletion_protection
}

# ---------------------------------------------------------------- ECS cluster

resource "aws_ecs_cluster" "this" {
  #checkov:skip=CKV_AWS_65:Container Insights is enabled in production via var.container_insights.
  name = local.name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

# ---------------------------------------------------------------- database

module "rds" {
  source                = "../modules/rds"
  name                  = local.name
  vpc_id                = module.network.vpc_id
  subnet_ids            = module.network.private_subnet_ids
  instance_class        = var.db_instance_class
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.deletion_protection
  log_retention_days    = var.log_retention_days
}

# ---------------------------------------------------------------- Django secret key
# Generated ephemerally and written with a write-only argument:
# the value exists in Secrets Manager only — never in plan output or Terraform state.

ephemeral "random_password" "django_secret_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "django_secret_key" {
  #checkov:skip=CKV_AWS_149:Encrypted with the AWS-managed Secrets Manager key; a CMK would add cost and key-policy management.
  name                    = "${local.name}/orders-api/django-secret-key"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "django_secret_key" {
  secret_id                = aws_secretsmanager_secret.django_secret_key.id
  secret_string_wo         = ephemeral.random_password.django_secret_key.result
  secret_string_wo_version = 1 # bump to rotate
}

# ---------------------------------------------------------------- services

module "orders_api" {
  source             = "../modules/ecs-service"
  name               = "${local.name}-orders-api"
  service_name       = "orders-api"
  cluster_arn        = aws_ecs_cluster.this.arn
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  image              = "${local.ecr_registry}/ea-foods/orders-api:${var.image_tag}"
  ecr_repository_arn = "${local.ecr_arn_base}/ea-foods/orders-api"
  container_port     = 8000
  cpu                = var.task_cpu
  memory             = var.task_memory
  desired_count      = var.min_tasks
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
  use_fargate_spot   = var.use_fargate_spot
  log_retention_days = var.log_retention_days

  environment_variables = {
    APP_VERSION          = var.image_tag
    DJANGO_ALLOWED_HOSTS = var.domain_name
    DB_HOST              = module.rds.address
    DB_PORT              = tostring(module.rds.port)
    DB_NAME              = module.rds.database_name
    DB_SSL_CA            = local.rds_ca_path
  }

  # Injected by ECS at container start; the ":<key>::" suffix picks one JSON key from the secret.
  secrets = {
    DB_USER           = "${module.rds.master_user_secret_arn}:username::"
    DB_PASSWORD       = "${module.rds.master_user_secret_arn}:password::"
    DJANGO_SECRET_KEY = aws_secretsmanager_secret.django_secret_key.arn
  }
  secret_arns = [module.rds.master_user_secret_arn, aws_secretsmanager_secret.django_secret_key.arn]

  listener_arn          = module.alb.https_listener_arn
  listener_priority     = 10
  path_patterns         = ["/orders", "/orders/*"]
  alb_security_group_id = module.alb.security_group_id
}

module "notify_svc" {
  source             = "../modules/ecs-service"
  name               = "${local.name}-notify-svc"
  service_name       = "notify-svc"
  cluster_arn        = aws_ecs_cluster.this.arn
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids
  image              = "${local.ecr_registry}/ea-foods/notify-svc:${var.image_tag}"
  ecr_repository_arn = "${local.ecr_arn_base}/ea-foods/notify-svc"
  container_port     = 3000
  cpu                = var.task_cpu
  memory             = var.task_memory
  desired_count      = var.min_tasks
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
  use_fargate_spot   = var.use_fargate_spot
  log_retention_days = var.log_retention_days

  environment_variables = {
    APP_VERSION = var.image_tag
  }

  listener_arn          = module.alb.https_listener_arn
  listener_priority     = 20
  path_patterns         = ["/notify", "/notify/*"]
  alb_security_group_id = module.alb.security_group_id
}

# ---------------------------------------------------------------- database access: orders-api only

resource "aws_vpc_security_group_ingress_rule" "db_from_orders_api" {
  security_group_id            = module.rds.security_group_id
  description                  = "MySQL from orders-api tasks only"
  referenced_security_group_id = module.orders_api.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

resource "aws_vpc_security_group_egress_rule" "orders_api_to_db" {
  security_group_id            = module.orders_api.security_group_id
  description                  = "orders-api to MySQL"
  referenced_security_group_id = module.rds.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

# ---------------------------------------------------------------- monitoring

module "monitoring" {
  source         = "../modules/monitoring"
  name           = local.name
  alb_arn_suffix = module.alb.arn_suffix
  cluster_name   = aws_ecs_cluster.this.name
  db_identifier  = module.rds.identifier
  alarm_email    = var.alarm_email

  services = {
    orders-api = { service_name = module.orders_api.service_name, target_group_arn_suffix = module.orders_api.target_group_arn_suffix }
    notify-svc = { service_name = module.notify_svc.service_name, target_group_arn_suffix = module.notify_svc.target_group_arn_suffix }
  }
}
