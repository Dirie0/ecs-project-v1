output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "nat_eip_ids" {
  value       =  module.vpc.nat_eip_ids

}

output "nat_eip_public_ips" {
  value       = module.vpc.nat_eip_public_ips 
}

output "nat_gateway_ids" {
  value       = module.vpc.nat_gateway_ids 

}

output "internet_gateway_id" {
  value       = module.vpc.internet_gateway_id
}

output "security_group_alb_id" {
  value = module.security_groups.security_group_alb_id
}

output "security_group_ecs_id" {
  value = module.security_groups.security_group_ecs_id
}

output "repository_url" {
  value = module.ecr.repository_url
}

output "repository_name" {
  value = module.ecr.repository_name
}

output "acm_certificate_arn" {
  value = module.acm.certificate_arn
}

output "app_log_group" {
  value = module.cloudwatch.app_log_group
}


output "ecs_task_role_arn" {
  value = module.iam.ecs_task_role_arn
}

output "ecs_execution_role_arn" {
  value = module.iam.ecs_task_execution_role_arn
}