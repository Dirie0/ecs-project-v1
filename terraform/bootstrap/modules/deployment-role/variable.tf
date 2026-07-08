variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name, used in resource naming"
  type        = string
}

variable "github_repo" {
  description = "owner/repo, e.g. Dirie0/ecs-project-v1"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider (from bootstrap/oidc output)"
  type        = string
}