variable "aws_region" {
  description = "AWS region for the IPAM operating region and regional pool locale."
  type        = string
}

variable "project" {
  description = "Project name, used for resource naming and tagging."
  type        = string
}

variable "root_cidr" {
  description = "CIDR block for the root IPAM pool. Should be a large RFC 1918 block (e.g., 10.0.0.0/8)."
  type        = string
  default     = "10.0.0.0/8"
}

variable "regional_cidr" {
  description = "CIDR block for the regional pool. Must be within root_cidr."
  type        = string
  default     = "10.0.0.0/16"
}

variable "network_cidr" {
  description = "CIDR block for the network account pool. Must be within regional_cidr and non-overlapping with dev/prod CIDRs."
  type        = string
  default     = "10.0.0.0/24"
}

variable "dev_cidr" {
  description = "CIDR block for the dev workload pool. Must be within regional_cidr."
  type        = string
  default     = "10.0.1.0/24"
}

variable "prod_cidr" {
  description = "CIDR block for the prod workload pool. Must be within regional_cidr and non-overlapping with dev_cidr."
  type        = string
  default     = "10.0.2.0/24"
}
