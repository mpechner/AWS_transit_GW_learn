# =============================================================================
# Network / Shared-Services Environment
# =============================================================================
# This environment owns the shared networking infrastructure:
#   - IPAM: centralized IP address management and pool hierarchy
#   - Transit Gateway: hub-and-spoke connectivity for workload VPCs
#
# Both resources are shared to the AWS Organization via RAM so workload
# accounts (dev, prod) can use them without any cross-account providers here.
#
# Deployment order: apply this environment FIRST, then dev, then prod.
# After apply, run `terraform output` and copy values into workload tfvars.
# =============================================================================

module "ipam" {
  source = "../../modules/ipam"

  aws_region    = var.aws_region
  project       = var.project
  root_cidr     = var.root_cidr
  regional_cidr = var.regional_cidr
  dev_cidr      = var.dev_cidr
  prod_cidr     = var.prod_cidr
}

module "transit_gateway" {
  source = "../../modules/transit-gateway"

  project = var.project
}
