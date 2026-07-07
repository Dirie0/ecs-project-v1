variable "vpc_config" {
  description = "VPC config including name and cidr block range"
  type = object({
    cidr_block = string
    name       = string
  })
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "public_subnet_config" {
  type = map(object({
    cidr_block = string
    az         = string
  }))
}

variable "private_subnet_config" {
  type = map(object({
    cidr_block = string
    az         = string
  }))
}

