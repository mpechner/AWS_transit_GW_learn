output "ipam_id" {
  description = "ID of the IPAM instance."
  value       = aws_vpc_ipam.main.id
}

output "ipam_arn" {
  description = "ARN of the IPAM instance."
  value       = aws_vpc_ipam.main.arn
}

output "private_scope_id" {
  description = "ID of the IPAM private scope (default scope for RFC 1918 pools)."
  value       = aws_vpc_ipam.main.private_default_scope_id
}

output "root_pool_id" {
  description = "ID of the root IPAM pool."
  value       = aws_vpc_ipam_pool.root.id
}

output "regional_pool_id" {
  description = "ID of the regional IPAM pool."
  value       = aws_vpc_ipam_pool.regional.id
}

output "network_pool_id" {
  description = "ID of the network account IPAM pool."
  value       = aws_vpc_ipam_pool.network.id
}

output "network_pool_arn" {
  description = "ARN of the network account IPAM pool."
  value       = aws_vpc_ipam_pool.network.arn
}

output "dev_pool_id" {
  description = "ID of the dev workload IPAM pool. Pass this to the dev environment as dev_ipam_pool_id."
  value       = aws_vpc_ipam_pool.dev.id
}

output "dev_pool_arn" {
  description = "ARN of the dev workload IPAM pool."
  value       = aws_vpc_ipam_pool.dev.arn
}

output "prod_pool_id" {
  description = "ID of the prod workload IPAM pool. Pass this to the prod environment as prod_ipam_pool_id."
  value       = aws_vpc_ipam_pool.prod.id
}

output "prod_pool_arn" {
  description = "ARN of the prod workload IPAM pool."
  value       = aws_vpc_ipam_pool.prod.arn
}

output "ram_share_arn" {
  description = "ARN of the RAM resource share for IPAM pools."
  value       = aws_ram_resource_share.ipam_pools.arn
}
