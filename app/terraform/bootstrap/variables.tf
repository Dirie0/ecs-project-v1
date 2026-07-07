variable "bucket_name" {
  description = "The name of the S3 bucket to create"
  type        = string
}


variable tags {
  description = "Tags to apply to the S3 bucket"
  type        = map(string)
}

variable "aws_region" {
  description = "The AWS region to create resources in"
  type        = string
}
