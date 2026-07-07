variable "aws_region" {
  type = string
}

variable "environment" {
  type = string
}


variable "project_name" {
    type = string
}

variable "bucket_name" {
    type = string
}

variable "tags" {
    type = map(string)
}