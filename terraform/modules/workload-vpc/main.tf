# =============================================================================
# Module: workload-vpc
# =============================================================================
# Creates a VPC with CIDR allocated from a shared IPAM pool, private subnets
# across two availability zones, and a Transit Gateway attachment for
# cross-account connectivity.
#
# Design notes:
#
# No public subnets or Internet Gateway in Phase 1.
# This is intentional — Phase 1 is focused on private connectivity through
# the TGW. Adding internet egress would introduce scope (security groups,
# NAT Gateways, flow logs) that distracts from the core TGW learning objective.
# Phase 2 pattern: centralized egress VPC with NAT Gateways, shared via TGW.
#
# IPAM allocation:
# Using ipv4_ipam_pool_id without cidr_block lets IPAM assign the CIDR.
# ipv4_netmask_length = 24 requests a /24. Since each pool only contains
# one /24, the allocation is deterministic. If IPAM has no /24 available,
# VPC creation fails — this is the guardrail IPAM provides.
#
# Route table:
# A route for var.tgw_route_destination (typically the regional supernet)
# pointing to the TGW covers traffic to all other environments.
# The local route (VPC CIDR → local) is implicit and always present.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# VPC — allocated from IPAM pool
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  ipv4_ipam_pool_id   = var.ipam_pool_id
  ipv4_netmask_length = var.vpc_netmask_length
  # NOTE: ipv4_netmask_length is ForceNew — changing it destroys and recreates
  # the VPC along with all subnets, route tables, and TGW attachments.

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project}-${var.environment}-vpc"
    Environment = var.environment
    Project     = var.project
  }

  # IPAM-allocated VPCs are slow to delete. AWS must deallocate the CIDR back
  # to the IPAM pool before releasing the VPC. This routinely takes 10-20
  # minutes after all subnets and attachments are gone. Terraform's built-in
  # timeout (20m) is usually sufficient. If it times out, re-run destroy.
}

# -----------------------------------------------------------------------------
# Private Subnets
# One subnet per AZ. cidrsubnet() carves /26 subnets from the /24 VPC CIDR:
#   index 0: .0/26   (AZ-a)
#   index 1: .64/26  (AZ-b)
#   index 2: .128/26 (reserved)
#   index 3: .192/26 (reserved)
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  # count is order-sensitive: reordering var.availability_zones will destroy
  # and recreate subnets. Production pattern: use for_each keyed by AZ name.
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 2, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "${var.project}-${var.environment}-private-${count.index + 1}"
    Environment = var.environment
    Project     = var.project
    Tier        = "private"
  }
}

# -----------------------------------------------------------------------------
# Route Table
# A single private route table shared by all subnets in this VPC.
# Routes traffic destined for other environments through the TGW.
# -----------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project}-${var.environment}-private-rt"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# Transit Gateway Attachment
#
# Attaches this VPC to the shared Transit Gateway. The TGW must have been
# shared to this account via RAM before this resource can be created.
#
# Subnets across multiple AZs: TGW creates one ENI per subnet for redundancy.
# If an AZ fails, TGW routes through the ENI in a healthy AZ.
#
# transit_gateway_default_route_table_association = true
# transit_gateway_default_route_table_propagation = true
#   Uses the TGW's default route table (Phase 1 design).
#   This attachment's VPC CIDR will be propagated as a route in the TGW
#   default route table, making this VPC reachable from all other attached VPCs.
#
#   Phase 2: set both to false and explicitly associate with named route tables.
# -----------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.main.id
  subnet_ids         = aws_subnet.private[*].id

  dns_support = "enable"

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = {
    Name        = "${var.project}-${var.environment}-tgw-attachment"
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# VPC Route to Transit Gateway
#
# Routes traffic for the regional supernet through the TGW.
# This covers traffic destined for both dev (10.0.1.x) and prod (10.0.2.x)
# when var.tgw_route_destination = "10.0.0.0/16".
#
# depends_on ensures the TGW attachment is in "available" state before
# Terraform attempts to add the route. Without this, the route creation
# may fail if the attachment ENI is not yet active.
# -----------------------------------------------------------------------------
resource "aws_route" "to_tgw" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = var.tgw_route_destination
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.main]
}
