variable "aws_region" {
  description = "AWS region for all resources in this environment."
  type        = string
  default     = "us-west-2"
}

variable "dev_account_id" {
  description = "12-digit AWS account ID for the dev workload account."
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.dev_account_id))
    error_message = "dev_account_id must be a 12-digit AWS account ID."
  }
}

variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "aws-transit-gw-learn"
}

variable "availability_zones" {
  description = "List of availability zones for private subnets. Must be in var.aws_region."
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}
