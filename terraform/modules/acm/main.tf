resource "aws_acm_certificate" "app" {

  domain_name = var.domain_name

  validation_method = "DNS"


  lifecycle {

    create_before_destroy = true

  }

}



resource "aws_route53_record" "validation" {


  for_each = {

    for dvo in aws_acm_certificate.app.domain_validation_options :

    dvo.domain_name => dvo

  }


  zone_id = var.zone_id


  name = each.value.resource_record_name


  type = each.value.resource_record_type


  records = [

    each.value.resource_record_value

  ]


  ttl = 60

}



resource "aws_acm_certificate_validation" "app" {


  certificate_arn = aws_acm_certificate.app.arn


  validation_record_fqdns = [

    for record in aws_route53_record.validation :

    record.fqdn

  ]

}