# These values become GitHub repository/environment variables (not secrets —
# role ARNs and bucket names are identifiers, not credentials).

output "tf_state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "ecr_push_role_arn" {
  value = aws_iam_role.ecr_push.arn
}

output "deploy_role_arns" {
  value = { for env, role in aws_iam_role.deploy : env => role.arn }
}

output "ecr_repository_urls" {
  value = { for svc, repo in aws_ecr_repository.service : svc => repo.repository_url }
}
