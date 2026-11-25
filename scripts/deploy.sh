#!/usr/bin/env bash
# Deploy ONE environment to an image tag (git SHA).
#
# Used by the pipeline AND by humans. A rollback is this same script with an older,
# known-good tag (see rollback.sh): one code path, same checks, exercised on every deploy.
#
# Usage:  scripts/deploy.sh <staging|production> <image-tag>
# Needs:  TF_STATE_BUCKET, AWS credentials for that environment's deploy role.
# Optional: ROLLBACK=true  -> skip migrations, keep the "previous" pointer unchanged.
set -euo pipefail

env="${1:?usage: deploy.sh <staging|production> <image-tag>}"
tag="${2:?usage: deploy.sh <staging|production> <image-tag>}"
: "${TF_STATE_BUCKET:?TF_STATE_BUCKET must be set (output of infra/bootstrap)}"
rollback="${ROLLBACK:-false}"

dir="infra/envs/${env}"
scripts="$(cd "$(dirname "$0")" && pwd)"
current_param="/ea-foods/${env}/image-tag"
previous_param="/ea-foods/${env}/previous-image-tag"

echo "==> 1/6 Checking that both images exist for tag ${tag}"
for svc in orders-api notify-svc; do
  aws ecr describe-images --repository-name "ea-foods/${svc}" --image-ids imageTag="${tag}" >/dev/null
done

echo "==> 2/6 terraform plan"
terraform -chdir="${dir}" init -input=false -backend-config="bucket=${TF_STATE_BUCKET}"
terraform -chdir="${dir}" plan -input=false -var "image_tag=${tag}" -out=tfplan

echo "==> 3/6 Database migrations (new image, before the services roll)"
migrated=false
if [ "${rollback}" = "true" ]; then
  # Migrations are never reversed on rollback: they must be backward compatible
  # (expand/contract), so the previous release keeps working on the newer schema.
  echo "Rollback: skipping migrations."
  migrated=true
elif aws ecs describe-task-definition --task-definition "ea-foods-${env}-orders-api" >/dev/null 2>&1; then
  "${scripts}/run-migrations.sh" "${env}" "${tag}"
  migrated=true
else
  echo "First deploy: no task definition yet, migrations will run right after apply."
fi

echo "==> 4/6 terraform apply (returns only when ECS services are steady)"
terraform -chdir="${dir}" apply -input=false tfplan
if [ "${migrated}" = "false" ]; then
  "${scripts}/run-migrations.sh" "${env}" "${tag}"
fi

echo "==> 5/6 Smoke test through the load balancer"
url="$(terraform -chdir="${dir}" output -raw url)"
"${scripts}/smoke-test.sh" "${url}" "${tag}"

echo "==> 6/6 Recording release in SSM Parameter Store"
current="$(aws ssm get-parameter --name "${current_param}" --query Parameter.Value --output text 2>/dev/null || true)"
if [ "${rollback}" != "true" ] && [ -n "${current}" ] && [ "${current}" != "${tag}" ]; then
  aws ssm put-parameter --name "${previous_param}" --value "${current}" --type String --overwrite >/dev/null
fi
aws ssm put-parameter --name "${current_param}" --value "${tag}" --type String --overwrite >/dev/null

echo "Done: ${env} is running ${tag} (was: ${current:-nothing})."
