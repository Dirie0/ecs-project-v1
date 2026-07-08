variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "ecs_execution_role_arn" {
  type = string
}

variable "ecs_task_role_arn" {
  type = string
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

variable "ecr_repository_url" {
    type = string   
}


variable "aws_region" {
    type = string   
}

variable "aws_region" {
    type = string

}

variable "log_group" {
    type = string 
}

variable "app_image" {
    type = string 
}
