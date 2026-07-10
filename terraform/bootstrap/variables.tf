variable "bucket_name" {
  description = "The name of the S3 bucket to create"
  type        = string
}


variable "tags" {
  description = "Tags to apply to the S3 bucket"
  type        = map(string)
}

variable "aws_region" {
  description = "The AWS region to create resources in"
  type        = string
}

variable "github_repo" {
  description = "The GitHub repository for the OIDC provider"
  type        = string
}

variable "environment" {
  description = "The environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "The project name for resource naming"
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "The ARN of the OIDC provider"
  type        = string
}

