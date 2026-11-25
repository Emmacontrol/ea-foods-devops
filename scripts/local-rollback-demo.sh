#!/usr/bin/env bash
# Local, runnable rehearsal of the release and rollback flow (no AWS needed).
#
# docker compose stands in for ECS and local/proxy.conf for the ALB. Everything else is
# the real mechanism used in AWS:
#   - releases are immutable image tags (git SHAs in AWS; v1/v2/v3 here)
#   - every deploy is checked by scripts/smoke-test.sh: 200 from /orders and /notify
#     through the load balancer AND the expected X-App-Version header
#   - a failed smoke test triggers an automatic rollback to the last known-good release
#   - a manual rollback redeploys the previous release from the images already built
#
# Usage: make rollback-demo   (or scripts/local-rollback-demo.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

url="http://localhost:8080"
export SMOKE_ATTEMPTS=3
current="" previous=""

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# deploy <tag> [VAR=value ...]: roll both services to <tag>, then smoke test it.
deploy() {
  local tag="$1"; shift
  env "$@" APP_TAG="${tag}" docker compose up -d --wait --no-build proxy >/dev/null 2>&1
  scripts/smoke-test.sh "${url}" "${tag}"
}

# release <tag> [VAR=value ...]: deploy; on failure roll back automatically (like _deploy.yml).
release() {
  local tag="$1"
  step "Deploying ${tag}"
  if deploy "$@"; then
    previous="${current}"; current="${tag}"
    echo "Released ${tag} (previous: ${previous:-none})"
  else
    echo "Container health checks at this moment (all green, yet users get errors):"
    docker compose ps --format '   {{.Service}}: {{.Status}}' orders-api notify-svc
    step "Smoke test FAILED for ${tag}: automatic rollback to last known-good ${current}"
    deploy "${current}"
    echo "Rolled back to ${current}; ${tag} never became the current release"
  fi
}

step "Building images once and tagging three releases (v1, v2, v3)"
APP_TAG=v1 docker compose build -q
for svc in orders-api notify-svc; do
  docker tag "${svc}:v1" "${svc}:v2"
  docker tag "${svc}:v1" "${svc}:v3"
done

release v1
release v2

# v3 ships a bad configuration: containers start and /health stays green (so ECS's
# circuit breaker would NOT catch it), but every /orders request returns 400.
release v3 DJANGO_ALLOWED_HOSTS=wrong.example.com

step "Manual rollback to the previous release (${previous}), as with: scripts/rollback.sh <env>"
deploy "${previous}"
current="${previous}"

step "Result"
curl -sI "${url}/orders" | grep -i x-app-version
curl -sI "${url}/notify" | grep -i x-app-version
echo "Rollback demo complete: running ${current}. Stop with: make down"
