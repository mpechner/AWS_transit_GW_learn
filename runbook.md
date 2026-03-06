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
| `ORG_ID` | AWS Organization ID (`o-xxxxxxxxxx`) | `aws organizations describe-organization` |
| `TFSTATE_BUCKET` | S3 bucket for Terraform remote state | Existing bucket from `tf_take2` or create new |
| `TFSTATE_LOCK_TABLE` | DynamoDB table for state locking | Existing table from `tf_take2` or create new |
| `AWS_REGION` | Target region | `us-west-2` (or your preferred region) |

---

## Assumptions

- You have AWS credentials that can assume `terraform-execute` in all three accounts
- The `terraform-execute` role exists in each account (created by `tf_take2/TF_org_user`)
- The S3 state bucket and DynamoDB lock table already exist
- Terraform >= 1.5.0 is installed
- AWS CLI v2 is installed and configured

---

## Phase 0: One-Time Bootstrap

These steps are run once and never need to be repeated.

### 0.1 Enable RAM Organization Sharing

Run this in the **management account**. It allows RAM shares to target
accounts using organization ARNs (required for IPAM and TGW sharing).

```bash
# Set credentials for your management account
aws ram enable-sharing-with-aws-organization
```

Expected output:
```json
{}
```

If you get an error that it's already enabled, proceed.

### 0.2 Enable IPAM Organization Integration

IPAM needs org-level integration to manage CIDR allocations across accounts.
This is handled automatically by the `aws_vpc_ipam` resource when the
`terraform-execute` role has `organizations:DescribeOrganization` permission.

No manual step required — just verify the permission exists on the role.

### 0.3 Verify Role Assumption

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

## Phase 1: Deploy Network Environment

The network environment creates IPAM and Transit Gateway, then shares them
to the organization via RAM. All subsequent environments depend on its outputs.

### 1.1 Configure Backend

Edit `terraform/environments/network/backend.tf` and replace the placeholder
values with your actual state bucket and table names.

Alternatively, use partial backend configuration (recommended — keeps bucket
name out of code):

```bash
cd terraform/environments/network

terraform init \
  -backend-config="bucket=${TFSTATE_BUCKET}" \
  -backend-config="key=transit-gw-learn/network/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${TFSTATE_LOCK_TABLE}"
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

Expected resources created (~14):
- `aws_vpc_ipam.main`
- `aws_vpc_ipam_pool.root`, `.regional`, `.dev`, `.prod`
- `aws_vpc_ipam_pool_cidr.root`, `.regional`, `.dev`, `.prod`
- `aws_ram_resource_share.ipam_pools`
- `aws_ram_resource_association.dev_pool`, `.prod_pool`
- `aws_ram_principal_association.org` (IPAM)
- `aws_ec2_transit_gateway.main`
- `aws_ram_resource_share.tgw`
- `aws_ram_resource_association.tgw`
- `aws_ram_principal_association.org` (TGW)

### 1.4 Capture Outputs

```bash
terraform output -json > /tmp/network_outputs.json
cat /tmp/network_outputs.json
```

Record these values — you will need them for dev and prod tfvars:

```
transit_gateway_id    = "tgw-xxxxxxxxxxxxxxxxx"
dev_ipam_pool_id      = "ipam-pool-xxxxxxxxxxxxxxxxx"
prod_ipam_pool_id     = "ipam-pool-xxxxxxxxxxxxxxxxx"
```

---

## Phase 2: Deploy Dev Environment

### 2.1 Configure Backend

```bash
cd terraform/environments/dev

terraform init \
  -backend-config="bucket=${TFSTATE_BUCKET}" \
  -backend-config="key=transit-gw-learn/dev/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${TFSTATE_LOCK_TABLE}"
```

### 2.2 Create tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region       = "us-west-2"
dev_account_id   = "222222222222"   # your dev account ID

# From network environment outputs
transit_gateway_id = "tgw-xxxxxxxxxxxxxxxxx"
dev_ipam_pool_id   = "ipam-pool-xxxxxxxxxxxxxxxxx"

# Route to other environments through TGW
# Use the regional supernet — covers both dev (10.0.1.x) and prod (10.0.2.x)
tgw_route_destination = "10.0.0.0/16"

availability_zones = ["us-west-2a", "us-west-2b"]

project = "aws-transit-gw-learn"
```

### 2.3 Plan and Apply

```bash
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
```

Expected resources created (~8):
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
  -backend-config="dynamodb_table=${TFSTATE_LOCK_TABLE}"
```

### 3.2 Create tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region        = "us-west-2"
prod_account_id   = "333333333333"   # your prod account ID

# From network environment outputs
transit_gateway_id = "tgw-xxxxxxxxxxxxxxxxx"
prod_ipam_pool_id  = "ipam-pool-xxxxxxxxxxxxxxxxx"

tgw_route_destination = "10.0.0.0/16"
availability_zones    = ["us-west-2a", "us-west-2b"]

project = "aws-transit-gw-learn"
```

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

Expected: Both attachments show `State = available`.

### Check 2: TGW Route Table Has Propagated Routes

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <tgw-rt-id-from-network-outputs> \
  --filters "Name=type,Values=propagated" \
  --query 'Routes[].{CIDR:DestinationCidrBlock,State:State,Type:Type}' \
  --output table \
  --region us-west-2
```

Expected: Two propagated routes — `10.0.1.0/24` (dev) and `10.0.2.0/24` (prod).

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

```bash
NETWORK_ACCOUNT_ID=111111111111 \
DEV_ACCOUNT_ID=222222222222 \
PROD_ACCOUNT_ID=333333333333 \
AWS_REGION=us-west-2 \
TGW_ID=tgw-xxxxxxxxxxxxxxxxx \
  bash scripts/verify.sh
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
cd terraform/environments/network
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
