# =============================================================================
# Remote State Backend — Dev Environment
# =============================================================================
# See environments/network/backend.tf for configuration options.
# Use a different key than the network environment.
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_YOUR_TFSTATE_BUCKET"
    key            = "transit-gw-learn/dev/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
