output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB, NAT)."
  value       = [for az in var.azs : aws_subnet.public[az].id]
}

output "app_subnet_ids" {
  description = "Private app subnet IDs (EKS nodes/pods)."
  value       = [for az in var.azs : aws_subnet.app[az].id]
}

output "data_subnet_ids" {
  description = "Private data subnet IDs (Aurora, ElastiCache)."
  value       = [for az in var.azs : aws_subnet.data[az].id]
}

output "intra_subnet_ids" {
  description = "Intra subnet IDs (EKS control plane ENIs, TGW)."
  value       = [for az in var.azs : aws_subnet.intra[az].id]
}

output "app_subnets_by_az" {
  description = "Map AZ -> app subnet ID (used by FIS AZ experiments)."
  value       = { for az in var.azs : az => aws_subnet.app[az].id }
}

output "nat_public_ips" {
  description = "NAT gateway egress IPs (share with customers for DB allowlisting)."
  value       = [for e in aws_eip.nat : e.public_ip]
}
