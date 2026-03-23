variable "aws_region" {
  description = "AWS region for all resources in this environment."
  type        = string
  default     = "us-west-2"
}

variable "network_account_id" {
  description = "12-digit AWS account ID for the network/shared-services account. Used to construct the terraform-execute role ARN."
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.network_account_id))
    error_message = "network_account_id must be a 12-digit AWS account ID."
  }
}

variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "aws-transit-gw-learn"
}

# CIDR variables — defaults match the architecture documented in architecture.md.
# Change only if these ranges conflict with your existing address space.

variable "root_cidr" {
  description = "CIDR block for the root IPAM pool. Holds the entire address space for this design."
  type        = string
  default     = "10.0.0.0/8"
}

variable "regional_cidr" {
  description = "CIDR block for the regional pool. Must be within root_cidr."
  type        = string
  default     = "10.0.0.0/16"
}

variable "network_cidr" {
  description = "CIDR block for the network account IPAM pool. Must be within regional_cidr and non-overlapping with dev/prod CIDRs."
  type        = string
  default     = "10.0.0.0/24"
}

variable "dev_cidr" {
  description = "CIDR block for the dev workload IPAM pool. Must be within regional_cidr."
  type        = string
  default     = "10.0.1.0/24"
}

variable "prod_cidr" {
  description = "CIDR block for the prod workload IPAM pool. Must be within regional_cidr and non-overlapping with dev_cidr."
  type        = string
  default     = "10.0.2.0/24"
}
