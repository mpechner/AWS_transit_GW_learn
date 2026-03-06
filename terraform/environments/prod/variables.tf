variable "aws_region" {
  description = "AWS region for all resources in this environment."
  type        = string
  default     = "us-west-2"
}

variable "prod_account_id" {
  description = "12-digit AWS account ID for the prod workload account."
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.prod_account_id))
    error_message = "prod_account_id must be a 12-digit AWS account ID."
  }
}

variable "project" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "aws-transit-gw-learn"
}

variable "transit_gateway_id" {
  description = "ID of the Transit Gateway created in the network environment. From: terraform output transit_gateway_id"
  type        = string
}

variable "prod_ipam_pool_id" {
  description = "ID of the prod IPAM pool created in the network environment. From: terraform output prod_ipam_pool_id"
  type        = string
}

variable "tgw_route_destination" {
  description = "CIDR block to route through the Transit Gateway. Use the regional supernet to cover all environments."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones for private subnets. Must be in var.aws_region."
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}
