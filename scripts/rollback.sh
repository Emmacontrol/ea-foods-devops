#!/usr/bin/env bash
# Roll back ONE environment to a previous image — by redeploying it with deploy.sh.
#
# Usage:  scripts/rollback.sh <staging|production> [image-tag]
#   no tag   -> the release before the current one (/ea-foods/<env>/previous-image-tag)
#   with tag -> any image still in ECR (the last 30 are kept); list them with:
#               aws ecr describe-images --repository-name ea-foods/orders-api \
#                 --query 'sort_by(imageDetails,&imagePushedAt)[-10:].[imageTags[0],imagePushedAt]' --output table
set -euo pipefail

env="${1:?usage: rollback.sh <staging|production> [image-tag]}"
tag="${2:-}"

if [ -z "${tag}" ]; then
  tag="$(aws ssm get-parameter --name "/ea-foods/${env}/previous-image-tag" --query Parameter.Value --output text)"
fi
current="$(aws ssm get-parameter --name "/ea-foods/${env}/image-tag" --query Parameter.Value --output text 2>/dev/null || echo unknown)"

echo "Rolling back ${env}: ${current} -> ${tag}"
ROLLBACK=true exec "$(dirname "$0")/deploy.sh" "${env}" "${tag}"
