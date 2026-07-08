variable "environment" {
  description = "The environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "alb_security_group_id" {
  description = "The ID of the security group to associate with the ALB"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "vpc_id" {
  description = "The ID of the VPC where the ALB will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "A list of public subnet IDs where the ALB will be created"
  type        = list(string)
}

variable "acm_certificate_arn" {
  description = "The ARN of the ACM certificate to associate with the ALB"
  type        = string
}