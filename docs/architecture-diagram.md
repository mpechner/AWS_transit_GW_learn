# Architecture Diagrams

Extended diagrams for reference. These supplement the inline diagrams in
[architecture.md](../architecture.md).

---

## Full Resource Map

```
AWS Organization (o-xxxxxxxxxx)
│
├── Management Account
│   └── (org management only — no Terraform resources deployed by this repo)
│
├── Network / Shared-Services Account (111111111111)
│   │
│   ├── AWS IPAM
│   │   ├── Private Scope (auto-created)
│   │   ├── Root Pool: 10.0.0.0/8
│   │   │   └── Regional Pool: 10.0.0.0/16 [us-west-2]
│   │   │       ├── Network Pool: 10.0.0.0/24
│   │   │       │   └── Allocation: 10.0.0.0/24 → network VPC
│   │   │       ├── Dev Pool: 10.0.1.0/24
│   │   │       │   └── Allocation: 10.0.1.0/24 → dev VPC
│   │   │       └── Prod Pool: 10.0.2.0/24
│   │   │           └── Allocation: 10.0.2.0/24 → prod VPC
│   │   └── RAM Resource Share (ipam-pool-share)
│   │       ├── Resources: [dev-pool-arn, prod-pool-arn]
│   │       └── Principal: org-arn (allow_external_principals=false)
│   │
│   ├── Transit Gateway (tgw-xxxxxxxxxxxxxxxxx)
│   │   ├── auto_accept_shared_attachments: enable
│   │   ├── default_route_table_association: enable
│   │   ├── default_route_table_propagation: enable
│   │   ├── Default Route Table (tgw-rtb-xxxxxxxxxxxxxxxxx)
│   │   │   ├── Propagated: 10.0.0.0/24 → network-attachment
│   │   │   ├── Propagated: 10.0.1.0/24 → dev-attachment
│   │   │   └── Propagated: 10.0.2.0/24 → prod-attachment
│   │   └── RAM Resource Share (tgw-share)
│   │       ├── Resource: tgw-arn
│   │       └── Principal: org-arn (allow_external_principals=false)
│   │
│   ├── VPC: aws-transit-gw-learn-network-vpc
│   │   ├── CIDR: 10.0.0.0/24 (allocated from IPAM network pool)
│   │   ├── DNS hostnames: enabled
│   │   ├── Private Subnet AZ-a: 10.0.0.0/26  (us-west-2a)
│   │   ├── Private Subnet AZ-b: 10.0.0.64/26 (us-west-2b)
│   │   └── Route Table: private-rt
│   │       ├── Local: 10.0.0.0/24 → local
│   │       └── TGW:   10.0.0.0/16 → tgw-xxxxxxxxxxxxxxxxx
│   │
│   ├── TGW Attachment: network-tgw-attachment
│   │   ├── Transit Gateway: tgw-xxxxxxxxxxxxxxxxx (local)
│   │   ├── VPC: network VPC
│   │   ├── Subnets: [us-west-2a subnet, us-west-2b subnet]
│   │   ├── State: available (auto-accepted)
│   │   └── Default RT association: yes / propagation: yes
│   │
│   └── IAM Role: terraform-execute
│       └── (created by tf_take2/TF_org_user)
│
├── Dev Workload Account (222222222222)
│   │
│   ├── VPC: aws-transit-gw-learn-dev-vpc
│   │   ├── CIDR: 10.0.1.0/24 (allocated from IPAM dev pool)
│   │   ├── DNS hostnames: enabled
│   │   ├── Private Subnet AZ-a: 10.0.1.0/26  (us-west-2a)
│   │   ├── Private Subnet AZ-b: 10.0.1.64/26 (us-west-2b)
│   │   └── Route Table: private-rt
│   │       ├── Local: 10.0.1.0/24 → local
│   │       └── TGW:   10.0.0.0/16 → tgw-xxxxxxxxxxxxxxxxx
│   │
│   ├── TGW Attachment: dev-tgw-attachment
│   │   ├── Transit Gateway: tgw-xxxxxxxxxxxxxxxxx (shared from network account)
│   │   ├── VPC: dev VPC
│   │   ├── Subnets: [us-west-2a subnet, us-west-2b subnet]
│   │   ├── State: available (auto-accepted)
│   │   └── Default RT association: yes / propagation: yes
│   │
│   └── IAM Role: terraform-execute
│
└── Prod Workload Account (333333333333)
    │
    ├── VPC: aws-transit-gw-learn-prod-vpc
    │   ├── CIDR: 10.0.2.0/24 (allocated from IPAM prod pool)
    │   ├── DNS hostnames: enabled
    │   ├── Private Subnet AZ-a: 10.0.2.0/26  (us-west-2a)
    │   ├── Private Subnet AZ-b: 10.0.2.64/26 (us-west-2b)
    │   └── Route Table: private-rt
    │       ├── Local: 10.0.2.0/24 → local
    │       └── TGW:   10.0.0.0/16 → tgw-xxxxxxxxxxxxxxxxx
    │
    ├── TGW Attachment: prod-tgw-attachment
    │   ├── Transit Gateway: tgw-xxxxxxxxxxxxxxxxx (shared from network account)
    │   ├── VPC: prod VPC
    │   ├── Subnets: [us-west-2a subnet, us-west-2b subnet]
    │   ├── State: available (auto-accepted)
    │   └── Default RT association: yes / propagation: yes
    │
    └── IAM Role: terraform-execute
```

---

## Subnet CIDR Breakdown

```
Network VPC: 10.0.0.0/24 (256 addresses)
┌──────────────────────────────────────────────────────────────┐
│ 10.0.0.0/26   (64 addr) │ Private Subnet AZ-a (us-west-2a)  │
├──────────────────────────────────────────────────────────────┤
│ 10.0.0.64/26  (64 addr) │ Private Subnet AZ-b (us-west-2b)  │
├──────────────────────────────────────────────────────────────┤
│ 10.0.0.128/26 (64 addr) │ Reserved                          │
├──────────────────────────────────────────────────────────────┤
│ 10.0.0.192/26 (64 addr) │ Reserved                          │
└──────────────────────────────────────────────────────────────┘

Dev VPC: 10.0.1.0/24 (256 addresses)
┌──────────────────────────────────────────────────────────────┐
│ 10.0.1.0/26   (64 addr) │ Private Subnet AZ-a (us-west-2a)  │
├──────────────────────────────────────────────────────────────┤
│ 10.0.1.64/26  (64 addr) │ Private Subnet AZ-b (us-west-2b)  │
├──────────────────────────────────────────────────────────────┤
│ 10.0.1.128/26 (64 addr) │ Reserved (future subnet or IGW)   │
├──────────────────────────────────────────────────────────────┤
│ 10.0.1.192/26 (64 addr) │ Reserved (future subnet or IGW)   │
└──────────────────────────────────────────────────────────────┘

Prod VPC: 10.0.2.0/24 (256 addresses)
┌──────────────────────────────────────────────────────────────┐
│ 10.0.2.0/26   (64 addr) │ Private Subnet AZ-a (us-west-2a)  │
├──────────────────────────────────────────────────────────────┤
│ 10.0.2.64/26  (64 addr) │ Private Subnet AZ-b (us-west-2b)  │
├──────────────────────────────────────────────────────────────┤
│ 10.0.2.128/26 (64 addr) │ Reserved                          │
├──────────────────────────────────────────────────────────────┤
│ 10.0.2.192/26 (64 addr) │ Reserved                          │
└──────────────────────────────────────────────────────────────┘
```

---

## Phase 2: Route Segmentation (Design Only)

What the TGW route table structure would look like with environment isolation:

```
Transit Gateway Route Tables (Phase 2 design)

┌─────────────────────────────────────────────────────────────┐
│ dev-route-table                                             │
│   Associations:  dev-attachment                             │
│   Propagations:  dev-attachment                             │
│   Static routes: 0.0.0.0/0 → inspection-attachment         │
│                  10.0.2.0/24 → BLOCKED (no route = drop)    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ prod-route-table                                            │
│   Associations:  prod-attachment                            │
│   Propagations:  prod-attachment                            │
│   Static routes: 0.0.0.0/0 → inspection-attachment         │
│                  10.0.1.0/24 → BLOCKED                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ inspection-route-table                                      │
│   Associations:  inspection-attachment                      │
│   Propagations:  dev-attachment, prod-attachment            │
│   (inspection VPC can reach both; they cannot reach each    │
│    other directly — all traffic hairpins through firewall)  │
└─────────────────────────────────────────────────────────────┘

Traffic flow: dev → prod
  1. dev-subnet → TGW (via dev-attachment)
  2. TGW looks up dev-route-table → 0.0.0.0/0 → inspection
  3. TGW → inspection-attachment → firewall VPC
  4. Firewall inspects, allows/denies
  5. Firewall → TGW (via inspection-attachment)
  6. TGW looks up inspection-route-table → 10.0.2.0/24 → prod-attachment
  7. TGW → prod-subnet
```

---

## Terraform Provider Assume-Role Pattern

```
Workstation / CI Runner
│
│  AWS credentials (IAM user or role with sts:AssumeRole)
│
├── terraform apply (layers/network)
│   └── provider "aws" { assume_role { role_arn = ".../network/.../terraform-execute" }}
│       └── Creates: IPAM, TGW, RAM shares, network VPC + TGW attachment in network account
│
├── terraform apply (environments/dev)
│   └── provider "aws" { assume_role { role_arn = ".../dev/.../terraform-execute" }}
│   └── data "terraform_remote_state" reads layers/network outputs from S3
│       └── Creates: VPC, subnets, TGW attachment in dev account
│
└── terraform apply (environments/prod)
    └── provider "aws" { assume_role { role_arn = ".../prod/.../terraform-execute" }}
    └── data "terraform_remote_state" reads layers/network outputs from S3
        └── Creates: VPC, subnets, TGW attachment in prod account
```

Each `terraform apply` is a separate process that assumes a different role.
There is no cross-account provider aliasing in this design — each environment
only touches one account.
