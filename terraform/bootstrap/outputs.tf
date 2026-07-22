
output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "repository_url" {
  value = aws_ecr_repository.repo.repository_url
}

output "repository_name" {
  value = aws_ecr_repository.repo.name
}

output "repository_arn" {
  value = aws_ecr_repository.repo.arn
}


output "deployment_roles" {
  description = "Deployment IAM role ARNs by environment"

  value = {
    for environment, role in module.deployment_roles :
    environment => role.role_arn
  }
}



output "state_buckets" {
  description = "Terraform state bucket names by environment"

  value = {
    for environment, bucket in module.state_buckets :
    environment => bucket.bucket_name
  }
}


output "zone_id" {
  value = aws_route53_zone.main.zone_id
}


output "nameservers" {
  value = aws_route53_zone.main.name_servers
}


output "domain_name" {
  value = aws_route53_zone.main.name
}

