# =============================================================================
# Remote State Backend — Network Environment
# =============================================================================
# Terraform does not support variable interpolation in backend configuration.
# You have two options:
#
# Option A (recommended): Partial backend config via CLI flags
#   terraform init \
#     -backend-config="bucket=mikey-com-terraformstate" \
#     -backend-config="key=transit-gw-learn/network/terraform.tfstate" \
#     -backend-config="region=us-east-1" \
#     -backend-config="use_lockfile=true"
#
# Option B: Edit this file directly (do not commit with real bucket names)
#   Replace REPLACE_WITH_YOUR_TFSTATE_BUCKET with your actual bucket name.
#
# The S3 bucket must already exist.
# Reuse the state bucket from tf_take2 if available.
# The state bucket should have:
#   - Versioning enabled
#   - Server-side encryption (AES-256 or KMS)
#   - Public access blocked
#   - Access logging enabled
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "mikey-com-terraformstate"
    key            = "transit-gw-learn/network/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
