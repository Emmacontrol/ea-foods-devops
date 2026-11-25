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

Requirements: Docker with Compose v2.

```bash
make up          # builds images, starts MySQL, runs migrations, starts both services
curl localhost:8000/health   # {"status": "ok", "service": "orders-api", "version": "local"}
curl localhost:8000/orders   # 3 seeded orders read from MySQL
curl localhost:3000/notify   # {"status":"sent", ...} — and one JSON log line per request
make logs        # tail logs
make down        # stop and delete the local database volume
```

Unit tests: `make test` (orders-api uses SQLite for tests; notify-svc uses the built-in `node:test` runner).

| Image | Base (final stage) | Size | Runs as |
|---|---|---|---|
| orders-api | `python:3.13-slim`, pip removed | ~177 MB | uid 10001 |
| notify-svc | `gcr.io/distroless/nodejs24-debian13:nonroot` (no shell, no package manager) | ~162 MB | uid 65532 |

Local containers mirror production hardening: read-only root filesystem, all Linux capabilities dropped, `no-new-privileges`, and migrations as a one-off job rather than on app start-up.

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
