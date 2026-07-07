resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_config.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = var.vpc_tag
}

