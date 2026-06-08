output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnets" {
  description = "List of public subnet IDs."
  value       = [for k, s in aws_subnet.public : s.id]
}

output "private_subnets" {
  description = "List of private subnet IDs."
  value       = [for k, s in aws_subnet.private : s.id]
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway."
  value       = aws_nat_gateway.this.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway."
  value       = aws_internet_gateway.this.id
}
