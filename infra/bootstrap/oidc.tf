# GitHub Actions authenticates to AWS with short-lived OIDC tokens — no access keys
# are stored anywhere. Each role's trust policy pins WHICH workflow context may assume it.

locals {
  account_id  = data.aws_caller_identity.current.account_id
  repo_sub    = "repo:${var.github_repository}"
  oidc_issuer = "token.actions.githubusercontent.com"
}

# An AWS account can hold only one provider per issuer URL: create it, or reuse an existing one.
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_issuer}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://${local.oidc_issuer}"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# Trust policy factory: only this repo, only the given `sub` claims.
data "aws_iam_policy_document" "trust" {
  for_each = {
    plan     = ["${local.repo_sub}:pull_request", "${local.repo_sub}:ref:refs/heads/main"]
    ecr_push = ["${local.repo_sub}:ref:refs/heads/main"]
    # Jobs that declare `environment: <env>` get sub = repo:<repo>:environment:<env>.
    # The production environment has required reviewers, so this role is only
    # reachable after a human approves the deployment.
    staging    = ["${local.repo_sub}:environment:staging"]
    production = ["${local.repo_sub}:environment:production"]
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = each.value
    }
  }
}

# ---------------------------------------------------------------- plan (read-only)

resource "aws_iam_role" "plan" {
  name                 = "ea-foods-gha-plan"
  assume_role_policy   = data.aws_iam_policy_document.trust["plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan" {
  # ReadOnlyAccess is broad; explicitly forbid reading secret VALUES.
  statement {
    sid       = "DenySecretValues"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue", "ssm:GetParameter*", "kms:Decrypt"]
    resources = ["*"]
  }
  statement {
    sid       = "StateRead"
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
  }
  statement {
    sid       = "StateLockOnly" # plan takes a lock but can never overwrite state
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "plan"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# ---------------------------------------------------------------- ecr push (main only)

resource "aws_iam_role" "ecr_push" {
  name               = "ea-foods-gha-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.trust["ecr_push"].json
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource scoping
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
      "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload",
      "ecr:PutImage", "ecr:UploadLayerPart",
    ]
    resources = [for r in aws_ecr_repository.service : r.arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# ---------------------------------------------------------------- deploy (one per environment)

resource "aws_iam_role" "deploy" {
  for_each             = var.environments
  name                 = "ea-foods-gha-deploy-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.trust[each.key].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  #checkov:skip=CKV_AWS_111:Terraform deployer must create resources whose ARNs are unknown up front; constrained by region, IAM role-name prefix and a deny on secret values.
  #checkov:skip=CKV_AWS_356:Same as above. Hard isolation between environments = separate AWS accounts (README: production additions).
  for_each = var.environments

  # Terraform manages these services, in this region only.
  statement {
    sid = "RegionalServices"
    actions = [
      "ec2:*", "ecs:*", "elasticloadbalancing:*", "rds:*", "logs:*", "cloudwatch:*", "sns:*",
      "acm:*", "application-autoscaling:*", "secretsmanager:*", "ssm:*",
      "ecr:DescribeImages", "ecr:DescribeRepositories", "ecr:ListImages",
      "kms:DescribeKey", "kms:CreateGrant", "kms:ListAliases",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # The deployer creates secrets but never needs to read their values.
  statement {
    sid       = "DenySecretValues"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }

  statement {
    sid = "Route53Records"
    actions = [
      "route53:ChangeResourceRecordSets", "route53:GetChange", "route53:GetHostedZone",
      "route53:ListResourceRecordSets", "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # IAM only on roles named for THIS environment.
  statement {
    sid = "ManageEnvironmentRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:TagRole", "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/ea-foods-${each.key}-*"]
  }

  statement {
    sid       = "PassRolesToEcsOnly"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/ea-foods-${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "monitoring.rds.amazonaws.com", "vpc-flow-logs.amazonaws.com"]
    }
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com", "rds.amazonaws.com",
        "ecs.application-autoscaling.amazonaws.com",
      ]
    }
  }

  # State: only this environment's key prefix.
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${each.key}/*"]
    }
  }
  statement {
    sid       = "StateReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/${each.key}/*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = var.environments
  name     = "deploy"
  role     = aws_iam_role.deploy[each.key].id
  policy   = data.aws_iam_policy_document.deploy[each.key].json
}
