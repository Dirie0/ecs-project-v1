variable "aws_region" {
  type = string
}

variable "environment" {
  type = string
}


variable "bucket_name" {
  type = string
}

variable "vpc_config" {
  type = object({
    cidr_block = string
    name       = string
  })
}

variable "common_tags" {
  type = map(string)
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
    nat_key    = string
  }))
}

