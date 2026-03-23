# =============================================================================
# Module: ipam
# =============================================================================
# Creates an AWS IPAM instance with a pool hierarchy for multi-account IP
# address management, and shares the workload pools to the AWS Organization
# via Resource Access Manager (RAM).
#
# Pool Hierarchy:
#   Root Pool  (10.0.0.0/8)          — holds entire address space, no locale
#     └─ Regional Pool (10.0.0.0/16) — scoped to aws_region
#          ├─ Network Pool (10.0.0.0/24) — local to network account
#          ├─ Dev Pool     (10.0.1.0/24) — shared to org, for dev workloads
#          └─ Prod Pool    (10.0.2.0/24) — shared to org, for prod workloads
#
# Workload accounts create VPCs using the shared pool IDs. IPAM tracks and
# enforces all allocations — overlapping CIDRs are rejected at creation time.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_organizations_organization" "current" {}

# -----------------------------------------------------------------------------
# IPAM Instance
# The IPAM must declare every region it will manage. For Phase 1, that is
# just the one region Terraform is configured for.
# -----------------------------------------------------------------------------
resource "aws_vpc_ipam" "main" {
  description = "${var.project} IPAM — centralized IP management"

  operating_regions {
    region_name = var.aws_region
  }

  tags = {
    Name    = "${var.project}-ipam"
    Project = var.project
  }
}

# -----------------------------------------------------------------------------
# Root Pool
# Top of the hierarchy. Holds the entire RFC 1918 /8 block.
# Root pools are not region-scoped (no locale).
# IPAM creates default public and private scopes automatically.
# We use the private scope for RFC 1918 space.
# -----------------------------------------------------------------------------
resource "aws_vpc_ipam_pool" "root" {
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.main.private_default_scope_id
  description    = "Root IPv4 pool — holds entire address space"

  # No locale at root level

  tags = {
    Name    = "${var.project}-ipam-root-pool"
    Project = var.project
    Tier    = "root"
  }
}

# Provision the root CIDR into the root pool.
# This makes 10.0.0.0/8 available for child pools to carve from.
resource "aws_vpc_ipam_pool_cidr" "root" {
  ipam_pool_id = aws_vpc_ipam_pool.root.id
  cidr         = var.root_cidr
}

# -----------------------------------------------------------------------------
# Regional Pool
# Child of root pool. Scoped to a specific region.
# All VPCs and workload pools in this region draw from this pool.
# In Phase 2, add one regional pool per region under the same root pool.
# -----------------------------------------------------------------------------
resource "aws_vpc_ipam_pool" "regional" {
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.main.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.root.id
  locale              = var.aws_region
  description         = "Regional pool — ${var.aws_region}"

  tags = {
    Name    = "${var.project}-ipam-regional-pool-${var.aws_region}"
    Project = var.project
    Region  = var.aws_region
    Tier    = "regional"
  }
}

resource "aws_vpc_ipam_pool_cidr" "regional" {
  ipam_pool_id = aws_vpc_ipam_pool.regional.id
  cidr         = var.regional_cidr

  # The regional CIDR must be within the root pool's CIDR.
  # depends_on ensures the root CIDR is provisioned before we try to carve from it.
  depends_on = [aws_vpc_ipam_pool_cidr.root]
}

# -----------------------------------------------------------------------------
# Network Pool
# Child of the regional pool. Used by the network account's own VPC.
# Not RAM-shared — IPAM lives in the same account so no cross-account
# sharing is needed.
#
# allocation_min/max/default_netmask_length = 24:
#   Enforces that the VPC gets exactly a /24 from this pool.
# -----------------------------------------------------------------------------
resource "aws_vpc_ipam_pool" "network" {
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.main.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.regional.id
  locale              = var.aws_region
  description         = "Network account address pool"

  allocation_default_netmask_length = 24
  allocation_min_netmask_length     = 24
  allocation_max_netmask_length     = 24

  tags = {
    Name        = "${var.project}-ipam-network-pool"
    Project     = var.project
    Environment = "network"
    Tier        = "workload"
  }
}

resource "aws_vpc_ipam_pool_cidr" "network" {
  ipam_pool_id = aws_vpc_ipam_pool.network.id
  cidr         = var.network_cidr

  depends_on = [aws_vpc_ipam_pool_cidr.regional]
}

# -----------------------------------------------------------------------------
# Dev Pool
# Child of the regional pool. Used exclusively by dev workloads.
# Shared to the organization via RAM so the dev account can allocate from it.
#
# allocation_min/max/default_netmask_length = 24:
#   Enforces that each VPC gets exactly a /24 from this pool.
#   Prevents one VPC from claiming the entire pool range.
# -----------------------------------------------------------------------------
resource "aws_vpc_ipam_pool" "dev" {
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.main.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.regional.id
  locale              = var.aws_region
  description         = "Dev workload address pool"

  allocation_default_netmask_length = 24
  allocation_min_netmask_length     = 24
  allocation_max_netmask_length     = 24

  tags = {
    Name        = "${var.project}-ipam-dev-pool"
    Project     = var.project
    Environment = "dev"
    Tier        = "workload"
  }
}

resource "aws_vpc_ipam_pool_cidr" "dev" {
  ipam_pool_id = aws_vpc_ipam_pool.dev.id
  cidr         = var.dev_cidr

  depends_on = [aws_vpc_ipam_pool_cidr.regional]
}

# -----------------------------------------------------------------------------
# Prod Pool
# -----------------------------------------------------------------------------
resource "aws_vpc_ipam_pool" "prod" {
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.main.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.regional.id
  locale              = var.aws_region
  description         = "Prod workload address pool"

  allocation_default_netmask_length = 24
  allocation_min_netmask_length     = 24
  allocation_max_netmask_length     = 24

  tags = {
    Name        = "${var.project}-ipam-prod-pool"
    Project     = var.project
    Environment = "prod"
    Tier        = "workload"
  }
}

resource "aws_vpc_ipam_pool_cidr" "prod" {
  ipam_pool_id = aws_vpc_ipam_pool.prod.id
  cidr         = var.prod_cidr

  depends_on = [aws_vpc_ipam_pool_cidr.regional]
}

# -----------------------------------------------------------------------------
# RAM Share — IPAM Pools
#
# Shares the dev and prod pools with the entire AWS Organization.
# Workload accounts can then use these pool IDs in aws_vpc resources.
#
# allow_external_principals = false:
#   Only accounts within the same AWS Organization can receive this share.
#   This is a security control — never set to true for network resources.
#
# Prerequisite: RAM organization sharing must be enabled in the management
# account: `aws ram enable-sharing-with-aws-organization`
# -----------------------------------------------------------------------------
resource "aws_ram_resource_share" "ipam_pools" {
  name                      = "${var.project}-ipam-pool-share"
  allow_external_principals = false

  tags = {
    Name    = "${var.project}-ipam-pool-share"
    Project = var.project
  }
}

resource "aws_ram_resource_association" "dev_pool" {
  resource_arn       = aws_vpc_ipam_pool.dev.arn
  resource_share_arn = aws_ram_resource_share.ipam_pools.arn
}

resource "aws_ram_resource_association" "prod_pool" {
  resource_arn       = aws_vpc_ipam_pool.prod.arn
  resource_share_arn = aws_ram_resource_share.ipam_pools.arn
}

# Share with the entire organization.
# Production hardening: replace with specific OU ARNs to restrict access.
resource "aws_ram_principal_association" "org" {
  principal          = data.aws_organizations_organization.current.arn
  resource_share_arn = aws_ram_resource_share.ipam_pools.arn
}
