# Controlling Prompt

This document records the original prompt used to initialize this repository.
It serves as the design brief and intent record for this project.

---

You are a senior AWS / Terraform / DevSecOps engineer.

I am creating and building in this NEW GitHub repository:

- SSH: git@github.com:mpechner/AWS_transit_GW_learn.git
- HTTPS: https://github.com/mpechner/AWS_transit_GW_learn

This project is primarily a learning-focused, portfolio-quality proof of concept for AWS Transit Gateway and IPAM in a secure multi-account environment.

It should be a good example repo for learning, experimentation, and demonstrating architecture judgment. It should be deployable, understandable, and safe by default. It should also clearly document what is simplified for learning purposes versus what would need further hardening in production.

I also have an existing repo that may contain patterns and code worth reusing or adapting:

- https://github.com/mpechner/tf_take2

Use tf_take2 as a reference repo only. Reuse or adapt patterns from it where appropriate, but do not force reuse if the design would be cleaner in this new repo.

## Existing Environment / Assumptions

- I already have an AWS Organization.
- I already have a cross-account execution role named `terraform-execute`, created by the `TF_org_user` directory in `tf_take2`.
- This new project should assume Terraform will use that role in each account.
- If container images are needed, reuse patterns from the `ecr` directory in `tf_take2`, but ensure the repository design is secure and cross-account friendly, including IAM and KMS.
- I am willing to use Terraform, Python, and Ansible, but Terraform should be the primary implementation tool unless there is a strong reason otherwise.

## Target Account Model

Use these three AWS accounts:

- **network/shared-services account**: owns IPAM and Transit Gateway
- **dev workload account**
- **prod workload account**

## Primary Goal

Create a portfolio-quality learning repo that demonstrates secure AWS multi-account networking using:

- AWS IPAM for CIDR management
- AWS Transit Gateway for multi-account connectivity
- secure cross-account role assumption using existing `terraform-execute` roles
- clear, structured documentation
- deployable, understandable, and safe-by-default examples

This should be both:
- a learning model
- a good proof-of-concept example for Transit Gateway

Success for this repo is not maximum feature count. Success is a clean example that teaches the design, deploys reliably, and documents the reasoning behind the choices.

## Core Principles

Follow AWS best practices as much as practical for a learning repo, including:

- least-privilege IAM
- no overly broad principals
- KMS key policies that support cross-account access without wildcards
- provider aliasing per account
- remote state isolation
- tagging standards
- flow logs / CloudTrail guidance
- no hardcoded account IDs outside tfvars, examples, or clearly documented config
- secure Transit Gateway attachment acceptance model
- separation of shared network services from workload accounts

Also:
- document what is simplified for the learning repo
- document what would be further hardened in a production implementation
- prefer a simple, well-explained Phase 1 over an overly abstract reusable framework
- where AWS offers multiple valid design choices, explain which one you chose and why

## Scope

### Phase 1 (required)
Build a single-region working example that includes:

- IPAM in the network/shared-services account
- dev VPC allocated from IPAM
- prod VPC allocated from IPAM
- Transit Gateway in the network/shared-services account
- TGW attachments for dev and prod VPCs
- route tables and associations documented clearly
- secure cross-account Terraform provider configuration
- outputs and verification steps so I can confirm the design works

### Phase 2 (design/documentation only, unless simple)
Document how the design could later expand to:

- multi-region IPAM pools
- inter-region Transit Gateway considerations
- route segmentation
- inspection VPC patterns
- centralized egress patterns

Do not overbuild Phase 1 just to support every future feature.

## Documentation Artifacts Required

Generate these as file-ready documents:

1. **README.md** — project purpose, account model, high-level architecture, deployment order, prerequisites, verification steps, cleanup steps
2. **runbook.md** — top-level step-by-step instructions to bring the environment up, required inputs, assumptions, Terraform workflow, validation / testing steps, teardown steps
3. **architecture.md** — what was built, design decisions, why IPAM was used, why Transit Gateway was used, tradeoffs vs VPC peering, trust boundaries, references for deeper AWS documentation study
4. **security.md** — IAM trust model, cross-account security considerations, KMS policy approach, logging guidance, accepted simplifications and production hardening recommendations
5. **repo-structure.md** — explain the directory layout, explain modules vs environments, explain where reused patterns from `tf_take2` were applied
6. **at least one text-based architecture diagram** — markdown friendly, clear enough to understand account boundaries and routing

## Technical Output Required

Provide concrete, file-ready content for:

- proposed repo directory structure
- Terraform module structure
- environment structure for network/dev/prod
- provider aliasing pattern
- IPAM pool design
- TGW design
- route table strategy
- example tfvars guidance
- implementation phases
- verification steps
- risks, assumptions, and gaps

## Constraints

- optimize for clarity and correctness, not maximum feature count
- do not add Kubernetes or unrelated services
- keep the scope focused on IPAM, TGW, and secure cross-account patterns
- do not produce vague architecture-only output; provide concrete file-ready content
- clearly mark what is MVP vs optional enhancement
- clearly identify which patterns from `tf_take2` should be reused, adapted, or avoided

## Important

This repo should be:
- deployable
- understandable
- secure by default
- useful as a learning example
- strong enough to reference in public documentation or interviews

If a design choice seems too complex for a learning repo, recommend a simpler approach and explain why.

Before generating code, first propose:
1. the repo directory structure
2. the implementation phases
3. what should be reused from `tf_take2`
4. what should not be reused from `tf_take2`
5. the minimum viable Phase 1 design

Then generate the file-ready content.

# Ancillary prompts
As a senior achitect, review and provide feedback

you are a devsecops person, perform a review.  Keep in mond this code is a short lived tutorial.  But feel free to document what would be needed to
  adapt this to production read code.