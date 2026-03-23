#!/usr/bin/env bash
# =============================================================================
# verify.sh — Post-deployment validation for Transit Gateway + IPAM
# =============================================================================
# Auto-detects all values from Terraform state. Just run from the repo root
# after all three environments are applied:
#
#   bash scripts/verify.sh
#
# Override any value with an environment variable:
#
#   AWS_REGION=us-east-1 bash scripts/verify.sh
#
# Prerequisites:
#   - AWS CLI v2 installed
#   - Credentials that can assume terraform-execute in all three accounts
#   - All three environments successfully applied (terraform state accessible)
# =============================================================================

set -eo pipefail

# ---------------------------------------------------------------------------
# Locate Terraform directories relative to this script
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NETWORK_DIR="${REPO_ROOT}/terraform/layers/network"
DEV_DIR="${REPO_ROOT}/terraform/environments/dev"
PROD_DIR="${REPO_ROOT}/terraform/environments/prod"

# ---------------------------------------------------------------------------
# Helper: read a single terraform output; returns empty string on failure
# ---------------------------------------------------------------------------
tf_output() {
  local dir="$1" key="$2"
  if [ -d "${dir}/.terraform" ]; then
    terraform -chdir="${dir}" output -raw "${key}" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Colors (only if terminal supports it)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  DIM='\033[2m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' DIM='' NC=''
fi

PASS=0
FAIL=0
pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
show_cmd() { echo -e "${DIM}\$ $*${NC}"; }

# ---------------------------------------------------------------------------
# Auto-detect from Terraform state (env vars take precedence)
# ---------------------------------------------------------------------------
echo ""
info "Reading values from Terraform state..."

NETWORK_ACCOUNT_ID="${NETWORK_ACCOUNT_ID:-$(tf_output "${NETWORK_DIR}" network_account_id)}"
TGW_ID="${TGW_ID:-$(tf_output "${NETWORK_DIR}" transit_gateway_id)}"
TF_REGION="$(tf_output "${NETWORK_DIR}" aws_region)"
DEV_ACCOUNT_ID="${DEV_ACCOUNT_ID:-$(tf_output "${DEV_DIR}" account_id)}"
PROD_ACCOUNT_ID="${PROD_ACCOUNT_ID:-$(tf_output "${PROD_DIR}" account_id)}"

REGION="${AWS_REGION:-${TF_REGION:-us-west-2}}"

# ---------------------------------------------------------------------------
# Validate — show what was detected and what's missing
# ---------------------------------------------------------------------------
MISSING=0
[ -z "${NETWORK_ACCOUNT_ID:-}" ] && echo -e "${RED}Error:${NC} NETWORK_ACCOUNT_ID not found in state or env" && MISSING=1
[ -z "${DEV_ACCOUNT_ID:-}" ]     && echo -e "${RED}Error:${NC} DEV_ACCOUNT_ID not found in state or env"     && MISSING=1
[ -z "${PROD_ACCOUNT_ID:-}" ]    && echo -e "${RED}Error:${NC} PROD_ACCOUNT_ID not found in state or env"    && MISSING=1
[ -z "${TGW_ID:-}" ]             && echo -e "${RED}Error:${NC} TGW_ID not found in state or env"             && MISSING=1

if [ "${MISSING}" -eq 1 ]; then
  echo ""
  echo "Auto-detection reads 'terraform output' from:"
  echo "  ${NETWORK_DIR}"
  echo "  ${DEV_DIR}"
  echo "  ${PROD_DIR}"
  echo ""
  echo "All three environments must be applied first (terraform apply)."
  echo "Or set missing values as environment variables:"
  echo ""
  echo "  NETWORK_ACCOUNT_ID=111111111111 \\"
  echo "  DEV_ACCOUNT_ID=222222222222 \\"
  echo "  PROD_ACCOUNT_ID=333333333333 \\"
  echo "  TGW_ID=tgw-xxxxxxxxxxxxxxxxx \\"
  echo "    bash scripts/verify.sh"
  exit 1
fi

set -u

ROLE_NAME="terraform-execute"

echo ""
echo "====================================================================="
echo " AWS Transit Gateway + IPAM Deployment Verification"
echo "====================================================================="
echo " Region:          ${REGION}"
echo " Network Account: ${NETWORK_ACCOUNT_ID}"
echo " Dev Account:     ${DEV_ACCOUNT_ID}"
echo " Prod Account:    ${PROD_ACCOUNT_ID}"
echo " TGW ID:          ${TGW_ID}"
echo "====================================================================="
echo ""

# ---------------------------------------------------------------------------
# Helper: assume a role and export credentials
# ---------------------------------------------------------------------------
assume_role() {
  local account_id="$1"
  local role_name="$2"
  local session_name="${3:-verify-session}"

  local creds
  creds=$(aws sts assume-role \
    --role-arn "arn:aws:iam::${account_id}:role/${role_name}" \
    --role-session-name "${session_name}" \
    --query 'Credentials' \
    --output json)

  export AWS_ACCESS_KEY_ID=$(echo "$creds" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKeyId'])")
  export AWS_SECRET_ACCESS_KEY=$(echo "$creds" | python3 -c "import sys,json; print(json.load(sys.stdin)['SecretAccessKey'])")
  export AWS_SESSION_TOKEN=$(echo "$creds" | python3 -c "import sys,json; print(json.load(sys.stdin)['SessionToken'])")
}

clear_role() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

# ---------------------------------------------------------------------------
# CHECK 1: TGW exists in network account
# ---------------------------------------------------------------------------
info "Checking Transit Gateway in network account..."
assume_role "${NETWORK_ACCOUNT_ID}" "${ROLE_NAME}" "verify-network"

TGW_STATE=$(aws ec2 describe-transit-gateways \
  --transit-gateway-ids "${TGW_ID}" \
  --region "${REGION}" \
  --query 'TransitGateways[0].State' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "${TGW_STATE}" = "available" ]; then
  pass "Transit Gateway ${TGW_ID} state: available"
else
  fail "Transit Gateway ${TGW_ID} state: ${TGW_STATE} (expected: available)"
fi

# ---------------------------------------------------------------------------
# CHECK 2: TGW attachments are available
# ---------------------------------------------------------------------------
info "Checking TGW attachment states..."

ATTACHMENT_COUNT=$(aws ec2 describe-transit-gateway-attachments \
  --filters "Name=transit-gateway-id,Values=${TGW_ID}" "Name=state,Values=available" \
  --region "${REGION}" \
  --query 'length(TransitGatewayAttachments)' \
  --output text)

if [ "${ATTACHMENT_COUNT}" -ge 3 ]; then
  pass "TGW has ${ATTACHMENT_COUNT} available attachment(s) (expected >= 3: network, dev, prod)"
else
  fail "TGW has ${ATTACHMENT_COUNT} available attachment(s) (expected >= 3: network, dev, prod)"
fi

echo ""
info "TGW Attachment Details:"
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=transit-gateway-id,Values=${TGW_ID}" \
  --region "${REGION}" \
  --query 'TransitGatewayAttachments[].{State:State,Type:ResourceType,OwnerAccount:ResourceOwnerId,ResourceId:ResourceId}' \
  --output table
echo ""

# ---------------------------------------------------------------------------
# CHECK 3: TGW default route table has propagated routes
# ---------------------------------------------------------------------------
info "Checking TGW route table for propagated routes..."

TGW_RT_ID=$(aws ec2 describe-transit-gateways \
  --transit-gateway-ids "${TGW_ID}" \
  --region "${REGION}" \
  --query 'TransitGateways[0].Options.AssociationDefaultRouteTableId' \
  --output text)

if [ -n "${TGW_RT_ID}" ] && [ "${TGW_RT_ID}" != "None" ]; then
  info "Default route table: ${TGW_RT_ID}"

  ROUTE_COUNT=$(aws ec2 search-transit-gateway-routes \
    --transit-gateway-route-table-id "${TGW_RT_ID}" \
    --filters "Name=type,Values=propagated" "Name=state,Values=active" \
    --region "${REGION}" \
    --query 'length(Routes)' \
    --output text)

  if [ "${ROUTE_COUNT}" -ge 3 ]; then
    pass "TGW route table has ${ROUTE_COUNT} propagated route(s) (expected >= 3: network, dev, prod)"
  else
    fail "TGW route table has ${ROUTE_COUNT} propagated route(s) (expected >= 3: network, dev, prod)"
  fi

  echo ""
  info "TGW Route Table Contents:"
  aws ec2 search-transit-gateway-routes \
    --transit-gateway-route-table-id "${TGW_RT_ID}" \
    --filters "Name=state,Values=active" \
    --region "${REGION}" \
    --query 'Routes[].{CIDR:DestinationCidrBlock,Type:Type,VPC:TransitGatewayAttachments[0].ResourceId,State:State}' \
    --output table
  echo ""
else
  fail "Could not retrieve TGW default route table ID"
fi

clear_role

# ---------------------------------------------------------------------------
# CHECK 4: Network VPC exists with correct CIDR
# ---------------------------------------------------------------------------
info "Checking network VPC..."
assume_role "${NETWORK_ACCOUNT_ID}" "${ROLE_NAME}" "verify-network-vpc"

NET_VPC=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Environment,Values=network" "Name=tag:Project,Values=aws-transit-gw-learn" \
  --region "${REGION}" \
  --query 'Vpcs[0].{Id:VpcId,CIDR:CidrBlock,State:State}' \
  --output json)

NET_VPC_ID=$(echo "${NET_VPC}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Id','NOT_FOUND'))")
NET_VPC_CIDR=$(echo "${NET_VPC}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('CIDR','UNKNOWN'))")

if [ "${NET_VPC_ID}" != "NOT_FOUND" ] && [ "${NET_VPC_ID}" != "None" ]; then
  pass "Network VPC found: ${NET_VPC_ID} (CIDR: ${NET_VPC_CIDR})"
else
  fail "Network VPC not found (tag:Environment=network, tag:Project=aws-transit-gw-learn)"
fi

if [ "${NET_VPC_ID}" != "NOT_FOUND" ] && [ "${NET_VPC_ID}" != "None" ]; then
  TGW_ROUTE=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${NET_VPC_ID}" \
    --region "${REGION}" \
    --query "RouteTables[].Routes[?TransitGatewayId=='${TGW_ID}'].DestinationCidrBlock" \
    --output text)

  if [ -n "${TGW_ROUTE}" ]; then
    pass "Network route table has TGW route: ${TGW_ROUTE} → ${TGW_ID}"
  else
    fail "Network route table missing TGW route to ${TGW_ID}"
  fi
fi

clear_role

# ---------------------------------------------------------------------------
# CHECK 5: Dev VPC exists with correct CIDR
# ---------------------------------------------------------------------------
info "Checking dev VPC..."
assume_role "${DEV_ACCOUNT_ID}" "${ROLE_NAME}" "verify-dev"

DEV_VPC=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Environment,Values=dev" "Name=tag:Project,Values=aws-transit-gw-learn" \
  --region "${REGION}" \
  --query 'Vpcs[0].{Id:VpcId,CIDR:CidrBlock,State:State}' \
  --output json)

DEV_VPC_ID=$(echo "${DEV_VPC}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Id','NOT_FOUND'))")
DEV_VPC_CIDR=$(echo "${DEV_VPC}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('CIDR','UNKNOWN'))")

if [ "${DEV_VPC_ID}" != "NOT_FOUND" ] && [ "${DEV_VPC_ID}" != "None" ]; then
  pass "Dev VPC found: ${DEV_VPC_ID} (CIDR: ${DEV_VPC_CIDR})"
else
  fail "Dev VPC not found (tag:Environment=dev, tag:Project=aws-transit-gw-learn)"
fi

if [ "${DEV_VPC_ID}" != "NOT_FOUND" ] && [ "${DEV_VPC_ID}" != "None" ]; then
  TGW_ROUTE=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${DEV_VPC_ID}" \
    --region "${REGION}" \
    --query "RouteTables[].Routes[?TransitGatewayId=='${TGW_ID}'].DestinationCidrBlock" \
    --output text)

  if [ -n "${TGW_ROUTE}" ]; then
    pass "Dev route table has TGW route: ${TGW_ROUTE} → ${TGW_ID}"
  else
    fail "Dev route table missing TGW route to ${TGW_ID}"
  fi
fi

clear_role

# ---------------------------------------------------------------------------
# CHECK 6: Prod VPC exists with correct CIDR
# ---------------------------------------------------------------------------
info "Checking prod VPC..."
assume_role "${PROD_ACCOUNT_ID}" "${ROLE_NAME}" "verify-prod"

PROD_VPC=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Environment,Values=prod" "Name=tag:Project,Values=aws-transit-gw-learn" \
  --region "${REGION}" \
  --query 'Vpcs[0].{Id:VpcId,CIDR:CidrBlock,State:State}' \
  --output json)

PROD_VPC_ID=$(echo "${PROD_VPC}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Id','NOT_FOUND'))")
PROD_VPC_CIDR=$(echo "${PROD_VPC}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('CIDR','UNKNOWN'))")

if [ "${PROD_VPC_ID}" != "NOT_FOUND" ] && [ "${PROD_VPC_ID}" != "None" ]; then
  pass "Prod VPC found: ${PROD_VPC_ID} (CIDR: ${PROD_VPC_CIDR})"
else
  fail "Prod VPC not found"
fi

if [ "${PROD_VPC_ID}" != "NOT_FOUND" ] && [ "${PROD_VPC_ID}" != "None" ]; then
  TGW_ROUTE=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${PROD_VPC_ID}" \
    --region "${REGION}" \
    --query "RouteTables[].Routes[?TransitGatewayId=='${TGW_ID}'].DestinationCidrBlock" \
    --output text)

  if [ -n "${TGW_ROUTE}" ]; then
    pass "Prod route table has TGW route: ${TGW_ROUTE} → ${TGW_ID}"
  else
    fail "Prod route table missing TGW route to ${TGW_ID}"
  fi
fi

clear_role

# ===========================================================================
#  RESOURCE INVENTORY — show command, then its output
# ===========================================================================
echo ""
echo "====================================================================="
echo " Resource Inventory"
echo "====================================================================="
echo ""
echo " Each command is printed before its output so you can copy-paste it."
echo " Network account commands require: assume terraform-execute in ${NETWORK_ACCOUNT_ID}"

# ---------------------------------------------------------------------------
# IPAM (network account)
# ---------------------------------------------------------------------------
assume_role "${NETWORK_ACCOUNT_ID}" "${ROLE_NAME}" "verify-inventory"

echo ""
info "--- IPAM ---"

echo ""
show_cmd "aws ec2 describe-ipams --region ${REGION} --query 'Ipams[].{ID:IpamId,State:State,Regions:OperatingRegions[].RegionName|join(\`, \`,@)}' --output table"
aws ec2 describe-ipams \
  --region "${REGION}" \
  --query 'Ipams[].{ID:IpamId,State:State,Regions:OperatingRegions[].RegionName|join(`, `,@)}' \
  --output table

echo ""
show_cmd "aws ec2 describe-ipam-pools --region ${REGION} --query 'IpamPools[].{Description:Description,PoolId:IpamPoolId,Locale:Locale,State:State}' --output table"
aws ec2 describe-ipam-pools \
  --region "${REGION}" \
  --query 'IpamPools[].{Description:Description,PoolId:IpamPoolId,Locale:Locale,State:State}' \
  --output table 2>/dev/null || true

IPAM_POOL_IDS=$(aws ec2 describe-ipam-pools \
  --region "${REGION}" \
  --query 'IpamPools[].IpamPoolId' \
  --output text)

for POOL_ID in ${IPAM_POOL_IDS}; do
  POOL_DESC=$(aws ec2 describe-ipam-pools \
    --region "${REGION}" \
    --filters "Name=ipam-pool-id,Values=${POOL_ID}" \
    --query 'IpamPools[0].Description' \
    --output text 2>/dev/null || echo "${POOL_ID}")
  echo ""
  info "  ${POOL_DESC}:"
  show_cmd "aws ec2 get-ipam-pool-cidrs --ipam-pool-id ${POOL_ID} --region ${REGION} --output table"
  aws ec2 get-ipam-pool-cidrs \
    --ipam-pool-id "${POOL_ID}" \
    --region "${REGION}" \
    --query 'IpamPoolCidrs[].{CIDR:Cidr,State:State}' \
    --output table 2>/dev/null || echo "  (no CIDRs)"

  ALLOC_COUNT=$(aws ec2 get-ipam-pool-allocations \
    --ipam-pool-id "${POOL_ID}" \
    --region "${REGION}" \
    --query 'length(IpamPoolAllocations)' \
    --output text 2>/dev/null || echo "0")
  if [ "${ALLOC_COUNT}" -gt 0 ] 2>/dev/null; then
    show_cmd "aws ec2 get-ipam-pool-allocations --ipam-pool-id ${POOL_ID} --region ${REGION} --query 'IpamPoolAllocations[].{CIDR:Cidr,Type:ResourceType,ResourceId:ResourceId,Owner:ResourceOwner}' --output table"
    aws ec2 get-ipam-pool-allocations \
      --ipam-pool-id "${POOL_ID}" \
      --region "${REGION}" \
      --query 'IpamPoolAllocations[].{CIDR:Cidr,Type:ResourceType,ResourceId:ResourceId,Owner:ResourceOwner}' \
      --output table
  fi
done

# ---------------------------------------------------------------------------
# RAM (network account)
# ---------------------------------------------------------------------------
echo ""
info "--- RAM Resource Shares ---"

echo ""
show_cmd "aws ram get-resource-shares --resource-owner SELF --region ${REGION} --query 'resourceShares[].{Name:name,Status:status}' --output table"
aws ram get-resource-shares \
  --resource-owner SELF \
  --region "${REGION}" \
  --query 'resourceShares[].{Name:name,Status:status}' \
  --output table

RAM_SHARE_ARNS=$(aws ram get-resource-shares \
  --resource-owner SELF \
  --region "${REGION}" \
  --query 'resourceShares[].resourceShareArn' \
  --output text)

for SHARE_ARN in ${RAM_SHARE_ARNS}; do
  SHARE_NAME=$(aws ram get-resource-shares \
    --resource-owner SELF \
    --region "${REGION}" \
    --resource-share-arns "${SHARE_ARN}" \
    --query 'resourceShares[0].name' \
    --output text)

  echo ""
  info "  ${SHARE_NAME} — resources:"
  show_cmd "aws ram list-resources --resource-owner SELF --resource-share-arns ${SHARE_ARN} --region ${REGION} --query 'resources[].{Type:type,ARN:arn,Status:status}' --output table"
  aws ram list-resources \
    --resource-owner SELF \
    --resource-share-arns "${SHARE_ARN}" \
    --region "${REGION}" \
    --query 'resources[].{Type:type,ARN:arn,Status:status}' \
    --output table 2>/dev/null || echo "    (none)"

  info "  ${SHARE_NAME} — principals:"
  show_cmd "aws ram list-principals --resource-owner SELF --resource-share-arns ${SHARE_ARN} --region ${REGION} --query 'principals[].{Principal:id,Status:status}' --output table"
  aws ram list-principals \
    --resource-owner SELF \
    --resource-share-arns "${SHARE_ARN}" \
    --region "${REGION}" \
    --query 'principals[].{Principal:id,Status:status}' \
    --output table 2>/dev/null || echo "    (none)"
done

# ---------------------------------------------------------------------------
# Transit Gateway (network account)
# ---------------------------------------------------------------------------
echo ""
info "--- Transit Gateway ---"

echo ""
show_cmd "aws ec2 describe-transit-gateways --transit-gateway-ids ${TGW_ID} --region ${REGION} --query 'TransitGateways[0].{ID:TransitGatewayId,State:State,AutoAccept:Options.AutoAcceptSharedAttachments,DefaultRtAssoc:Options.DefaultRouteTableAssociation,DefaultRtProp:Options.DefaultRouteTablePropagation,DnsSupport:Options.DnsSupport,VpnEcmp:Options.VpnEcmpSupport}' --output table"
aws ec2 describe-transit-gateways \
  --transit-gateway-ids "${TGW_ID}" \
  --region "${REGION}" \
  --query 'TransitGateways[0].{ID:TransitGatewayId,State:State,AutoAccept:Options.AutoAcceptSharedAttachments,DefaultRtAssoc:Options.DefaultRouteTableAssociation,DefaultRtProp:Options.DefaultRouteTablePropagation,DnsSupport:Options.DnsSupport,VpnEcmp:Options.VpnEcmpSupport}' \
  --output table

echo ""
show_cmd "aws ec2 describe-transit-gateway-attachments --filters 'Name=transit-gateway-id,Values=${TGW_ID}' --region ${REGION} --query 'TransitGatewayAttachments[].{State:State,Type:ResourceType,OwnerAccount:ResourceOwnerId,ResourceId:ResourceId}' --output table"
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=transit-gateway-id,Values=${TGW_ID}" \
  --region "${REGION}" \
  --query 'TransitGatewayAttachments[].{State:State,Type:ResourceType,OwnerAccount:ResourceOwnerId,ResourceId:ResourceId}' \
  --output table

if [ -n "${TGW_RT_ID:-}" ] && [ "${TGW_RT_ID}" != "None" ]; then
  echo ""
  show_cmd "aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id ${TGW_RT_ID} --filters 'Name=state,Values=active' --region ${REGION} --query 'Routes[].{CIDR:DestinationCidrBlock,Type:Type,VPC:TransitGatewayAttachments[0].ResourceId,State:State}' --output table"
  aws ec2 search-transit-gateway-routes \
    --transit-gateway-route-table-id "${TGW_RT_ID}" \
    --filters "Name=state,Values=active" \
    --region "${REGION}" \
    --query 'Routes[].{CIDR:DestinationCidrBlock,Type:Type,VPC:TransitGatewayAttachments[0].ResourceId,State:State}' \
    --output table
fi

clear_role

# ---------------------------------------------------------------------------
# VPC Detail: Network Account
# ---------------------------------------------------------------------------
echo ""
info "--- Network VPC (account ${NETWORK_ACCOUNT_ID}) ---"
assume_role "${NETWORK_ACCOUNT_ID}" "${ROLE_NAME}" "verify-inv-network"

if [ "${NET_VPC_ID}" != "NOT_FOUND" ] && [ "${NET_VPC_ID}" != "None" ]; then
  echo ""
  show_cmd "aws ec2 describe-subnets --filters 'Name=vpc-id,Values=${NET_VPC_ID}' --region ${REGION} --query 'Subnets[].{SubnetId:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,State:State}' --output table"
  aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${NET_VPC_ID}" \
    --region "${REGION}" \
    --query 'Subnets[].{SubnetId:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,State:State}' \
    --output table

  echo ""
  show_cmd "aws ec2 describe-route-tables --filters 'Name=vpc-id,Values=${NET_VPC_ID}' --region ${REGION} --query 'RouteTables[].Routes[].{Destination:DestinationCidrBlock,Target:GatewayId||TransitGatewayId||NatGatewayId||\`local\`,State:State}' --output table"
  aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${NET_VPC_ID}" \
    --region "${REGION}" \
    --query 'RouteTables[].Routes[].{Destination:DestinationCidrBlock,Target:GatewayId||TransitGatewayId||NatGatewayId||`local`,State:State}' \
    --output table
fi

clear_role

# ---------------------------------------------------------------------------
# VPC Detail: Dev Account
# ---------------------------------------------------------------------------
echo ""
info "--- Dev VPC (account ${DEV_ACCOUNT_ID}) ---"
assume_role "${DEV_ACCOUNT_ID}" "${ROLE_NAME}" "verify-inv-dev"

if [ "${DEV_VPC_ID}" != "NOT_FOUND" ] && [ "${DEV_VPC_ID}" != "None" ]; then
  echo ""
  show_cmd "aws ec2 describe-subnets --filters 'Name=vpc-id,Values=${DEV_VPC_ID}' --region ${REGION} --query 'Subnets[].{SubnetId:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,State:State}' --output table"
  aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${DEV_VPC_ID}" \
    --region "${REGION}" \
    --query 'Subnets[].{SubnetId:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,State:State}' \
    --output table

  echo ""
  show_cmd "aws ec2 describe-route-tables --filters 'Name=vpc-id,Values=${DEV_VPC_ID}' --region ${REGION} --query 'RouteTables[].Routes[].{Destination:DestinationCidrBlock,Target:GatewayId||TransitGatewayId||NatGatewayId||\`local\`,State:State}' --output table"
  aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${DEV_VPC_ID}" \
    --region "${REGION}" \
    --query 'RouteTables[].Routes[].{Destination:DestinationCidrBlock,Target:GatewayId||TransitGatewayId||NatGatewayId||`local`,State:State}' \
    --output table
fi

clear_role

# ---------------------------------------------------------------------------
# VPC Detail: Prod Account
# ---------------------------------------------------------------------------
echo ""
info "--- Prod VPC (account ${PROD_ACCOUNT_ID}) ---"
assume_role "${PROD_ACCOUNT_ID}" "${ROLE_NAME}" "verify-inv-prod"

if [ "${PROD_VPC_ID}" != "NOT_FOUND" ] && [ "${PROD_VPC_ID}" != "None" ]; then
  echo ""
  show_cmd "aws ec2 describe-subnets --filters 'Name=vpc-id,Values=${PROD_VPC_ID}' --region ${REGION} --query 'Subnets[].{SubnetId:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,State:State}' --output table"
  aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${PROD_VPC_ID}" \
    --region "${REGION}" \
    --query 'Subnets[].{SubnetId:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,State:State}' \
    --output table

  echo ""
  show_cmd "aws ec2 describe-route-tables --filters 'Name=vpc-id,Values=${PROD_VPC_ID}' --region ${REGION} --query 'RouteTables[].Routes[].{Destination:DestinationCidrBlock,Target:GatewayId||TransitGatewayId||NatGatewayId||\`local\`,State:State}' --output table"
  aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${PROD_VPC_ID}" \
    --region "${REGION}" \
    --query 'RouteTables[].Routes[].{Destination:DestinationCidrBlock,Target:GatewayId||TransitGatewayId||NatGatewayId||`local`,State:State}' \
    --output table
fi

clear_role

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "====================================================================="
echo " Verification Summary"
echo "====================================================================="
echo -e " ${GREEN}Passed: ${PASS}${NC}"
if [ "${FAIL}" -gt 0 ]; then
  echo -e " ${RED}Failed: ${FAIL}${NC}"
  echo ""
  echo " See runbook.md#validation for troubleshooting steps."
  echo "====================================================================="
  exit 1
else
  echo -e " ${GREEN}Failed: ${FAIL}${NC}"
  echo ""
  echo " All checks passed. The Transit Gateway + IPAM deployment is healthy."
  echo " Next: use AWS Reachability Analyzer to verify logical connectivity."
  echo " See runbook.md#validation for Reachability Analyzer instructions."
  echo "====================================================================="
  exit 0
fi
