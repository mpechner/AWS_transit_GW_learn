# =============================================================================
# Network Environment Outputs
# =============================================================================
# After running `terraform apply`, copy these values into the tfvars files
# for the dev and prod environments.
#
# Quick copy command:
#   terraform output -json | python3 -m json.tool
# =============================================================================

output "ipam_id" {
  description = "IPAM instance ID."
  value       = module.ipam.ipam_id
}

output "dev_ipam_pool_id" {
  description = "IPAM pool ID for dev workloads. Copy to dev/terraform.tfvars as dev_ipam_pool_id."
  value       = module.ipam.dev_pool_id
}

output "prod_ipam_pool_id" {
  description = "IPAM pool ID for prod workloads. Copy to prod/terraform.tfvars as prod_ipam_pool_id."
  value       = module.ipam.prod_pool_id
}

output "transit_gateway_id" {
  description = "Transit Gateway ID. Copy to dev/terraform.tfvars and prod/terraform.tfvars as transit_gateway_id."
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

output "next_steps" {
  description = "Reminder of what to do after applying this environment."
  value       = <<-EOT
    Network environment applied. Next steps:
    1. Copy transit_gateway_id, dev_ipam_pool_id → dev/terraform.tfvars
    2. Copy transit_gateway_id, prod_ipam_pool_id → prod/terraform.tfvars
    3. Wait ~60 seconds for RAM shares to propagate to member accounts
    4. Apply dev environment: cd ../dev && terraform apply
    5. Apply prod environment: cd ../prod && terraform apply
  EOT
}
