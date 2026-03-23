# =============================================================================
# Remote State Backend — Prod Environment
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "mikey-com-terraformstate"
    key            = "transit-gw-learn/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
