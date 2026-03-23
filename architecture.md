# Architecture

## What Was Built

This repo builds a single-region, three-account AWS networking foundation:

| Component | Account | Resource |
|-----------|---------|----------|
| IPAM | Network | `aws_vpc_ipam`, pool hierarchy, RAM share |
| Transit Gateway | Network | `aws_ec2_transit_gateway`, RAM share |
| Network VPC | Network | VPC from IPAM pool, private subnets, TGW attachment |
| Dev VPC | Dev | VPC from IPAM pool, private subnets, TGW attachment |
| Prod VPC | Prod | VPC from IPAM pool, private subnets, TGW attachment |

Traffic between dev and prod flows through the Transit Gateway. No traffic leaves
the private RFC 1918 address space in Phase 1 (no internet gateway, no NAT).

---

## Architecture Diagrams

### Account and Resource Ownership

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AWS Organization                                   │
│                                                                             │
│  ┌────────────────── Network Account ──────────────────────────────────┐   │
│  │                                                                      │   │
│  │  IPAM                           Transit Gateway                      │   │
│  │  ┌────────────────────────┐     ┌──────────────────────────────┐    │   │
│  │  │ Scope: private         │     │ auto_accept: enable           │    │   │
│  │  │                        │     │ default_rt_assoc: enable      │    │   │
│  │  │ Root Pool              │     │ default_rt_prop:  enable      │    │   │
│  │  │  10.0.0.0/8            │     │                              │    │   │
│  │  │   │                    │     │ Route Table (default)         │    │   │
│  │  │   └─ Regional Pool     │     │  10.0.0.0/24 → net-attach    │    │   │
│  │  │       10.0.0.0/16      │     │  10.0.1.0/24 → dev-attach    │    │   │
│  │  │        │               │     │  10.0.2.0/24 → prod-attach   │    │   │
│  │  │        ├─ Net Pool     │     │  (propagated automatically)   │    │   │
│  │  │        │   10.0.0.0/24 │     └──────────────┬───────────────┘    │   │
│  │  │        ├─ Dev Pool     │                    │                    │   │
│  │  │        │   10.0.1.0/24 │         RAM-shared to org               │   │
│  │  │        └─ Prod Pool    │                    │                    │   │
│  │  │            10.0.2.0/24 │                    │                    │   │
│  │  └──────────┬─────────────┘                    │                    │   │
│  │             │ RAM-shared to org                 │                    │   │
│  │             │ (dev + prod pools only)           │                    │   │
│  │                                                                      │   │
│  │  Network VPC                                                         │   │
│  │  ┌──────────────────────────────────────────────────────────────┐   │   │
│  │  │ CIDR: 10.0.0.0/24 (from IPAM network pool)                  │   │   │
│  │  │ Subnets: 10.0.0.0/26 (AZ-a), 10.0.0.64/26 (AZ-b)          │   │   │
│  │  │ Route: 10.0.0.0/16 → TGW                                    │   │   │
│  │  │ TGW Attachment ─────────────────────────────────────────┐    │   │   │
│  │  └─────────────────────────────────────────────────────────┘    │   │   │
│  │                                                                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌──────────────┐   ┌──────────────┐                                       │
│  │  Dev Account │   │ Prod Account │                                       │
│  │              │   │              │                                       │
│  │ VPC          │   │ VPC          │                                       │
│  │ 10.0.1.0/24  │   │ 10.0.2.0/24  │                                       │
│  │ (from IPAM)  │   │ (from IPAM)  │                                       │
│  │              │   │              │                                       │
│  │ Subnets:     │   │ Subnets:     │                                       │
│  │ 10.0.1.0/26  │   │ 10.0.2.0/26  │                                       │
│  │ 10.0.1.64/26 │   │ 10.0.2.64/26 │                                       │
│  │      │       │   │      │       │                                       │
│  │ TGW Attach ──┼───┼─TGW Attach ──┼── (all attach to shared TGW)         │
│  └──────────────┘   └──────────────┘                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow: Dev → Prod

```
Dev Subnet (10.0.1.0/26)
  │
  │  Route table: 10.0.0.0/16 → tgw-xxxxxxxx
  ▼
TGW Attachment (dev account, AZ-a ENI)
  │
  │  TGW default route table lookup:
  │  10.0.2.0/24 → prod-attachment (propagated by prod VPC)
  ▼
TGW Attachment (prod account, AZ-a ENI)
  │
  │  Route table: 10.0.0.0/16 → tgw-xxxxxxxx (return traffic)
  ▼
Prod Subnet (10.0.2.0/26)
```

### Terraform State Dependency Flow

```
layers/network
  └── outputs: tgw_id, network/dev/prod_ipam_pool_id, network_vpc_id
        │
        │  terraform_remote_state (reads S3 state directly)
        │
        ├──► environments/dev/data.tf
        │      (transit_gateway_id, dev_ipam_pool_id)
        │
        └──► environments/prod/data.tf
               (transit_gateway_id, prod_ipam_pool_id)
```

Values flow via `terraform_remote_state` — no manual copy step needed.
If the network layer is not applied, `terraform plan` in dev/prod will fail,
implicitly enforcing deployment order.

---

## Why IPAM?

**The problem IPAM solves**: In a multi-account environment without IPAM, teams
independently assign CIDRs to VPCs. Over time this leads to:
- CIDR conflicts that block VPC peering or TGW connectivity
- No audit trail of what IPs are in use
- Manual spreadsheets that drift from reality

**What IPAM provides**:
- Hierarchical pool structure that enforces non-overlapping allocations
- Allocation tracking across all accounts in the organization
- VPC creation will fail if it would create an overlap (enforced by AWS, not humans)
- Visibility into utilization across the entire address space

**Why not just use a spreadsheet?**
A spreadsheet is better than nothing but doesn't prevent conflicts — a developer
can still create a VPC with any CIDR if IPAM isn't enforced. IPAM makes the
guardrail an infrastructure control, not a process control.

**IPAM cost**: $0.00027/IP/hour per monitored IP. For this lab (3 x /24 pools =
768 IPs monitored) that is approximately $0.15/month. Acceptable for a learning
environment.

**Trade-off: IPAM adds operational overhead to labs**. IPAM was chosen here to
learn the service, but it comes with costs beyond dollars:
- VPC deletion takes 10-20 minutes while AWS deallocates the CIDR back to the pool
- Requires IPAM delegated admin setup in the management account
- Requires AWS Organizations service access for `ipam.amazonaws.com`
- RAM shares add another layer to troubleshoot

For a quick lab where learning IPAM is not the goal, hardcoding CIDRs per account
(`cidr_block = "10.0.1.0/24"`) would be simpler, faster to deploy, and
significantly faster to tear down. IPAM shines in production where preventing
CIDR conflicts across dozens of accounts justifies the complexity.

---

## Why Transit Gateway?

**The alternative — VPC Peering — has fundamental scalability limits**:

| | VPC Peering | Transit Gateway |
|-|-------------|-----------------|
| Topology | Mesh (each pair needs a connection) | Hub and spoke |
| Connections for N VPCs | N*(N-1)/2 | N |
| 10 VPCs | 45 peering connections | 10 attachments |
| Transitive routing | Not supported | Supported |
| Cross-account | Requires accepter in each account | Single shared resource |
| Route management | Per-VPC route tables in each pair | Centralized TGW route tables |
| Traffic inspection | Requires hairpinning | Natural insertion point |

**For 2 VPCs**, VPC peering is simpler. But:
- Adding a 3rd environment (staging) with peering requires 2 new connections and 6 new route table entries
- With TGW, adding staging requires 1 attachment and the route propagates automatically
- TGW is the standard for production multi-account networking at AWS

**Why not PrivateLink?**
PrivateLink is for service-to-service connectivity (one endpoint per service, unidirectional).
TGW is for network-level connectivity between VPCs. They serve different purposes.

---

## Design Decisions

### Decision: auto_accept_shared_attachments = "enable"

**Chosen**: `enable`

**Rationale**: When a TGW is shared to an AWS Organization, only accounts within
that organization can create attachments. Enabling auto-accept eliminates the
chicken-and-egg problem (workload account creates attachment → network account
must accept → workload account can route) which would require two Terraform
apply passes or cross-account provider aliases in workload environments.

**Production alternative**: Set to `disable`. Implement an acceptance workflow:
- EventBridge rule on `TransitGatewayAttachmentStateChange` events
- SNS notification to network team
- Lambda or manual approval before acceptance
- Terraform `aws_ec2_transit_gateway_vpc_attachment_accepter` in network environment

This gives explicit control over which VPCs join the transit network.

### Decision: Default Route Table with Propagation Enabled

**Chosen**: Single default route table, propagation enabled on all attachments.

**Rationale**: All VPCs in this design should be able to reach each other. Using
the default route table with propagation means VPC CIDRs are automatically
advertised as routes when attachments are created. No post-attachment apply needed.

**Production alternative**: Disable default route table association and propagation.
Create separate route tables for dev and prod. Only allow the routes you explicitly
need. This is the foundation of traffic segmentation — for example, preventing
dev from reaching prod directly, and routing all inter-environment traffic through
an inspection VPC first. See Phase 2 documentation.

### Decision: Remote State for Cross-Layer Dependencies

**Chosen**: Workload environments read the network layer's outputs via
`data "terraform_remote_state"` (see `environments/*/data.tf`).

**Rationale**: Remote state eliminates the error-prone manual copy step and
implicitly enforces deployment ordering — if the network layer hasn't been
applied, `terraform plan` fails with a clear error. The `data.tf` file in
each environment makes the dependency explicit and discoverable.

The `terraform_remote_state` data source reads S3 using ambient credentials
(the same identity running Terraform), not the provider's assumed role. This
avoids cross-account IAM complexity.

**Production alternative**: Use SSM Parameter Store — the network layer writes
outputs to SSM and workload environments read them with
`data "aws_ssm_parameter"`. This provides even looser coupling and survives
state backend changes.

### Decision: IPAM Pool Sizing

**Chosen**: `/24` pools per environment (256 addresses each).

**Rationale**: Sufficient for a learning lab. Each VPC gets exactly one `/24`,
with room for 4 subnets of `/26` each.

**Production sizing**: Use `/16` per environment minimum to accommodate multiple
VPCs, multiple subnets per AZ, and future growth. Plan your address space
before you need it — re-IPing VPCs is painful.

### Decision: No Public Subnets or Internet Gateway

**Chosen**: Private subnets only.

**Rationale**: Phase 1 is focused on TGW connectivity. Adding internet egress
introduces scope (NAT Gateway, security groups, flow logs) that distracts from
the core learning objective. Verification is done via AWS CLI, not EC2 ping tests.

**Production addition**: Centralized egress VPC with NAT Gateways, shared via
TGW. All workload VPCs route 0.0.0.0/0 through TGW to the egress VPC. This
reduces NAT Gateway costs and centralizes egress monitoring.

---

## Trust Boundaries

```
┌──────────────────────────────────────────────────────────┐
│  AWS Organization Trust Boundary                         │
│                                                          │
│  RAM sharing:  allow_external_principals = false         │
│  TGW:          auto_accept restricted to org members     │
│  IPAM:         org integration required for cross-acct   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Network Account Trust Boundary                   │   │
│  │                                                   │   │
│  │  - Owns IPAM and TGW                              │   │
│  │  - terraform-execute role: scoped to              │   │
│  │    ec2:*, ram:*, vpc-ipam:* in this account       │   │
│  │                                                   │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  ┌─────────────────┐    ┌─────────────────┐             │
│  │  Dev Trust Bdy  │    │  Prod Trust Bdy │             │
│  │                 │    │                 │             │
│  │ terraform-exec  │    │ terraform-exec  │             │
│  │ scoped to ec2:* │    │ scoped to ec2:* │             │
│  │ in dev account  │    │ in prod account │             │
│  └─────────────────┘    └─────────────────┘             │
└──────────────────────────────────────────────────────────┘
```

Terraform assumes `terraform-execute` separately in each account. The role in
account A has no permissions in account B. State is isolated per environment.

---

## IPAM Pool Hierarchy

```
IPAM (private scope)
│
└── Root Pool: 10.0.0.0/8
    │   No locale (not region-scoped)
    │   Holds the entire RFC 1918 /8 block
    │
    └── Regional Pool: 10.0.0.0/16
        │   Locale: us-west-2
        │   Carved from root pool
        │   In multi-region (Phase 2): add pools per region
        │
        ├── Network Pool: 10.0.0.0/24
        │   Locale: us-west-2
        │   Local to network account (not RAM-shared)
        │   allocation_min/max/default: /24
        │
        ├── Dev Pool: 10.0.1.0/24
        │   Locale: us-west-2
        │   Shared via RAM to org
        │   allocation_min/max/default: /24
        │
        └── Prod Pool: 10.0.2.0/24
            Locale: us-west-2
            Shared via RAM to org
            allocation_min/max/default: /24
```

Setting `allocation_min_netmask_length` and `allocation_max_netmask_length`
to the same value (`24`) enforces that VPCs can only request a `/24` from
these pools. This prevents a single VPC from consuming the entire pool.

**IPAM allocation enforcement tags (not used in Phase 1)**

IPAM pools support `allocation_resource_tags` — a policy that requires any
VPC allocated from a pool to carry specific tags at creation time. For example,
requiring `Environment = dev` on every VPC allocated from the dev pool ensures
that a VPC created in the wrong account or with the wrong tag is rejected.

This is one of the most useful IPAM guardrails in a multi-team environment.
It is omitted here because it adds Terraform complexity (tag enforcement is
checked by AWS at VPC creation, not at plan time, which can cause confusing
apply errors) and the learning value of the pool hierarchy is clearer without
it. Add `allocation_resource_tags` to production pool definitions once the
basic IPAM workflow is understood.

---

## Phase 2 Design Notes (Documentation Only)

### Multi-Region IPAM

Add operating regions to the IPAM instance and create per-region pools:

```
Root Pool: 10.0.0.0/8
├── us-west-2 Regional: 10.0.0.0/12
│   ├── Dev:  10.0.0.0/16
│   └── Prod: 10.1.0.0/16
└── us-east-1 Regional: 10.16.0.0/12
    ├── Dev:  10.16.0.0/16
    └── Prod: 10.17.0.0/16
```

### Traffic Segmentation with Separate Route Tables

```
TGW Route Tables:
  "dev-rt"
    - association: dev-attachment
    - propagation: dev-attachment only
    - static route: 0.0.0.0/0 → inspection-attachment

  "prod-rt"
    - association: prod-attachment
    - propagation: prod-attachment only
    - static route: 0.0.0.0/0 → inspection-attachment

  "inspection-rt"
    - association: inspection-attachment
    - propagation: dev-attachment, prod-attachment
```

This ensures dev→prod traffic flows through an inspection VPC (firewall).

### Centralized Egress

Add a dedicated egress VPC in the network account:
- NAT Gateways in public subnets
- TGW attachment in private subnets
- All workload VPCs route `0.0.0.0/0` through TGW to egress VPC
- Reduces NAT Gateway cost and centralizes egress IP management

### Inter-Region Transit Gateway

Create a TGW per region, then connect them with TGW peering:
- Peering attachments are manually accepted (no auto-accept)
- Static routes are required (BGP not supported on TGW peering)
- Each region's TGW routes the other region's CIDR through the peering attachment

---

## References

- [AWS Transit Gateway documentation](https://docs.aws.amazon.com/vpc/latest/tgw/)
- [AWS IPAM documentation](https://docs.aws.amazon.com/vpc/latest/ipam/)
- [AWS RAM documentation](https://docs.aws.amazon.com/ram/latest/userguide/)
- [Transit Gateway route tables](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-route-tables.html)
- [IPAM pool hierarchy concepts](https://docs.aws.amazon.com/vpc/latest/ipam/how-it-works-ipam.html)
- [Centralized egress patterns](https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-nat-igw.html)
- [AWS Network Firewall with TGW](https://docs.aws.amazon.com/network-firewall/latest/developerguide/arch-igw-ngw.html)
