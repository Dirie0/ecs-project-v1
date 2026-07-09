resource "aws_route53_record" "alb" {


  zone_id = var.zone_id


  name = var.domain_name


  type = "A"


  alias {

    name = var.aws_alb_dns_name

    zone_id = var.aws_alb_zone_id

    evaluate_target_health = true

  }

}