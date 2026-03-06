# =============================================================================
# Prod Workload Environment
# =============================================================================
# Mirrors the dev environment — same module, different variables.
# See environments/dev/main.tf for design notes.
#
# Prerequisites (must be applied first):
#   - environments/network — provides TGW ID and IPAM pool ID
#   - environments/dev — not a hard dependency, but prod is typically deployed after dev
# =============================================================================

# -----------------------------------------------------------------------------
# EBS Encryption by Default
# See environments/dev/main.tf for full notes.
# -----------------------------------------------------------------------------
resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
}

module "vpc" {
  source = "../../modules/workload-vpc"

  environment           = "prod"
  project               = var.project
  ipam_pool_id          = var.prod_ipam_pool_id
  transit_gateway_id    = var.transit_gateway_id
  availability_zones    = var.availability_zones
  tgw_route_destination = var.tgw_route_destination
}
