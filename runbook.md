# Runbook

Step-by-step instructions to deploy, validate, and tear down the Transit Gateway
+ IPAM learning environment.

---

## Required Inputs

Gather these values before starting. You will substitute them throughout.

| Variable | Description | Where to find it |
|----------|-------------|------------------|
| `NETWORK_ACCOUNT_ID` | 12-digit AWS account ID for network/shared-services account | AWS console or `aws organizations list-accounts` |
| `DEV_ACCOUNT_ID` | 12-digit AWS account ID for dev workload account | Same |
| `PROD_ACCOUNT_ID` | 12-digit AWS account ID for prod workload account | Same |
| `TFSTATE_BUCKET` | S3 bucket for Terraform remote state | Existing bucket from `tf_take2` or create new |
| `AWS_REGION` | Target region | `us-west-2` (or your preferred region) |

> **Note**: The AWS Organization ID is not required as an input — the IPAM and
> Transit Gateway modules fetch it dynamically via
> `data "aws_organizations_organization"`. S3 state locking uses native
> `use_lockfile = true` — no DynamoDB table needed.

---

## Assumptions

- You have AWS credentials that can assume `terraform-execute` in all three accounts
- The `terraform-execute` role exists in each account (created by `tf_take2/TF_org_user`)
- The S3 state bucket already exists (locking uses S3 native `use_lockfile`; no DynamoDB table needed)
- Terraform >= 1.5.0 is installed
- AWS CLI v2 is installed and configured

---

## Phase 0: One-Time Bootstrap

These steps are run once and never need to be repeated.

### 0.1 Enable RAM Organization Sharing

Run this in the **management account** (not a member account). It allows RAM
shares to target accounts using organization ARNs (required for IPAM and TGW
sharing). This creates the RAM service-linked role in the management account
and registers `ram.amazonaws.com` as a trusted service with Organizations.

```bash
# Set credentials for your management account
aws ram enable-sharing-with-aws-organization
```

Expected output: `{ "returnValue": true }` or `{}`

**Troubleshooting**: If RAM sharing was enabled previously but RAM operations
still fail with "Organization could not be found" or "resource can only be
shared within your AWS Organization," the integration may be stale. Reset it:

```bash
aws organizations disable-aws-service-access --service-principal ram.amazonaws.com
sleep 10
aws organizations enable-aws-service-access --service-principal ram.amazonaws.com
sleep 5
aws ram enable-sharing-with-aws-organization
```

Wait 60 seconds after re-enabling before retrying. This forces RAM to refresh
its view of the organization — the original enablement can become stale if
the organization structure or SCPs changed after it was first configured.

### 0.2 Verify RAM Service-Linked Role in the Network Account

The RAM service-linked role (`AWSServiceRoleForResourceAccessManager`) must
also exist in the **network account** — not just the management account.
Without it, RAM in the network account cannot validate organization principals
and you will get errors like "Organization could not be found" or
"resource can only be shared within your AWS Organization."

The SLR is normally auto-created when RAM first needs it, but an overly
restrictive region-denial SCP can block the auto-creation (since IAM is a
global service). If the SLR is missing, create it manually:

```bash
# Assume into the network account
export CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${NETWORK_ACCOUNT_ID}:role/terraform-execute \
  --role-session-name check-slr --output json)
export AWS_ACCESS_KEY_ID=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")

# Check if SLR exists
aws iam get-role --role-name AWSServiceRoleForResourceAccessManager

# If NoSuchEntity, create it:
aws iam create-service-linked-role --aws-service-name ram.amazonaws.com

# Clean up
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### 0.3 Verify Region-Restriction SCP Excludes Global Services

If your organization uses a region-restriction SCP, it must exclude global
services from the Deny. A common mistake is using `Action: "*"` with
`StringNotEqualsIfExists` on `aws:RequestedRegion` — the `IfExists` modifier
causes the Deny to apply to any API call that does not carry
`aws:RequestedRegion`, which blocks global services like RAM's organization
operations, IAM, and STS.

The correct pattern uses `NotAction` to exempt global services and
`StringNotEquals` (without `IfExists`):

```json
{
  "Effect": "Deny",
  "NotAction": [
    "iam:*", "sts:*", "organizations:*", "ram:*",
    "cloudfront:*", "route53:*", "route53domains:*",
    "shield:*", "waf:*", "wafv2:*", "budgets:*",
    "ce:*", "health:*", "support:*", "trustedadvisor:*"
  ],
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "aws:RequestedRegion": ["us-west-2", "us-west-1", "us-east-1"]
    }
  }
}
```

Without this fix, `terraform apply` for the network layer will fail on all
RAM organization sharing operations even though the role has full permissions.

### 0.4 Enable IPAM Organization Integration

IPAM needs org-level integration to manage CIDR allocations across accounts.
Without this, member accounts cannot allocate CIDRs from shared IPAM pools
and VPC creation will fail with:

```
UnsupportedOperation: The operation AllocateIpamPoolCidr is not supported.
Account XXXXXXXXXXXX is not monitored by IPAM ipam-XXXXXXXXXXXXXXXXX.
```

Run these commands from the **management account** (not a member account):

```bash
# 1. Enable IPAM as a trusted service with AWS Organizations
aws organizations enable-aws-service-access \
  --service-principal ipam.amazonaws.com

# 2. Delegate the network account as the IPAM administrator
aws ec2 enable-ipam-organization-admin-account \
  --delegated-admin-account-id ${NETWORK_ACCOUNT_ID} \
  --region ${AWS_REGION}
```

Expected output: `{ "Success": true }`

This registers the network account as the delegated IPAM admin, which allows
the IPAM instance to monitor all accounts in the organization and fulfill
allocation requests from them. Wait ~60 seconds for propagation before
deploying workload environments.

**Verification** (from the management account):

```bash
aws organizations list-delegated-administrators \
  --service-principal ipam.amazonaws.com \
  --query 'DelegatedAdministrators[].Id' \
  --output text
```

Expected: the network account ID.

### 0.5 Verify Role Assumption

Test that your credentials can assume `terraform-execute` in each account:

```bash
# Test network account
aws sts assume-role \
  --role-arn arn:aws:iam::${NETWORK_ACCOUNT_ID}:role/terraform-execute \
  --role-session-name test

# Test dev account
aws sts assume-role \
  --role-arn arn:aws:iam::${DEV_ACCOUNT_ID}:role/terraform-execute \
  --role-session-name test

# Test prod account
aws sts assume-role \
  --role-arn arn:aws:iam::${PROD_ACCOUNT_ID}:role/terraform-execute \
  --role-session-name test
```

Each should return a JSON object with `Credentials`. If any fail, check the
trust policy on the `terraform-execute` role in that account.

---

## Phase 1: Deploy Network Layer

The network layer creates IPAM and Transit Gateway, then shares them
to the organization via RAM. All subsequent environments depend on its outputs
(read via `terraform_remote_state`).

### 1.1 Configure Backend

Edit `terraform/layers/network/backend.tf` and replace the placeholder
values with your actual state bucket and table names.

Alternatively, use partial backend configuration (recommended — keeps bucket
name out of code):

```bash
cd terraform/layers/network

terraform init \
  -backend-config="bucket=${TFSTATE_BUCKET}" \
  -backend-config="key=transit-gw-learn/network/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="use_lockfile=true"
```

### 1.2 Create tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:

```hcl
aws_region         = "us-west-2"
network_account_id = "111111111111"   # your network account ID

# CIDR hierarchy (defaults are fine for learning)
root_cidr     = "10.0.0.0/8"
regional_cidr = "10.0.0.0/16"
network_cidr  = "10.0.0.0/24"
dev_cidr      = "10.0.1.0/24"
prod_cidr     = "10.0.2.0/24"

project = "aws-transit-gw-learn"
```

> **Security**: `terraform.tfvars` is in `.gitignore`. Do not commit it.
> Commit only `terraform.tfvars.example`.

### 1.3 Plan and Apply

```bash
terraform plan -out=network.tfplan
terraform apply network.tfplan
```

Expected resources created (~22):
- `aws_vpc_ipam.main`
- `aws_vpc_ipam_pool.root`, `.regional`, `.network`, `.dev`, `.prod`
- `aws_vpc_ipam_pool_cidr.root`, `.regional`, `.network`, `.dev`, `.prod`
- `aws_ram_resource_share.ipam_pools`
- `aws_ram_resource_association.dev_pool`, `.prod_pool`
- `aws_ram_principal_association.org` (IPAM)
- `aws_ec2_transit_gateway.main`
- `aws_ram_resource_share.tgw`
- `aws_ram_resource_association.tgw`
- `aws_ram_principal_association.org` (TGW)
- Network VPC: `aws_vpc.main`, 2x `aws_subnet.private`, `aws_route_table.private`,
  2x `aws_route_table_association.private`, `aws_ec2_transit_gateway_vpc_attachment.main`,
  `aws_route.to_tgw`

### 1.4 Verify Outputs

```bash
terraform output -json | python3 -m json.tool
```

Dev and prod environments read these outputs automatically via
`terraform_remote_state` — no manual copy needed. Verify the outputs
look correct before proceeding.

### 1.5 Verify in the AWS Console

Log into the **network account** in the AWS Console (us-west-2 region) and
check the following dashboards to confirm everything was created correctly.

**VPC > IP Address Manager (IPAM)**
- Navigate to: VPC Console → IP Address Manager → Pools
- You should see the pool hierarchy:
  - Root pool: `10.0.0.0/8`
  - Regional pool: `10.0.0.0/16` (locale: us-west-2)
  - Network pool: `10.0.0.0/24` — with one allocation (network VPC)
  - Dev pool: `10.0.1.0/24`
  - Prod pool: `10.0.2.0/24`
- The network pool should show one allocation; dev/prod allocations appear after those VPCs are created

**VPC > Transit Gateways**
- Navigate to: VPC Console → Transit Gateways
- Verify the TGW shows state: `available`
- Check: Transit Gateway Attachments — the network VPC attachment should be present
  with state `available`
- Check: Transit Gateway Route Tables — the default route table should have one
  propagated route: `10.0.0.0/24 → network-attachment` (dev/prod routes appear
  after those environments are deployed)

**VPC > Your VPCs**
- Navigate to: VPC Console → Your VPCs
- You should see the network VPC (`aws-transit-gw-learn-network-vpc`) with CIDR `10.0.0.0/24`
- Check Subnets: two private subnets (`10.0.0.0/26` in AZ-a, `10.0.0.64/26` in AZ-b)
- Check Route Tables: private route table with a route `10.0.0.0/16 → tgw-xxx`

**RAM (Resource Access Manager)**
- Navigate to: RAM Console → Resource shares → Shared by me
- You should see two resource shares:
  - `aws-transit-gw-learn-ipam-pool-share` — shared resources: dev pool, prod pool
  - `aws-transit-gw-learn-tgw-share` — shared resource: Transit Gateway
- Each share should show the organization as the principal
- Status should be `ASSOCIATED` for both resources and principals

**Verify from a workload account** (optional)
- Log into the dev or prod account
- Navigate to: RAM Console → Resource shares → Shared with me
- Both shares should appear, confirming RAM propagation is complete
- Navigate to: VPC Console → Transit Gateways → you should see the shared TGW
- Navigate to: VPC Console → IP Address Manager → Pools → you should see
  the shared IPAM pools available for allocation

> **Tip**: RAM share propagation to member accounts takes ~60 seconds.
> If the shares don't appear in a workload account, wait and refresh.

---

## Phase 2: Deploy Dev Environment

### 2.1 Configure Backend

```bash
cd terraform/environments/dev

terraform init \
  -backend-config="bucket=${TFSTATE_BUCKET}" \
  -backend-config="key=transit-gw-learn/dev/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="use_lockfile=true"
```

### 2.2 Create tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region         = "us-west-2"
dev_account_id     = "222222222222"   # your dev account ID
project            = "aws-transit-gw-learn"
availability_zones = ["us-west-2a", "us-west-2b"]
```

> **Note**: `transit_gateway_id`, `dev_ipam_pool_id`, and `tgw_route_destination`
> are read automatically from the network layer's remote state (see `data.tf`).
> No manual copy needed.

### 2.3 Plan and Apply

```bash
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
```

Expected resources created (~9):
- `aws_ebs_encryption_by_default.enabled`
- `aws_vpc.main`
- `aws_subnet.private[0]`, `[1]`
- `aws_route_table.private`
- `aws_route_table_association.private[0]`, `[1]`
- `aws_ec2_transit_gateway_vpc_attachment.main`
- `aws_route.to_tgw`

### 2.4 Capture Outputs

```bash
terraform output -json
```

Record `vpc_id` and `tgw_attachment_id` for validation.

---

## Phase 3: Deploy Prod Environment

### 3.1 Configure Backend

```bash
cd terraform/environments/prod

terraform init \
  -backend-config="bucket=${TFSTATE_BUCKET}" \
  -backend-config="key=transit-gw-learn/prod/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="use_lockfile=true"
```

### 3.2 Create tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region         = "us-west-2"
prod_account_id    = "333333333333"   # your prod account ID
project            = "aws-transit-gw-learn"
availability_zones = ["us-west-2a", "us-west-2b"]
```

> **Note**: `transit_gateway_id`, `prod_ipam_pool_id`, and `tgw_route_destination`
> are read automatically from the network layer's remote state (see `data.tf`).
> No manual copy needed.

### 3.3 Plan and Apply

```bash
terraform plan -out=prod.tfplan
terraform apply prod.tfplan
```

---

## Validation

After all three environments are deployed, run through this checklist.

### Check 1: TGW Attachments Are Available

Run with network account credentials:

```bash
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=transit-gateway-id,Values=tgw-xxxxxxxxxxxxxxxxx" \
  --query 'TransitGatewayAttachments[].{
    State:State,
    Type:ResourceType,
    ResourceId:ResourceId,
    CreatedBy:CreatedBy
  }' \
  --output table \
  --region us-west-2
```

Expected: All three attachments (network, dev, prod) show `State = available`.

### Check 2: TGW Route Table Has Propagated Routes

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <tgw-rt-id-from-network-outputs> \
  --filters "Name=type,Values=propagated" \
  --query 'Routes[].{CIDR:DestinationCidrBlock,State:State,Type:Type}' \
  --output table \
  --region us-west-2
```

Expected: Three propagated routes — `10.0.0.0/24` (network), `10.0.1.0/24` (dev), and `10.0.2.0/24` (prod).

### Check 3: IPAM Allocations

```bash
# Check dev pool allocations
aws ec2 get-ipam-pool-allocations \
  --ipam-pool-id ipam-pool-xxxxxxxxxxxxxxxxx \
  --region us-west-2 \
  --query 'IpamPoolAllocations[].{CIDR:Cidr,Resource:ResourceId,Type:ResourceType}'

# Check prod pool allocations
aws ec2 get-ipam-pool-allocations \
  --ipam-pool-id ipam-pool-xxxxxxxxxxxxxxxxx \
  --region us-west-2
```

Expected: Each pool shows one allocation (the VPC CIDR).

### Check 4: VPC Route Tables

With dev account credentials:

```bash
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<dev-vpc-id>" \
  --query 'RouteTables[].Routes[].{Dest:DestinationCidrBlock,Target:TransitGatewayId,State:State}' \
  --output table
```

Expected: A route for `10.0.0.0/16` with target `tgw-xxxxxxxxxxxxxxxxx`.

### Check 5: AWS Reachability Analyzer (Optional)

Create a Reachability Analyzer path from a dev subnet ENI to a prod subnet ENI.
This validates the logical connectivity without needing actual EC2 instances.

```bash
# Create analysis path
aws ec2 create-network-insights-path \
  --source <dev-subnet-eni-id> \
  --destination <prod-subnet-eni-id> \
  --protocol TCP \
  --region us-west-2

# Run analysis
aws ec2 start-network-insights-analysis \
  --network-insights-path-id nip-xxxxxxxxxxxxxxxxx

# Check result (wait ~60 seconds)
aws ec2 describe-network-insights-analyses \
  --network-insights-analysis-ids nia-xxxxxxxxxxxxxxxxx \
  --query 'NetworkInsightsAnalyses[].{Status:Status,Reachable:NetworkPathFound}'
```

### Run the Verification Script

The script auto-detects all values from Terraform state — no environment
variables needed if you've run `terraform apply` in all three directories:

```bash
bash scripts/verify.sh
```

To override any auto-detected value, set it as an environment variable:

```bash
AWS_REGION=us-east-1 bash scripts/verify.sh
```

---

## Teardown

Destroy in reverse dependency order. If you destroy network first, the
IPAM and TGW will fail to destroy because VPC allocations and attachments
still exist.

### Step 1: Destroy Prod

```bash
cd terraform/environments/prod
terraform destroy
```

Type `yes` to confirm. This releases the prod IPAM allocation and deletes
the TGW attachment. The TGW attachment deletion takes ~2 minutes.

### Step 2: Destroy Dev

```bash
cd terraform/environments/dev
terraform destroy
```

### Step 3: Destroy Network

```bash
cd terraform/layers/network
terraform destroy
```

This deletes the IPAM (and all pools), the TGW, and the RAM shares.

### Common Teardown Errors

**Error: `DependencyViolation` on TGW delete**
- Cause: A TGW attachment still exists (check both dev and prod accounts)
- Fix: Delete the attachment manually or run `terraform destroy` in the workload
  environment first

**Error: IPAM pool still has allocations**
- Cause: A VPC still holds an allocation from the pool
- Fix: Delete the VPC (or run workload environment `terraform destroy` first)

**Error: RAM share can't be deleted**
- Cause: Resources are still associated
- Fix: Disassociate resources from the share first, then delete the share
