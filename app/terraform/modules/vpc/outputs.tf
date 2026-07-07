output "vpc_id" {
  value = aws_vpc.main_vpc.id
}

output "public_subnet_ids" {
  value = values(aws_subnet.public)[*].id
}

output "private_subnet_ids" {
  value = values(aws_subnet.private)[*].id
}

output "nat_eip_ids" {
  description = "IDs of the Elastic IPs used by NAT Gateways"
  value       = values(aws_eip.nat)[*].id
}

output "nat_eip_public_ips" {
  description = "Public IP addresses of NAT Gateway Elastic IPs"
  value       = values(aws_eip.nat)[*].public_ip
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = values(aws_nat_gateway.nat_gateway)[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main_igw.id
}