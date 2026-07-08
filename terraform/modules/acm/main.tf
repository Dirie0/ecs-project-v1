resource "aws_acm_certificate" "app" {
  domain_name       = "dirieisseprojects.co.uk"
  validation_method = "DNS"
}