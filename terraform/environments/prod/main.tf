# =============================================================================
# Prod Workload Environment
# =============================================================================
# Mirrors the dev environment — same module, different variables.
# See environments/dev/main.tf for design notes.
#
# Prerequisites (must be applied first):
#   - layers/network — provides TGW ID and IPAM pool ID (read via remote state)
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
  ipam_pool_id          = data.terraform_remote_state.network.outputs.prod_ipam_pool_id
  transit_gateway_id    = data.terraform_remote_state.network.outputs.transit_gateway_id
  availability_zones    = var.availability_zones
  tgw_route_destination = data.terraform_remote_state.network.outputs.regional_cidr
}
