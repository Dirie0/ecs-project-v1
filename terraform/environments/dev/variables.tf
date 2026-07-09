variable "aws_region" {
  type = string
}

variable "environment" {
  type = string
}


variable "project_name" {
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


variable "task_cpu" {
  type = number
}

variable "task_memory" {
  type = number
}

variable "app_port" {
  type = number
}


variable "app_image" {
  type = string
}

variable "app_count" {
  type = number
}


variable "domain_name" {
  type = string
}