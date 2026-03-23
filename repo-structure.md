# Repo Structure

## Directory Layout

```
AWS_transit_GW_learn/
│
├── README.md                    # Project overview, architecture summary, quick start
├── runbook.md                   # Step-by-step deployment and teardown
├── architecture.md              # Design decisions, deep dive, Phase 2 roadmap
├── security.md                  # IAM trust model, hardening guide
├── repo-structure.md            # This file
│
├── docs/
│   └── architecture-diagram.md  # Extended ASCII diagrams for reference
│
├── terraform/
│   │
│   ├── layers/                  # Foundational infrastructure (deploy first)
│   │   │
│   │   └── network/             # Network/shared-services account
│   │       ├── providers.tf     # AWS provider, assumes terraform-execute in network account
│   │       ├── backend.tf       # S3 remote state (key: network/)
│   │       ├── variables.tf     # Account IDs, org ID, CIDR ranges
│   │       ├── main.tf          # Calls ipam, transit-gateway, and workload-vpc modules
│   │       ├── outputs.tf       # Exports TGW ID, IPAM pool IDs, network VPC ID
│   │       └── terraform.tfvars.example
│   │
│   ├── environments/            # Workload environments (one per account)
│   │   │                        # Each has its own state file.
│   │   │                        # Run `terraform apply` from inside each directory.
│   │   │
│   │   ├── dev/                 # Dev workload account
│   │   │   ├── providers.tf     # AWS provider, assumes terraform-execute in dev account
│   │   │   ├── backend.tf       # S3 remote state (key: dev/)
│   │   │   ├── data.tf          # terraform_remote_state — reads network layer outputs
│   │   │   ├── variables.tf     # Dev account ID, AZs, route destinations
│   │   │   ├── main.tf          # Calls workload-vpc module
│   │   │   ├── outputs.tf       # Exports VPC ID, attachment ID
│   │   │   └── terraform.tfvars.example
│   │   │
│   │   └── prod/                # Prod workload account (mirrors dev structure)
│   │       ├── providers.tf
│   │       ├── backend.tf
│   │       ├── data.tf
│   │       ├── variables.tf
│   │       ├── main.tf
│   │       ├── outputs.tf
│   │       └── terraform.tfvars.example
│   │
│   └── modules/                 # Reusable modules (not deployed directly)
│       │
│       ├── ipam/                # AWS IPAM instance + pool hierarchy + RAM sharing
│       │   ├── main.tf          # IPAM, root/regional/network/dev/prod pools, RAM share
│       │   ├── variables.tf
│       │   └── outputs.tf       # Pool IDs and ARNs
│       │
│       ├── transit-gateway/     # TGW creation + RAM sharing
│       │   ├── main.tf          # TGW resource + RAM share to org
│       │   ├── variables.tf
│       │   └── outputs.tf       # TGW ID, ARN, default route table ID
│       │
│       └── workload-vpc/        # VPC + subnets + TGW attachment + routes
│           ├── main.tf          # VPC (IPAM), subnets, route table, TGW attachment
│           ├── variables.tf
│           └── outputs.tf       # VPC ID, subnet IDs, attachment ID
│
└── scripts/
    └── verify.sh                # Post-deployment validation checks via AWS CLI
```

---

## Layers, Environments, and Modules

**Layers** (`terraform/layers/`) are foundational infrastructure that must be
deployed before any environment. The network layer creates shared resources
(IPAM, Transit Gateway) that workload environments depend on.

**Environments** (`terraform/environments/`) are workload root modules.
They have backends, providers, and state. You run `terraform apply` from inside them.
Each environment corresponds to one AWS account and one state file.
They read network layer outputs via `terraform_remote_state` (see `data.tf`).

**Modules** (`terraform/modules/`) are reusable building blocks.
They have no backend or provider configuration. They are called by layers
and environments. They accept variables and return outputs.

This separation means:
- The `workload-vpc` module can be called with different variables for dev and prod
- Adding a new environment (e.g., staging) means creating a new environment directory
  and calling the same modules — no module code changes needed
- The layer/environment split makes the deployment dependency hierarchy explicit
- Modules are tested implicitly when environments are applied

---

## Data Flow Between Layers and Environments

The network layer's outputs are consumed by workload environments via
`terraform_remote_state`. No manual copy step is required.

```
layers/network (apply first)
  └── outputs: transit_gateway_id, network/dev/prod_ipam_pool_id, network_vpc_id
        │
        │  terraform_remote_state (reads S3 state directly)
        │
        ├──► environments/dev/data.tf
        │      (transit_gateway_id, dev_ipam_pool_id)
        │
        └──► environments/prod/data.tf
               (transit_gateway_id, prod_ipam_pool_id)

environments/dev (apply second)
  └── reads network outputs from remote state automatically

environments/prod (apply third)
  └── reads network outputs from remote state automatically
```

The `terraform_remote_state` data source uses ambient AWS credentials (the
same identity running Terraform) to read the S3 state bucket. It is not
affected by the provider's `assume_role` into the workload account.

If the network layer has not been applied yet, `terraform plan` in dev or
prod will fail with a clear error — this implicitly enforces deployment order.

Production alternative: Write outputs to SSM Parameter Store and read them
with `data "aws_ssm_parameter"` for even looser coupling.

---

## Patterns Reused from tf_take2

| Pattern | tf_take2 source | How it's used here |
|---------|-----------------|--------------------|
| `assume_role` provider | Any environment's `providers.tf` | Each environment's `providers.tf` assumes `terraform-execute` using the same pattern |
| S3 backend with native locking | Any environment's `backend.tf` | Each environment uses the same bucket with environment-specific state keys |
| `terraform-execute` role | `TF_org_user/` | Referenced by ARN; not recreated |
| Tagging convention | Project-wide | `Project`, `Environment`, `ManagedBy` tags on all resources |

---

## Patterns NOT Reused from tf_take2

| tf_take2 pattern | Reason not reused |
|------------------|-------------------|
| ECR module | No container images in this repo's scope |
| Account creation / org bootstrapping | Accounts pre-exist |
| Any application or service modules | Out of scope — this repo is networking only |

---

## Terraform Version and Provider

All environments require:

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

AWS provider `~> 5.0` provides stable IPAM resources (added in 4.x, matured in 5.x).

---

## Adding a New Environment

To add a `staging` account:

1. Copy `terraform/environments/dev/` to `terraform/environments/staging/`
2. Update `providers.tf` to assume `terraform-execute` in the staging account
3. Update `backend.tf` key to `transit-gw-learn/staging/terraform.tfstate`
4. Update `variables.tf` to use `staging_account_id` instead of `dev_account_id`
5. Update `data.tf` to read the correct IPAM pool (add a `staging_ipam_pool_id` output to the network layer)
6. Update `main.tf` to pass `environment = "staging"` to the workload-vpc module
7. Create `terraform.tfvars` with the staging account ID
8. Run `terraform init` and `terraform apply`

No module changes required. The `workload-vpc` module already supports any
environment name through its `environment` variable.
