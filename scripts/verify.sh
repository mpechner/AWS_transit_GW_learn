#!/usr/bin/env bash
# =============================================================================
# verify.sh — Post-deployment validation for Transit Gateway + IPAM
# =============================================================================
# Usage:
#   NETWORK_ACCOUNT_ID=111111111111 \
#   DEV_ACCOUNT_ID=222222222222 \
#   PROD_ACCOUNT_ID=333333333333 \
#   TGW_ID=tgw-xxxxxxxxxxxxxxxxx \
#   AWS_REGION=us-west-2 \
#     bash scripts/verify.sh
#
# Prerequisites:
#   - AWS CLI v2 installed
#   - Credentials that can assume terraform-execute in all three accounts
#   - All three environments successfully applied
# =============================================================================

set -euo pipefail

ROLE_NAME="terraform-execute"
REGION="${AWS_REGION:-us-west-2}"

# Required environment variables
: "${NETWORK_ACCOUNT_ID:?Set NETWORK_ACCOUNT_ID}"
: "${DEV_ACCOUNT_ID:?Set DEV_ACCOUNT_ID}"
: "${PROD_ACCOUNT_ID:?Set PROD_ACCOUNT_ID}"
: "${TGW_ID:?Set TGW_ID (from terraform output transit_gateway_id in environments/network)}"

PASS=0
FAIL=0

# Colors (only if terminal supports it)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' NC=''
fi

pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Assume a role and export credentials
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

# Clear assumed role credentials
clear_role() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

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

if [ "${ATTACHMENT_COUNT}" -ge 2 ]; then
  pass "TGW has ${ATTACHMENT_COUNT} available attachment(s) (expected >= 2)"
else
  fail "TGW has ${ATTACHMENT_COUNT} available attachment(s) (expected >= 2)"
fi

# Show attachment details
echo ""
info "TGW Attachment Details:"
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=transit-gateway-id,Values=${TGW_ID}" \
  --region "${REGION}" \
  --query 'TransitGatewayAttachments[].{State:State,Type:ResourceType,Account:CreatedBy,ResourceId:ResourceId}' \
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

  if [ "${ROUTE_COUNT}" -ge 2 ]; then
    pass "TGW route table has ${ROUTE_COUNT} propagated route(s) (expected >= 2)"
  else
    fail "TGW route table has ${ROUTE_COUNT} propagated route(s) (expected >= 2 — dev and prod)"
  fi

  echo ""
  info "TGW Route Table Contents:"
  aws ec2 search-transit-gateway-routes \
    --transit-gateway-route-table-id "${TGW_RT_ID}" \
    --filters "Name=state,Values=active" \
    --region "${REGION}" \
    --query 'Routes[].{CIDR:DestinationCidrBlock,Type:Type,State:State}' \
    --output table
  echo ""
else
  fail "Could not retrieve TGW default route table ID"
fi

clear_role

# ---------------------------------------------------------------------------
# CHECK 4: Dev VPC exists with correct CIDR
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

# Check dev route table has TGW route
if [ "${DEV_VPC_ID}" != "NOT_FOUND" ]; then
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
# CHECK 5: Prod VPC exists with correct CIDR
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

# Check prod route table has TGW route
if [ "${PROD_VPC_ID}" != "NOT_FOUND" ]; then
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
  echo -e " ${RED}Failed: ${FAIL}${NC}"
  echo ""
  echo " All checks passed. The Transit Gateway + IPAM deployment is healthy."
  echo " Next: use AWS Reachability Analyzer to verify logical connectivity."
  echo " See runbook.md#validation for Reachability Analyzer instructions."
  echo "====================================================================="
  exit 0
fi
