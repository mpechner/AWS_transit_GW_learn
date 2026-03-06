# =============================================================================
# Remote State Backend — Network Environment
# =============================================================================
# Terraform does not support variable interpolation in backend configuration.
# You have two options:
#
# Option A (recommended): Partial backend config via CLI flags
#   terraform init \
#     -backend-config="bucket=YOUR_TFSTATE_BUCKET" \
#     -backend-config="key=transit-gw-learn/network/terraform.tfstate" \
#     -backend-config="region=us-west-2" \
#     -backend-config="dynamodb_table=terraform-locks"
#
# Option B: Edit this file directly (do not commit with real bucket names)
#   Replace REPLACE_WITH_YOUR_TFSTATE_BUCKET with your actual bucket name.
#
# The S3 bucket and DynamoDB table must already exist.
# Reuse the state bucket and lock table from tf_take2 if available.
# The state bucket should have:
#   - Versioning enabled
#   - Server-side encryption (AES-256 or KMS)
#   - Public access blocked
#   - Access logging enabled
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_YOUR_TFSTATE_BUCKET"
    key            = "transit-gw-learn/network/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
