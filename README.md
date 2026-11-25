# EA Foods — DevOps Take-Home

Two small services (`orders-api`, `notify-svc`) on AWS ECS Fargate behind an HTTPS Application Load Balancer, with a private RDS MySQL database, provisioned by Terraform and shipped by GitHub Actions.

> Status: work in progress.

## Repository layout

```
apps/
  orders-api/      Django + MySQL — GET /health, GET /orders
  notify-svc/      Node.js — GET /health, logs a message per request
infra/
  bootstrap/       One-time: Terraform state bucket, GitHub OIDC provider, CI roles
  modules/         Reusable modules (network, alb, ecs-service, rds, monitoring, ecr)
  envs/            staging/ and production/ — same modules, different config
.github/workflows/ ci.yml (PR), deploy.yml (main), rollback.yml (manual)
scripts/           Helper scripts (rollback, smoke test)
docs/plans/        Committed `terraform plan` output
RUNBOOK.md         Point-in-time DB restore, rolling back a bad release
```

## Run locally

<!-- TODO Phase 1 -->

## Architecture

<!-- TODO Phase 5: mermaid diagram -->

## Deploy

<!-- TODO Phase 2/3 -->

## Rollback

<!-- TODO Phase 3 -->

## Security

<!-- TODO -->

## Monitoring and reliability

<!-- TODO Phase 4 -->

## Trade-offs

<!-- TODO -->

## Running this on Bitbucket Pipelines

<!-- TODO: mapping table -->

## Estimated monthly AWS cost

<!-- TODO: Infracost + manual table -->

## What I'd add for production / with more time

<!-- TODO -->
