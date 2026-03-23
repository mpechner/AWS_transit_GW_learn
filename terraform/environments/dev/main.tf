# =============================================================================
# Dev Workload Environment
# =============================================================================
# Creates a VPC in the dev account with:
#   - CIDR allocated from the shared IPAM dev pool
#   - Two private subnets (one per AZ)
#   - A route table with a route to the TGW for inter-environment traffic
#   - A TGW attachment to the shared Transit Gateway
#
# Prerequisites (must be applied first):
#   - layers/network — provides TGW ID and IPAM pool ID (read via remote state)
#   - RAM organization sharing enabled and propagated (~60 seconds after network apply)
# =============================================================================

# -----------------------------------------------------------------------------
# EBS Encryption by Default
# Account-level setting: all new EBS volumes (including EC2 root volumes) in
# this account/region are encrypted automatically. Applies immediately to any
# instance launched after this is set — no per-instance configuration needed.
# Uses the AWS-managed EBS key by default.
# Production hardening: specify a customer-managed KMS key via default_kms_key_id
# so you control rotation, access policy, and cross-account sharing.
# -----------------------------------------------------------------------------
resource "aws_ebs_encryption_by_default" "enabled" {
  enabled = true
}

module "vpc" {
  source = "../../modules/workload-vpc"

  environment           = "dev"
  project               = var.project
  ipam_pool_id          = data.terraform_remote_state.network.outputs.dev_ipam_pool_id
  transit_gateway_id    = data.terraform_remote_state.network.outputs.transit_gateway_id
  availability_zones    = var.availability_zones
  tgw_route_destination = data.terraform_remote_state.network.outputs.regional_cidr
}
