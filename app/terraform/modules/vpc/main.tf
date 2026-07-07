resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_config.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(
    var.common_tags,
    {
      Name = var.vpc_config.name
    }
  )
}

resource "aws_subnet" "public" {
  for_each = var.public_subnet_config

  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(
    var.common_tags,
    {
    Name = "${var.vpc_config.name}-public-${each.key}"
    }
  )
}
resource "aws_subnet" "private" {
  for_each = var.private_subnet_config

  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = merge(
    var.common_tags,
    {
    Name = "${var.vpc_config.name}-private-${each.key}"
    }
  )
}