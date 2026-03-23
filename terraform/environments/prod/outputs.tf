output "vpc_id" {
  description = "Prod VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "Prod VPC CIDR block (allocated from IPAM prod pool)."
  value       = module.vpc.vpc_cidr
}

output "private_subnet_ids" {
  description = "Prod private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "private_subnet_cidrs" {
  description = "Prod private subnet CIDR blocks."
  value       = module.vpc.private_subnet_cidrs
}

output "tgw_attachment_id" {
  description = "Prod TGW attachment ID. Verify state is 'available' in network account."
  value       = module.vpc.tgw_attachment_id
}

output "account_id" {
  description = "Prod account ID (pass-through from variable, used by verify.sh)."
  value       = var.prod_account_id
}
