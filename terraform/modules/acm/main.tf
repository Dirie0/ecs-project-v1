resource "aws_acm_certificate" "app" {

  domain_name = var.domain_name

  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

}


resource "aws_route53_record" "validation" {

  zone_id = var.zone_id

  name = tolist(
    aws_acm_certificate.app.domain_validation_options
  )[0].resource_record_name

  type = tolist(
    aws_acm_certificate.app.domain_validation_options
  )[0].resource_record_type

  records = [
    tolist(
      aws_acm_certificate.app.domain_validation_options
    )[0].resource_record_value
  ]

  ttl = 60

}


resource "aws_acm_certificate_validation" "app" {

  certificate_arn = aws_acm_certificate.app.arn

  validation_record_fqdns = [
    aws_route53_record.validation.fqdn
  ]

}