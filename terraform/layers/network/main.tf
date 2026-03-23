# =============================================================================
# Network / Shared-Services Environment
# =============================================================================
# This environment owns the shared networking infrastructure:
#   - IPAM: centralized IP address management and pool hierarchy
#   - Transit Gateway: hub-and-spoke connectivity for workload VPCs
#   - Network VPC: the network account's own VPC, attached to the TGW
#
# IPAM pools and the TGW are shared to the AWS Organization via RAM so
# workload accounts (dev, prod) can use them without cross-account providers.
#
# Deployment order: apply this layer FIRST, then dev, then prod.
# Dev and prod environments read outputs from this layer's remote state.
# =============================================================================

module "ipam" {
  source = "../../modules/ipam"

  aws_region    = var.aws_region
  project       = var.project
  root_cidr     = var.root_cidr
  regional_cidr = var.regional_cidr
  network_cidr  = var.network_cidr
  dev_cidr      = var.dev_cidr
  prod_cidr     = var.prod_cidr
}

module "transit_gateway" {
  source = "../../modules/transit-gateway"

  project = var.project
}

module "network_vpc" {
  source = "../../modules/workload-vpc"

  environment           = "network"
  project               = var.project
  ipam_pool_id          = module.ipam.network_pool_id
  transit_gateway_id    = module.transit_gateway.tgw_id
  availability_zones    = ["${var.aws_region}a", "${var.aws_region}b"]
  tgw_route_destination = var.regional_cidr

  depends_on = [module.ipam, module.transit_gateway]
}
