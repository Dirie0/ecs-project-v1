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
    Name = "${var.environment}-subnet-${each.key}"
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
    Name = "${var.environment}-subnet-${each.key}"
    }
  )
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id
    tags = merge(
        var.common_tags,
        {
        Name = "${var.environment}-igw"
        }
    )
}

resource "aws_eip" "nat" {
  for_each = aws_subnet.public

  domain = "vpc"

  depends_on = [aws_internet_gateway.main_igw]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-nat-eip-${each.key}"
    }
  )
}

resource "aws_nat_gateway" "nat_gateway" {
  for_each = aws_subnet.public

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id

  depends_on = [aws_internet_gateway.main_igw]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-nat-gateway-${each.key}"
    }
  )
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-public-rt"
    }
  )
}



