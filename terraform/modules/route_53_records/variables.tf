variable "zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}


variable "domain_name" {
  description = "Domain name"
  type        = string
}


variable "alb_dns_name" {
  description = "ALB DNS name"
  type        = string
}


variable "alb_zone_id" {
  description = "ALB hosted zone ID"
  type        = string
}