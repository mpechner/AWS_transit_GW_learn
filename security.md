# Security

## IAM Trust Model

### terraform-execute Role

All Terraform operations assume the `terraform-execute` role in the target account.
This role was created by `tf_take2/TF_org_user` and exists in each account.

```
Local credentials (your workstation or CI)
  │
  └── sts:AssumeRole → arn:aws:iam::<ACCOUNT_ID>:role/terraform-execute
        │
        └── Terraform applies resources in that account
```

**Trust policy** (what entities can assume this role):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::<MANAGEMENT_ACCOUNT_ID>:root"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "sts:ExternalId": "<external-id-if-set>"
      }
    }
  }]
}
```

**Simplified for learning**: The trust policy above allows any principal in the
management account. Production hardening: restrict to a specific IAM user, role,
or OIDC identity provider (for CI/CD pipelines like GitHub Actions).

---

## Permissions Per Account

### Network Account (terraform-execute)

Minimum permissions needed for this repo. The network account creates IPAM,
TGW, RAM shares, **and** its own VPC (with subnets, route table, and TGW
attachment), so it needs both the shared-infrastructure and VPC permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "IPAM",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateIpam",
        "ec2:DeleteIpam",
        "ec2:DescribeIpams",
        "ec2:ModifyIpam",
        "ec2:CreateIpamPool",
        "ec2:DeleteIpamPool",
        "ec2:DescribeIpamPools",
        "ec2:ModifyIpamPool",
        "ec2:ProvisionIpamPoolCidr",
        "ec2:DeprovisionIpamPoolCidr",
        "ec2:GetIpamPoolAllocations",
        "ec2:GetIpamPoolCidrs",
        "ec2:AllocateIpamPoolCidr",
        "ec2:ReleaseIpamPoolAllocation"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TransitGateway",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTransitGateway",
        "ec2:DeleteTransitGateway",
        "ec2:DescribeTransitGateways",
        "ec2:ModifyTransitGateway",
        "ec2:CreateTransitGatewayRouteTable",
        "ec2:DeleteTransitGatewayRouteTable",
        "ec2:DescribeTransitGatewayRouteTables",
        "ec2:AssociateTransitGatewayRouteTable",
        "ec2:DisassociateTransitGatewayRouteTable",
        "ec2:EnableTransitGatewayRouteTablePropagation",
        "ec2:DisableTransitGatewayRouteTablePropagation",
        "ec2:CreateTransitGatewayRoute",
        "ec2:DeleteTransitGatewayRoute",
        "ec2:SearchTransitGatewayRoutes",
        "ec2:DescribeTransitGatewayAttachments",
        "ec2:AcceptTransitGatewayVpcAttachment",
        "ec2:RejectTransitGatewayVpcAttachment"
      ],
      "Resource": "*"
    },
    {
      "Sid": "VPC",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:DescribeVpcs",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:DescribeSubnets",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:CreateTransitGatewayVpcAttachment",
        "ec2:DeleteTransitGatewayVpcAttachment",
        "ec2:DescribeTransitGatewayVpcAttachments",
        "ec2:ModifyTransitGatewayVpcAttachment"
      ],
      "Resource": "*"
    },
    {
      "Sid": "RAM",
      "Effect": "Allow",
      "Action": [
        "ram:CreateResourceShare",
        "ram:DeleteResourceShare",
        "ram:UpdateResourceShare",
        "ram:AssociateResourceShare",
        "ram:DisassociateResourceShare",
        "ram:GetResourceShares",
        "ram:ListResourceSharePermissions",
        "ram:TagResource",
        "ram:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Tagging",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Organizations",
      "Effect": "Allow",
      "Action": [
        "organizations:DescribeOrganization"
      ],
      "Resource": "*"
    }
  ]
}
```

### Dev / Prod Accounts (terraform-execute)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VPC",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:DescribeVpcs",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:DescribeSubnets",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TGWAttachment",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTransitGatewayVpcAttachment",
        "ec2:DeleteTransitGatewayVpcAttachment",
        "ec2:DescribeTransitGatewayVpcAttachments",
        "ec2:ModifyTransitGatewayVpcAttachment",
        "ec2:DescribeTransitGatewayAttachments"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IPAMAllocation",
      "Effect": "Allow",
      "Action": [
        "ec2:AllocateIpamPoolCidr",
        "ec2:ReleaseIpamPoolAllocation",
        "ec2:GetIpamPoolAllocations",
        "ec2:DescribeIpamPools"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Tagging",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags",
        "ec2:DeleteTags"
      ],
      "Resource": "*"
    }
  ]
}
```

**Note**: The policies above use `"Resource": "*"` for simplicity. Production
hardening: scope resources to specific ARNs and add condition keys like
`aws:RequestedRegion` to restrict to a single region.

---

## Cross-Account Security Considerations

### RAM Sharing

Both the IPAM pools and the Transit Gateway are shared via RAM with
`allow_external_principals = false`.

This means:
- Only accounts within the same AWS Organization can receive the share
- External accounts (even if they have the resource ARN) cannot access it
- If an account leaves the organization, the share is automatically revoked

**What this does NOT prevent**: An account inside your organization that is
compromised or misconfigured could still create VPCs from the IPAM pool or
create TGW attachments. See the "Production Hardening" section for OU-scoped sharing.

### Transit Gateway Attachment Security

With `auto_accept_shared_attachments = "enable"`, any account in the organization
can attach a VPC to the TGW. This is a broad permission.

**Mitigations in this design**:
- TGW is only shared to the organization (not public)
- `allow_external_principals = false` on the RAM share
- Route propagation is scoped to whatever CIDRs the VPC actually has

**Production hardening**: Disable auto-accept. Use an EventBridge rule to notify
on new pending attachments. Require explicit approval before accepting. This gives
the network team control over what joins the transit network.

### EBS Encryption

EBS encryption by default is **deployed** in both dev and prod environments via
`aws_ebs_encryption_by_default`. This is an account-level setting — every new
EBS volume (including EC2 root volumes) in that account and region is encrypted
automatically. No per-instance configuration is required.

The AWS-managed EBS key (`aws/ebs`) is used by default.

**Production hardening**: Specify a customer-managed KMS key:

```hcl
resource "aws_ebs_default_kms_key" "main" {
  key_arn = aws_kms_key.ebs.arn
}
```

A CMK gives you control over key rotation policy, access policy (which roles
can decrypt volumes), and the ability to revoke access by disabling the key.

### IMDSv2 (Instance Metadata Service)

There are no EC2 instances in this repo. When instances are added, enforce IMDSv2
in every launch template:

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"  # IMDSv2 — rejects unauthenticated requests
  http_put_response_hop_limit = 1           # blocks container-to-host IMDS escape
}
```

`http_tokens = "required"` prevents IMDSv1 requests. IMDSv1 allows unauthenticated
GET requests to `169.254.169.254`, which SSRF vulnerabilities can exploit to
retrieve instance credentials (the Capital One breach vector).

`http_put_response_hop_limit = 1` ensures the token exchange cannot traverse an
extra network hop, which prevents a container from reaching the host's IMDS
through a bridge network.

**Production hardening**: Enforce via SCP at the org level so no account can
launch an instance without IMDSv2, regardless of who runs the launch command:

```json
{
  "Sid": "RequireIMDSv2",
  "Effect": "Deny",
  "Action": "ec2:RunInstances",
  "Resource": "arn:aws:ec2:*:*:instance/*",
  "Condition": {
    "StringNotEquals": {
      "ec2:MetadataHttpTokens": "required"
    }
  }
}
```

Without the SCP, a developer can override the launch template default at
instance launch time. The SCP makes it impossible at the API level.
Also add the AWS Config rule `ec2-imdsv2-check` to detect any instances that
predate the control.

### Provider Isolation

Each Terraform environment assumes `terraform-execute` only in its target account.
The network environment cannot modify dev resources, and vice versa. This is
enforced by the IAM trust policy on each role — the role in the dev account
does not trust the same principal as the role in the network account
(or if it does, that principal cannot assume both simultaneously in a single plan
without explicit configuration).

---

## KMS Considerations

Phase 1 does not use KMS-encrypted resources. The resources in scope
(IPAM, TGW, VPC, subnets, route tables) do not support customer-managed KMS keys.

**Where KMS applies in production extensions of this design**:

| Resource | KMS use case |
|----------|--------------|
| VPC Flow Logs (S3) | S3 bucket encryption with CMK |
| VPC Flow Logs (CloudWatch) | CloudWatch log group with CMK |
| CloudTrail | Trail encryption with CMK |
| SSM Parameter Store (if used for state sharing) | SecureString parameters |

**KMS cross-account policy pattern** (for flow logs in a centralized logging account):

```json
{
  "Sid": "AllowWorkloadAccountToUseKey",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::<WORKLOAD_ACCOUNT_ID>:root"
  },
  "Action": [
    "kms:GenerateDataKey",
    "kms:Decrypt"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "s3.us-west-2.amazonaws.com"
    }
  }
}
```

Never use `"Principal": "*"` in a KMS key policy. Always scope to specific
account principals and use `kms:ViaService` conditions where applicable.

---

## Logging Guidance

### VPC Flow Logs (not deployed in Phase 1)

Add to the workload-vpc module to enable in production:

```hcl
resource "aws_flow_log" "vpc" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = var.flow_log_role_arn
  log_destination = var.flow_log_destination_arn

  tags = {
    Name        = "${var.project}-${var.environment}-flow-logs"
    Environment = var.environment
  }
}
```

Recommended destinations:
- **S3 (centralized logging account)**: cheapest, queryable with Athena
- **CloudWatch Logs**: easier to query interactively, more expensive at scale

### CloudTrail

CloudTrail should be enabled at the organization level in the management account.
This captures all API calls across all accounts, including:
- `ec2:CreateTransitGatewayVpcAttachment` — who attached what
- `ram:AssociateResourceShare` — who shared what
- `ec2:AllocateIpamPoolCidr` — who allocated IPs from which pool

These events are important for audit trails in security incidents.

### Recommended: Enable CloudTrail Organization Trail

```bash
# Run in management account
aws cloudtrail create-trail \
  --name org-trail \
  --s3-bucket-name your-cloudtrail-bucket \
  --is-organization-trail \
  --is-multi-region-trail
```

---

## Accepted Simplifications

The following are intentional simplifications for the learning environment.
Each would need addressing before production use.

| Simplification | Risk | Production Fix |
|----------------|------|----------------|
| `auto_accept_shared_attachments = "enable"` | Any org account can join transit network | Disable, implement approval workflow |
| RAM shared to entire org | Overly broad — all org accounts can use IPAM pools and TGW | Share to specific OUs only |
| No VPC Flow Logs | No network traffic visibility | Add flow log resources per VPC |
| No CloudTrail enforcement | API actions not auditable | Enable org-level CloudTrail |
| `terraform-execute` trust is broad | Over-privileged if shared | Scope to specific OIDC/role, add ExternalId |
| Account IDs in tfvars | Requires careful `.gitignore` discipline | Use SSM, Vault, or CI/CD secrets |
| Remote state coupling | Environments depend on network layer state being accessible | Use SSM Parameter Store for looser coupling |
| No SCPs | No guardrails on what accounts can do | Add SCPs for region restriction, IMDSv2 enforcement, etc. — see IMDSv2 section above. Region SCPs must use `NotAction` to exclude global services (IAM, STS, RAM, Organizations) and `StringNotEquals` (not `IfExists`) — see runbook Phase 0.3 |
| IMDSv2 not enforced by SCP | Developers can override launch template defaults at instance launch | Add SCP denying `ec2:RunInstances` unless `ec2:MetadataHttpTokens = required` — production only |
| EBS uses AWS-managed key | No control over key rotation or access revocation | Specify CMK via `aws_ebs_default_kms_key` — production only |
| No resource-level IAM conditions | Permissions are account-wide | Scope IAM to tagged resources or specific regions |
| No deletion protection | Resources can be destroyed easily | Add Terraform `lifecycle { prevent_destroy }` to critical resources |
| Default VPC security group left intact | AWS creates a default SG allowing all intra-SG traffic in every VPC | Add `aws_default_security_group` resource with empty ingress/egress to remove all rules |

---

## .gitignore and Secret Hygiene

The `.gitignore` excludes `terraform.tfvars` and `*.tfvars` (but keeps `*.tfvars.example`).
Never commit files containing:
- AWS account IDs (if your accounts are sensitive)
- AWS access keys or secret keys
- Any file matching `terraform.tfvars` (use `terraform.tfvars.example` as the template)

The `.gitignore` also excludes `.env` and `.envrc`. Use those patterns to
store credentials locally, or use AWS profiles and SSO.
