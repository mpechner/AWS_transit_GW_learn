# =============================================================================
# Remote State — Read Network Layer Outputs
# =============================================================================
# The network layer (layers/network) must be applied before this environment.
# This data source reads its state to get the Transit Gateway ID and IPAM pool
# ID, eliminating the need to manually copy outputs into tfvars.
#
# Uses ambient AWS credentials (not the provider's assumed role) to read S3,
# so no cross-account IAM wiring is required.
# =============================================================================

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "mikey-com-terraformstate"
    key    = "transit-gw-learn/network/terraform.tfstate"
    region = "us-east-1"
  }
}
