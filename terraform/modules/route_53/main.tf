resource "aws_route53_zone" "main" {

  name = var.domain_name

  tags = merge(
    var.common_tags,
    {
      Name = var.domain_name
      Service = "route_53"

    }
  )
}

