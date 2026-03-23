# =============================================================================
# Network Layer Outputs
# =============================================================================
# These outputs are consumed by dev and prod environments via
# terraform_remote_state (see environments/*/data.tf). No manual copy needed.
#
# To inspect outputs:
#   terraform output -json | python3 -m json.tool
# =============================================================================

output "ipam_id" {
  description = "IPAM instance ID."
  value       = module.ipam.ipam_id
}

output "network_ipam_pool_id" {
  description = "IPAM pool ID for the network account VPC."
  value       = module.ipam.network_pool_id
}

output "network_vpc_id" {
  description = "VPC ID for the network account."
  value       = module.network_vpc.vpc_id
}

output "network_vpc_cidr" {
  description = "CIDR block allocated to the network account VPC."
  value       = module.network_vpc.vpc_cidr
}

output "dev_ipam_pool_id" {
  description = "IPAM pool ID for dev workloads. Read by environments/dev via remote state."
  value       = module.ipam.dev_pool_id
}

output "prod_ipam_pool_id" {
  description = "IPAM pool ID for prod workloads. Read by environments/prod via remote state."
  value       = module.ipam.prod_pool_id
}

output "regional_cidr" {
  description = "Regional CIDR supernet. Used by workload environments as the TGW route destination."
  value       = var.regional_cidr
}

output "transit_gateway_id" {
  description = "Transit Gateway ID. Read by dev and prod environments via remote state."
  value       = module.transit_gateway.tgw_id
}

output "transit_gateway_arn" {
  description = "Transit Gateway ARN."
  value       = module.transit_gateway.tgw_arn
}

output "tgw_default_route_table_id" {
  description = "TGW default route table ID. Use this to verify route propagation after workload environments are applied."
  value       = module.transit_gateway.tgw_default_route_table_id
}

output "ipam_ram_share_arn" {
  description = "ARN of the RAM share for IPAM pools."
  value       = module.ipam.ram_share_arn
}

output "tgw_ram_share_arn" {
  description = "ARN of the RAM share for the Transit Gateway."
  value       = module.transit_gateway.ram_share_arn
}

output "network_account_id" {
  description = "Network account ID (pass-through from variable, used by verify.sh)."
  value       = var.network_account_id
}

output "aws_region" {
  description = "AWS region (pass-through from variable, used by verify.sh)."
  value       = var.aws_region
}

output "next_steps" {
  description = "Reminder of what to do after applying this layer."
  value       = <<-EOT
    Network layer applied. Next steps:
    1. Wait ~60 seconds for RAM shares to propagate to member accounts
    2. Apply dev environment: cd ../../environments/dev && terraform apply
    3. Apply prod environment: cd ../../environments/prod && terraform apply
    Dev and prod read TGW ID and IPAM pool IDs from this layer's remote state
    automatically — no manual copy needed.
  EOT
}
