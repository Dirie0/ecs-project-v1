variable "aws_region" {
  type = string
}


variable "project_name" {
  type = string
}


variable "github_repo" {
  type = string
}


variable "tags" {
  type = map(string)
}


variable "environments" {
  type = list(string)
}

variable "domain_name" {
  type = string
}