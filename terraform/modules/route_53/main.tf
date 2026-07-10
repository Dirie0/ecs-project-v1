resource "aws_route53_zone" "main" {
  name = var.domain_name
  tags = merge(
    var.common_tags,
    {
      Name    = var.domain_name
      Service = "dns"
    }
  )
}


resource "aws_route53domains_registered_domain" "main" {
  domain_name = var.domain_name
  dynamic "name_server" {
    for_each = aws_route53_zone.main.name_servers
    content {
      name = name_server.value
    }
  }
}

