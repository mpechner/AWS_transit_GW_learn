# AWS Transit Gateway + IPAM — Multi-Account Learning Lab

A learning-focused, portfolio-quality proof of concept demonstrating secure
multi-account AWS networking using:

- **AWS IPAM** — centralized IP address management, prevents CIDR conflicts
- **AWS Transit Gateway** — hub-and-spoke connectivity replacing VPC peering mesh
- **Cross-account Terraform** — provider `assume_role` with least-privilege IAM
- **AWS RAM** — sharing network resources across accounts in an organization

> **Learning Repo Notice**: This repo is intentionally simplified for clarity
> and deployability. See [security.md](security.md) for a clear list of what
> would require additional hardening in a production environment.

---

## Account Model

| Role | Purpose |
|------|---------|
| **Network / Shared-Services** | Owns IPAM and Transit Gateway. Deploys a VPC from the IPAM network pool. Shares IPAM pools and TGW to workload accounts via RAM. |
| **Dev Workload** | Deploys a VPC with CIDR allocated from the IPAM dev pool. Attaches to TGW. |
| **Prod Workload** | Deploys a VPC with CIDR allocated from the IPAM prod pool. Attaches to TGW. |

---

## Architecture

```
┌──────────────────────────────── AWS Organization ──────────────────────────────┐
│                                                                                 │
│  ┌──────────────── Network / Shared-Services Account ─────────────────┐        │
│  │                                                                     │        │
│  │   ┌──────────────────────────┐    ┌──────────────────────────┐     │        │
│  │   │          IPAM            │    │     Transit Gateway      │     │        │
│  │   │  Root:     10.0.0.0/8   │    │   (org-shared via RAM)   │     │        │
│  │   │  Regional: 10.0.0.0/16  │    │   Default Route Table    │     │        │
│  │   │  ├ Net:  10.0.0.0/24    │    │   net  routes propagate  │     │        │
│  │   │  ├ Dev:  10.0.1.0/24    │    │   dev  routes propagate  │     │        │
│  │   │  └ Prod: 10.0.2.0/24    │    │   prod routes propagate  │     │        │
│  │   └─────────────┬────────────┘    └────────────┬─────────────┘     │        │
│  │                 │  RAM Share                   │  RAM Share         │        │
│  │   Network VPC: 10.0.0.0/24   TGW Attachment (local)               │        │
│  └─────────────────┼──────────────────────────────┼───────────────────┘        │
│                    │                              │                             │
│       ┌────────────┴────────┐         ┌───────────┴────────┐                   │
│       ▼                     │         │                    ▼                   │
│  ┌────────────────────┐     │         │     ┌────────────────────┐             │
│  │    Dev Account     │     │         │     │   Prod Account     │             │
│  │  VPC 10.0.1.0/24   │     │         │     │  VPC 10.0.2.0/24   │             │
│  │  (IPAM-allocated)  │     │         │     │  (IPAM-allocated)  │             │
│  │                    │     │         │     │                    │             │
│  │  Private /26 AZ-a  │     │         │     │  Private /26 AZ-a  │             │
│  │  Private /26 AZ-b  │     │         │     │  Private /26 AZ-b  │             │
│  │        │           │     │         │     │        │           │             │
│  │  TGW Attachment ───┼─────┴─────────┴─────┼── TGW Attachment   │             │
│  └────────────────────┘                     └────────────────────┘             │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Deployment Order

Apply in dependency order. The network layer must be deployed first; workload
environments read its outputs via `terraform_remote_state` automatically.

| Step | Directory | What it creates |
|------|-----------|-----------------|
| 1 | Bootstrap | Verify prerequisites; enable RAM org sharing |
| 2 | `layers/network` | IPAM, TGW, RAM shares, network VPC + TGW attachment |
| 3 | `environments/dev` | Dev VPC (IPAM-allocated), TGW attachment |
| 4 | `environments/prod` | Prod VPC (IPAM-allocated), TGW attachment |

See [runbook.md](runbook.md) for complete step-by-step commands.

---

## Prerequisites

- AWS Organization with three accounts (network, dev, prod)
- `terraform-execute` IAM role in each account (from `tf_take2/TF_org_user`)
- S3 bucket for Terraform remote state (reuse from `tf_take2`; locking uses S3 native `use_lockfile`)
- RAM organization sharing enabled (one-time setup in management account)
- IPAM delegated admin enabled for the network account (one-time setup in management account)
- Terraform >= 1.5.0 and AWS CLI v2
- Credentials with permission to assume `terraform-execute` in all three accounts

---

## Verification

After all environments are deployed:

```bash
# Check TGW attachment states (network account credentials)
aws ec2 describe-transit-gateway-attachments \
  --query 'TransitGatewayAttachments[].{State:State,Resource:ResourceId,Account:CreatedBy}' \
  --output table

# Check IPAM allocations for dev pool
aws ec2 get-ipam-pool-allocations \
  --ipam-pool-id <dev-pool-id-from-network-outputs>

# Run the included verification script (auto-detects from Terraform state)
bash scripts/verify.sh
```

See [runbook.md](runbook.md#validation) for the complete validation checklist.

---

## Cleanup

Destroy in reverse order to avoid dependency errors. Dev and prod can run
in parallel (separate state locks); just wait for both before destroying network:

```bash
# Terminal 1                              # Terminal 2
cd terraform/environments/dev             cd terraform/environments/prod
terraform destroy                         terraform destroy

# After both complete:
cd terraform/layers/network && terraform destroy
```

> **Warning**: IPAM-allocated VPCs take 10-20 minutes to delete while AWS
> deallocates the CIDR back to the pool. This is normal -- don't cancel.
> See [runbook.md](runbook.md#teardown) for details.

---

## Documentation

| Document | Purpose |
|----------|---------|
| [architecture.md](architecture.md) | Design decisions, IPAM/TGW deep dive, Phase 2 roadmap |
| [security.md](security.md) | IAM trust model, cross-account security, hardening guide |
| [runbook.md](runbook.md) | Step-by-step deployment, validation, and teardown |
| [repo-structure.md](repo-structure.md) | Directory layout, module design, tf_take2 patterns |
| [sample-output.md](sample-output.md) | Full `verify.sh` output from a successful deployment |
| [docs/architecture-diagram.md](docs/architecture-diagram.md) | Extended architecture diagrams |

---

## Learning Goals

Working through this repo teaches:

- How IPAM prevents CIDR overlaps across accounts and makes IP planning auditable
- How Transit Gateway replaces an O(n²) VPC peering mesh with O(n) attachments
- How to use Terraform `assume_role` providers for secure cross-account deployments
- How RAM shares resources within an AWS Organization without account-level IAM grants
- Why route table propagation works and when you would segment it (Phase 2)
- The deployment ordering discipline required when Terraform state is split by account

---

## Further Reading

AWS documentation for the services used in this repo:

| Topic | Link |
|-------|------|
| What is IPAM | https://docs.aws.amazon.com/vpc/latest/ipam/what-it-is-ipam.html |
| IPAM pool hierarchy | https://docs.aws.amazon.com/vpc/latest/ipam/how-it-works-ipam.html |
| Share IPAM pools via RAM | https://docs.aws.amazon.com/vpc/latest/ipam/share-pool-ipam.html |
| Enable IPAM delegated admin | https://docs.aws.amazon.com/vpc/latest/ipam/enable-integ-ipam.html |
| How Transit Gateway works | https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html |
| TGW VPC attachments | https://docs.aws.amazon.com/vpc/latest/tgw/tgw-vpc-attachments.html |
| TGW route table propagation | https://docs.aws.amazon.com/vpc/latest/tgw/tgw-route-tables.html |
| What is AWS RAM | https://docs.aws.amazon.com/ram/latest/userguide/what-is.html |
| Enable RAM org sharing | https://docs.aws.amazon.com/ram/latest/userguide/getting-started-sharing.html#getting-started-sharing-orgs |
| Terraform assume_role provider | https://registry.terraform.io/providers/hashicorp/aws/latest/docs#assuming-an-iam-role |
| Terraform remote_state data source | https://developer.hashicorp.com/terraform/language/state/remote-state-data |

Start with "How Transit Gateway works" and "What is IPAM" -- those two cover most of what this repo does.
