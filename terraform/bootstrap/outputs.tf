output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN"
  value       = module.oidc.github_oidc_provider_arn
}


output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}


output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = module.ecr.repository_arn
}


output "deployment_roles" {
  description = "Deployment IAM role ARNs by environment"

  value = {
    for environment, role in module.deployment_roles :
    environment => role.role_arn
  }
}


output "ecr_deployment_role_arn" {
  description = "ECR push deployment role ARN"

  value = module.ecr_deployment_role.ecr-deployment-role
}


output "state_buckets" {
  description = "Terraform state bucket names by environment"

  value = {
    for environment, bucket in module.state_buckets :
    environment => bucket.bucket_name
  }
}