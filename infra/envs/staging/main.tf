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
    key          = "staging/terraform.tfstate"
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
      Environment = "staging"
      ManagedBy   = "terraform"
    }
  }
}

module "stack" {
  source      = "../../stack"
  environment = "staging"
  image_tag   = var.image_tag

  domain_name     = var.domain_name
  route53_zone_id = var.route53_zone_id
  alarm_email     = var.alarm_email

  # Staging is optimised for cost; it only has to behave like production, not survive like it.
  vpc_cidr                 = "10.10.0.0/16"
  single_nat_gateway       = true # one NAT shared by both AZs (~$35/month saved)
  task_cpu                 = 256
  task_memory              = 512
  min_tasks                = 1
  max_tasks                = 2
  use_fargate_spot         = true # up to ~70% cheaper; interruptions are acceptable here
  container_insights       = false
  db_instance_class        = "db.t4g.micro"
  db_multi_az              = false
  db_backup_retention_days = 3 # covers a weekend; enough to rehearse the restore runbook
  deletion_protection      = false
  log_retention_days       = 7
}
