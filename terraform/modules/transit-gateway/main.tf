# =============================================================================
# Module: transit-gateway
# =============================================================================
# Creates an AWS Transit Gateway and shares it to the AWS Organization via RAM.
#
# Design choices documented here:
#
# auto_accept_shared_attachments = "enable"
#   When a member account creates a VPC attachment to this shared TGW, the
#   attachment is automatically accepted (transitions to "available").
#   Safe within an organization because only org members can attach (enforced
#   by RAM's allow_external_principals = false).
#   Production hardening: set to "disable" and implement an explicit
#   acceptance workflow (EventBridge → SNS → approval → aws_ec2_transit_gateway_vpc_attachment_accepter).
#
# default_route_table_association = "enable"
# default_route_table_propagation = "enable"
#   All attachments automatically associate with the TGW's default route table
#   and propagate their VPC CIDRs into it. This gives full-mesh reachability
#   between all attached VPCs with no additional configuration.
#   Phase 2 pattern: disable both, create per-environment route tables, and
#   manage associations and propagations explicitly for traffic segmentation.
#
# dns_support = "enable"
#   Allows instances in attached VPCs to resolve Route 53 DNS via the TGW.
#   Required if you add centralized DNS (Phase 2).
#
# vpn_ecmp_support = "disable"
#   ECMP (Equal Cost Multi-Path) is only relevant for Site-to-Site VPN.
#   Not needed for this VPC-only design.
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
# Transit Gateway
# -----------------------------------------------------------------------------
resource "aws_ec2_transit_gateway" "main" {
  description                     = "${var.project} Transit Gateway"
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "disable"

  tags = {
    Name    = "${var.project}-tgw"
    Project = var.project
  }
}

# -----------------------------------------------------------------------------
# RAM Share — Transit Gateway
#
# Shares the TGW with the entire organization so workload accounts can
# create VPC attachments using the TGW ID.
#
# After sharing, the TGW appears in the RAM console of each org member account.
# There may be a 30–90 second propagation delay before it is visible.
# -----------------------------------------------------------------------------
resource "aws_ram_resource_share" "tgw" {
  name                      = "${var.project}-tgw-share"
  allow_external_principals = false

  tags = {
    Name    = "${var.project}-tgw-share"
    Project = var.project
  }
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.main.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# Share with the entire organization.
# Production hardening: use specific OU ARNs to restrict which accounts
# can create TGW attachments.
resource "aws_ram_principal_association" "org" {
  principal          = data.aws_organizations_organization.current.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}
