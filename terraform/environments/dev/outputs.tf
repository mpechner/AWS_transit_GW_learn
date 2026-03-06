output "vpc_id" {
  description = "Dev VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "Dev VPC CIDR block (allocated from IPAM dev pool)."
  value       = module.vpc.vpc_cidr
}

output "private_subnet_ids" {
  description = "Dev private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "private_subnet_cidrs" {
  description = "Dev private subnet CIDR blocks."
  value       = module.vpc.private_subnet_cidrs
}

output "tgw_attachment_id" {
  description = "Dev TGW attachment ID. Verify state is 'available' in network account."
  value       = module.vpc.tgw_attachment_id
}
