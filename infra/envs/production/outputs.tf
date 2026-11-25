output "url" {
  value = module.stack.url
}

output "alb_dns_name" {
  value = module.stack.alb_dns_name
}

output "cluster_name" {
  value = module.stack.cluster_name
}

output "orders_api_task_family" {
  value = module.stack.orders_api_task_family
}

output "orders_api_security_group_id" {
  value = module.stack.orders_api_security_group_id
}

output "private_subnet_ids" {
  value = module.stack.private_subnet_ids
}

output "db_identifier" {
  value = module.stack.db_identifier
}
