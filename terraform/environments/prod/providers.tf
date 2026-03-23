terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider for the prod workload account.
# The TGW and IPAM pool IDs are read from the network layer's remote state
# (see data.tf), which uses ambient credentials to access S3 — not this provider.
provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = "arn:aws:iam::${var.prod_account_id}:role/terraform-execute"
    session_name = "terraform-${var.project}-prod"
  }

  default_tags {
    tags = {
      Project     = var.project
      Environment = "prod"
      ManagedBy   = "terraform"
      Repo        = "AWS_transit_GW_learn"
    }
  }
}
