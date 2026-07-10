output "record_name" {
  description = "DNS record name"
  value       = aws_route53_record.main.name
}

output "record_fqdn" {
  description = "Fully qualified domain name"
  value       = aws_route53_record.main.fqdn
}

output "record_type" {
  description = "DNS record type"
  value       = aws_route53_record.main.type
}