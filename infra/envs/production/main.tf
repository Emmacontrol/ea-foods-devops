terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Partial config: the bucket name is passed at init time
  #   terraform init -backend-config="bucket=<tf_state_bucket output from infra/bootstrap>"
  backend "s3" {
    key          = "production/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "ea-foods"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

module "stack" {
  source      = "../../stack"
  environment = "production"
  image_tag   = var.image_tag

  domain_name     = var.domain_name
  route53_zone_id = var.route53_zone_id
  alarm_email     = var.alarm_email

  # Production is optimised for availability and recoverability.
  vpc_cidr                 = "10.20.0.0/16"
  single_nat_gateway       = false # one NAT per AZ: losing an AZ does not cut the other AZ's egress
  task_cpu                 = 512
  task_memory              = 1024
  min_tasks                = 2 # one task per AZ at minimum
  max_tasks                = 6
  use_fargate_spot         = false
  container_insights       = true
  db_instance_class        = "db.t4g.small"
  db_multi_az              = true # synchronous standby, automatic failover in ~1-2 min
  db_backup_retention_days = 14   # see README "Backups": data bugs are often found days later
  deletion_protection      = true
  log_retention_days       = 30
}
