terraform {

  required_version = "~> 1.14.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.50.0"
    }
  }
}
provider "aws" {
  region = var.aws_region
}