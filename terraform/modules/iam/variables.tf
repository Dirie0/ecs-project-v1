variable "environment" {
  description = "The environment name (e.g., dev, staging, prod)"
  type        = string
}
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}