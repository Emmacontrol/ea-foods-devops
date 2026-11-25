terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Bootstrap creates the remote-state bucket, so its own state is local (chicken-and-egg).
  # It changes rarely; in a team it would be migrated into the bucket after first apply.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "ea-foods"
      Component = "bootstrap"
      ManagedBy = "terraform"
      Repo      = var.github_repository
    }
  }
}

data "aws_caller_identity" "current" {}
