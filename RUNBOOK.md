# Runbook

Operational procedures for `orders-api` and `notify-svc` on ECS Fargate.
Commands use **production**. For staging, replace `production` with `staging`.

| Thing | Where |
|---|---|
| Service logs | CloudWatch log groups `/ecs/ea-foods-production-orders-api` and `/ecs/ea-foods-production-notify-svc` |
| Database logs | `/aws/rds/instance/ea-foods-production/error` and `/slowquery` |
| Alarms | CloudWatch alarms prefixed `ea-foods-production-`, sent to SNS topic `ea-foods-production-alarms` |
| Running release | `curl -sI https://<domain>/orders \| grep -i x-app-version`, or SSM parameter `/ea-foods/production/image-tag` |
| Previous release | SSM parameter `/ea-foods/production/previous-image-tag` |
| Deploy / rollback | GitHub Actions workflows `Deploy` and `Rollback`, or `scripts/deploy.sh` and `scripts/rollback.sh` |

To use the CLI commands below, assume the environment's deploy role (`ea-foods-gha-deploy-production`) or an equivalent admin role, and `export TF_STATE_BUCKET=<bucket>`.

---

## 1. Rolling back a bad release

### Symptoms
- `…-5xx-rate`, `…-unhealthy-targets` or `…-alb-5xx` alarm fires shortly after a deploy.
- The deploy pipeline failed at the smoke test.
- Users report errors and the timing matches a release.

### What already happened automatically
1. **ECS deployment circuit breaker.** If the new tasks failed their health checks, ECS has already gone back to the previous task definition, and the deploy job failed.
2. **Pipeline auto-rollback.** If the deploy or smoke test failed after the apply, the `_deploy` job has already redeployed the last known-good tag. You'll see a warning annotation and a red run.

Check the current state before acting:
```bash
curl -sI https://<domain>/orders | grep -i x-app-version
aws ssm get-parameter --name /ea-foods/production/image-tag --query Parameter.Value --output text
```

### Decide
- **Roll back** when the impact started with the latest release. It's the fastest, safest fix.
- **Fix forward** only when a rollback is impossible, for example when the previous release can't run against the current schema. Migrations must be backward compatible, so this should be rare.

### Option A: GitHub (preferred)
1. Go to **Actions → Rollback → Run workflow**.
2. Set `environment` to `production`.
3. Set `image_tag`: leave it empty for the release before the current one, or enter a specific commit SHA.
4. Approve the production deployment when asked.

The workflow redeploys that immutable image through the same path as a normal deploy: plan, then apply and wait for steady state, then smoke test the version header, then record the release.

### Option B: CLI (GitHub is down)
```bash
scripts/rollback.sh production            # release before the current one
scripts/rollback.sh production <git-sha>  # any image still in ECR (the last 30 are kept)

# list recent releases
aws ecr describe-images --repository-name ea-foods/orders-api \
  --query 'sort_by(imageDetails,&imagePushedAt)[-10:].[imageTags[0],imagePushedAt]' --output table
```

### Option C: emergency (Terraform or state unavailable)
Point the service straight at an earlier task definition revision:
```bash
aws ecs list-task-definitions --family-prefix ea-foods-production-orders-api --sort DESC --max-items 5
aws ecs update-service --cluster ea-foods-production --service orders-api \
  --task-definition ea-foods-production-orders-api:<revision>
aws ecs wait services-stable --cluster ea-foods-production --services orders-api
```
This creates **drift** from Terraform. As soon as possible afterwards, run Option A or B with the same tag so Terraform's state matches what's running again.

### Verify
- `x-app-version` on `/orders` and `/notify` shows the expected SHA.
- The alarms go back to `OK`. The 5xx-rate alarm needs 3 good minutes out of 5.
- Logs look clean. CloudWatch Logs Insights on the `notify-svc` log group:
  ```
  fields @timestamp, status, path | filter status >= 500 | sort @timestamp desc | limit 50
  ```

### Afterwards
- Revert or fix the bad commit on `main`. Otherwise the next merge redeploys it.
- Write a short incident note: timeline, impact, cause, follow-ups.

> **Database caveat.** Rollbacks never reverse migrations. Every migration must follow
> *expand/contract*: add new columns or tables first, deploy code that uses them, and
> remove the old ones in a later release. That way the previous release always runs on the newer schema.

---

## 2. Point-in-time database restore

**Use this for** data loss or corruption: a bad migration, an application bug, or a manual mistake.
**Don't use it for** a database instance or AZ failure. Multi-AZ fails over automatically in about 1–2 minutes.

| | Production | Staging |
|---|---|---|
| Restore window (backup retention) | 14 days | 3 days |
| RPO (data you can lose) | about 5 minutes. Transaction logs are shipped every 5 minutes; see `LatestRestorableTime` | same |
| RTO (time to recover) | about 30–60 minutes for a small database. Most of it is creating the instance and replaying logs | same |

**Rule: always restore to a *new* instance. Never overwrite the live one.** Then either copy the lost data back, or cut over to the restored instance.

### 1. Find the restore time (UTC)
Pick the last moment *before* the bad event. Use app logs, deploy times (the `Deploy` workflow history) and CloudTrail.
```bash
aws rds describe-db-instances --db-instance-identifier ea-foods-production \
  --query 'DBInstances[0].LatestRestorableTime'
aws rds describe-db-instance-automated-backups --db-instance-identifier ea-foods-production \
  --query 'DBInstanceAutomatedBackups[0].RestoreWindow'
```

### 2. (Optional) Stop writes while you investigate
If ongoing writes make the damage worse, scale `orders-api` to zero. Autoscaling's minimum must be lowered first, or it scales the service straight back up.
```bash
aws application-autoscaling register-scalable-target --service-namespace ecs \
  --resource-id service/ea-foods-production/orders-api --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 0 --max-capacity 0
```
`/orders` then returns 503 from the ALB. `notify-svc` isn't affected. The next deploy restores the capacity settings.

### 3. Restore to a new instance
```bash
RESTORE_TIME=2026-11-28T09:14:00Z          # from step 1
TARGET=ea-foods-production-restore-$(date -u +%Y%m%d%H%M)
DB_SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=ea-foods-production-db \
  --query 'SecurityGroups[0].GroupId' --output text)

aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier ea-foods-production \
  --target-db-instance-identifier "$TARGET" \
  --restore-time "$RESTORE_TIME" \
  --db-subnet-group-name ea-foods-production \
  --vpc-security-group-ids "$DB_SG" \
  --db-parameter-group-name ea-foods-production \
  --no-publicly-accessible \
  --manage-master-user-password \
  --deletion-protection

aws rds wait db-instance-available --db-instance-identifier "$TARGET"
```
- The restored instance keeps the **same security group**, so it is just as private: only `orders-api` tasks can reach it.
- `--manage-master-user-password` gives it its own RDS-managed secret.

### 4. Verify the restored data
There's no bastion host. Run a one-off `orders-api` task instead: it already has network access to the database. Point it at the restored host:
```bash
RESTORED_HOST=$(aws rds describe-db-instances --db-instance-identifier "$TARGET" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
NETWORK=$(aws ecs describe-services --cluster ea-foods-production --services orders-api \
  --query 'services[0].networkConfiguration' --output json)

aws ecs run-task --cluster ea-foods-production --launch-type FARGATE \
  --task-definition ea-foods-production-orders-api --network-configuration "$NETWORK" \
  --overrides "{\"containerOverrides\":[{\"name\":\"orders-api\",
    \"environment\":[{\"name\":\"DB_HOST\",\"value\":\"$RESTORED_HOST\"}],
    \"command\":[\"python\",\"manage.py\",\"shell\",\"-c\",
      \"from orders.models import Order; print(Order.objects.count(), Order.objects.order_by('-id').values()[:5])\"]}]}"
```
The output appears in `/ecs/ea-foods-production-orders-api`.

> This task still reads the **production** database password, because its secrets come from the task definition. Before running it, set the restored instance's master password to the production value with `aws rds modify-db-instance --master-user-password`, or use a task definition copy that references the restored instance's secret.

### 5. Recover: choose one
**(a) Repair in place (preferred for partial loss).** Copy the affected rows or tables from the restored instance back into production, for example with `mysqldump --where=...` from a one-off task. Writes made since the incident are kept.

**(b) Full cutover (widespread corruption).** Swap the instance identifiers. The RDS endpoint hostname comes from the identifier, so `DB_HOST` doesn't change:
```bash
aws rds modify-db-instance --db-instance-identifier ea-foods-production \
  --new-db-instance-identifier ea-foods-production-corrupt --apply-immediately
aws rds wait db-instance-available --db-instance-identifier ea-foods-production-corrupt
aws rds modify-db-instance --db-instance-identifier "$TARGET" \
  --new-db-instance-identifier ea-foods-production --apply-immediately
aws rds wait db-instance-available --db-instance-identifier ea-foods-production
```
Then bring Terraform back in line and roll the services, so they pick up the restored instance's secret:
```bash
cd infra/envs/production
terraform init -backend-config="bucket=$TF_STATE_BUCKET"
terraform state rm module.stack.module.rds.aws_db_instance.this
terraform import -var image_tag=<current-sha> module.stack.module.rds.aws_db_instance.this ea-foods-production
cd - && scripts/deploy.sh production <current-sha>
```
Restore the autoscaling limits if you changed them in step 2. The deploy does this.

### 6. Clean up
- Keep `ea-foods-production-corrupt` (or the restore instance) until the incident review is done. Then take a final snapshot and delete it.
- Rehearse this procedure in **staging** each quarter. Staging's 3-day retention exists partly for that.

---

## 3. Alarm reference

| Alarm | Likely causes | First steps |
|---|---|---|
| `…-orders-api-5xx-rate` | Bad release, database unreachable or overloaded, DB credentials rotated | Check whether a deploy just happened, then section 1. Search logs for `OperationalError` / `Access denied`. Check the `db-cpu-high` alarm. |
| `…-notify-svc-5xx-rate` | Bad release | Section 1 |
| `…-unhealthy-targets` | Tasks crashing or failing `/health`, out of memory | `aws ecs describe-services ... --query 'services[0].events[:10]'`; check stopped-task reasons; check the logs |
| `…-cpu-high` | Traffic spike beyond max tasks, CPU-heavy code path | Check the task count against max. Raise `max_tasks` or the task size in `infra/envs/production/main.tf` |
| `…-alb-5xx` | No healthy targets (503), timeouts (504) | Same as unhealthy targets |
| `…-db-cpu-high` | Slow queries, missing index, traffic spike | Check `/slowquery` logs; consider a larger `db_instance_class` |
| `…-db-storage-low` | Storage autoscaling reached its ceiling | Raise `max_allocated_storage_gb` |

### Known operational risk: database password rotation
The DB password is an RDS-managed secret, injected when a task **starts**. If rotation is enabled and the password rotates, running tasks keep the old one until they're replaced. **Fix:** force a new deployment:
```bash
aws ecs update-service --cluster ea-foods-production --service orders-api --force-new-deployment
```
A planned improvement is to automate this with an EventBridge rule on the Secrets Manager `RotationSucceeded` event (see the README, "What I'd add").
