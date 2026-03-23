# =============================================================================
# Remote State Backend — Dev Environment
# =============================================================================
# See layers/network/backend.tf for configuration options.
# Use a different key than the network environment.
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "mikey-com-terraformstate"
    key            = "transit-gw-learn/dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
