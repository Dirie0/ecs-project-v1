variable "vpc_config" {
  description = "VPC config including name and cidr block range"
  type = object({
    cidr_block = string
    name       = string
  })
}

variable "vpc_tag" {
  description = "Tags to apply to the VPC"
  type        = map(string)
}