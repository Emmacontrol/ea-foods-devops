#!/usr/bin/env bash
# Run `manage.py migrate` as a one-off ECS Fargate task with a given image tag.
#
# Reuses the orders-api task definition (same roles, secrets, env vars, subnets and
# security group) but swaps the image, so migrations run with the NEW code before
# any service task is replaced. Running them in a single one-off task avoids several
# containers racing to migrate the same database on start-up.
#
# Usage: scripts/run-migrations.sh <staging|production> <image-tag>
set -euo pipefail

env="${1:?usage: run-migrations.sh <env> <image-tag>}"
tag="${2:?usage: run-migrations.sh <env> <image-tag>}"
cluster="ea-foods-${env}"
family="ea-foods-${env}-orders-api"

current="$(aws ecs describe-task-definition --task-definition "${family}" --query taskDefinition --output json)"

migrate_def="$(jq --arg tag "${tag}" '
  .containerDefinitions[0].image |= sub(":[^:]+$"; ":" + $tag)
  | {family: (.family + "-migrate"), taskRoleArn, executionRoleArn, networkMode,
     requiresCompatibilities, cpu, memory, runtimePlatform, volumes, containerDefinitions}' <<<"${current}")"

task_def_arn="$(aws ecs register-task-definition --cli-input-json "${migrate_def}" \
  --query taskDefinition.taskDefinitionArn --output text)"

network="$(aws ecs describe-services --cluster "${cluster}" --services orders-api \
  --query 'services[0].networkConfiguration' --output json)"

task_arn="$(aws ecs run-task --cluster "${cluster}" --task-definition "${task_def_arn}" \
  --launch-type FARGATE --network-configuration "${network}" \
  --overrides '{"containerOverrides":[{"name":"orders-api","command":["python","manage.py","migrate","--noinput"]}]}' \
  --query 'tasks[0].taskArn' --output text)"

echo "Migration task started: ${task_arn}"
aws ecs wait tasks-stopped --cluster "${cluster}" --tasks "${task_arn}"

exit_code="$(aws ecs describe-tasks --cluster "${cluster}" --tasks "${task_arn}" \
  --query 'tasks[0].containers[0].exitCode' --output text)"
if [ "${exit_code}" != "0" ]; then
  echo "Migration FAILED (exit code ${exit_code}). Logs: CloudWatch log group /ecs/${family}" >&2
  exit 1
fi
echo "Migrations applied."
