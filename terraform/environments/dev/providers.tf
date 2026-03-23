terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider for the dev workload account.
#
# Assumes the terraform-execute role in the dev account only.
# The TGW and IPAM pool IDs are read from the network layer's remote state
# (see data.tf), which uses ambient credentials to access S3 — not this provider.
provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${var.dev_account_id}:role/terraform-execute"
    session_name = "terraform-${var.project}-dev"
  }

  default_tags {
    tags = {
      Project     = var.project
      Environment = "dev"
      ManagedBy   = "terraform"
      Repo        = "AWS_transit_GW_learn"
    }
  }
}
