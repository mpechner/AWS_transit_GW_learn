terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider for the network/shared-services account.
#
# Assumes the terraform-execute role created by tf_take2/TF_org_user.
# This role must exist in the network account and must trust the principal
# running Terraform (your IAM user, role, or CI identity).
#
# session_name appears in CloudTrail logs — useful for audit trails.
provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${var.network_account_id}:role/terraform-execute"
    session_name = "terraform-${var.project}-network"
  }

  default_tags {
    tags = {
      Project     = var.project
      Environment = "network"
      ManagedBy   = "terraform"
      Repo        = "AWS_transit_GW_learn"
    }
  }
}
