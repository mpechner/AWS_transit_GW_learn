variable "environment" {
  description = "Environment name (e.g., dev, prod, staging). Used in resource names and tags."
  type        = string
}

variable "project" {
  description = "Project name, used for resource naming and tagging."
  type        = string
}

variable "ipam_pool_id" {
  description = "ID of the IPAM pool from which the VPC CIDR will be allocated. Must be shared to this account via RAM."
  type        = string
}

variable "transit_gateway_id" {
  description = "ID of the Transit Gateway to attach to. Must be shared to this account via RAM."
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones for private subnets. Provide exactly 2 for this design."
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for TGW attachment redundancy."
  }
}

variable "vpc_netmask_length" {
  description = "Prefix length to request from the IPAM pool (e.g., 24 for a /24 VPC). Must be within the pool's allocation_min/max_netmask_length constraints."
  type        = number
  default     = 24
}

variable "tgw_route_destination" {
  description = "CIDR block to route through the Transit Gateway. Must be set explicitly by the caller — use the regional supernet (e.g., 10.0.0.0/16) to cover all environments."
  type        = string
  # No default: the caller must supply this explicitly. A network-specific
  # default here would couple the module to one CIDR scheme and silently
  # route incorrectly if the address space differs.
}
