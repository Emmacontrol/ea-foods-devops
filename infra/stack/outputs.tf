output "url" {
  value = module.alb.url
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

# Used by the pipeline to run the one-off migration task.
output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "orders_api_task_family" {
  value = module.orders_api.task_definition_family
}

output "orders_api_security_group_id" {
  value = module.orders_api.security_group_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "db_identifier" {
  value = module.rds.identifier
}

output "alarm_topic_arn" {
  value = module.monitoring.alarm_topic_arn
}
