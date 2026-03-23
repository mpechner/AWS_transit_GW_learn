# Sample `verify.sh` Output

> This is the actual output from a successful deployment, captured so you can
> review what the script checks and displays without deploying anything.
>
> Account numbers and the organization ID have been anonymized. All other
> identifiers (VPC IDs, subnet IDs, IPAM pool IDs, TGW IDs, RAM share ARNs)
> are ephemeral — they are created by `terraform apply` and destroyed by
> `terraform destroy`.

```
$ bash scripts/verify.sh

[INFO] Reading values from Terraform state...

=====================================================================
 AWS Transit Gateway + IPAM Deployment Verification
=====================================================================
 Region:          us-west-2
 Network Account: 111111111111
 Dev Account:     222222222222
 Prod Account:    333333333333
 TGW ID:          tgw-0d99b4b89c762846e
=====================================================================

[INFO] Checking Transit Gateway in network account...
[PASS] Transit Gateway tgw-0d99b4b89c762846e state: available
[INFO] Checking TGW attachment states...
[PASS] TGW has 3 available attachment(s) (expected >= 3: network, dev, prod)

[INFO] TGW Attachment Details:
-----------------------------------------------------------------------
|                DescribeTransitGatewayAttachments                    |
+--------------+-------------------------+------------+--------+
| OwnerAccount |       ResourceId        |   State    | Type   |
+--------------+-------------------------+------------+--------+
|  111111111111|  vpc-087ad34d973439867  |  available |  vpc   |
|  222222222222|  vpc-06dfa65f4c3960a9b  |  available |  vpc   |
|  333333333333|  vpc-0f40843575a928f6c  |  available |  vpc   |
+--------------+-------------------------+------------+--------+

[INFO] Checking TGW route table for propagated routes...
[INFO] Default route table: tgw-rtb-0c8ce2cd6e8298bfd
[PASS] TGW route table has 3 propagated route(s) (expected >= 3: network, dev, prod)

[INFO] TGW Route Table Contents:
----------------------------------------------------------------------
|                    SearchTransitGatewayRoutes                      |
+-------------+----------+--------------+---------------------------+
|    CIDR     |  State   |    Type      |           VPC             |
+-------------+----------+--------------+---------------------------+
|  10.0.0.0/24|  active  |  propagated  |  vpc-087ad34d973439867    |
|  10.0.1.0/24|  active  |  propagated  |  vpc-06dfa65f4c3960a9b    |
|  10.0.2.0/24|  active  |  propagated  |  vpc-0f40843575a928f6c    |
+-------------+----------+--------------+---------------------------+

[INFO] Checking network VPC...
[PASS] Network VPC found: vpc-087ad34d973439867 (CIDR: 10.0.0.0/24)
[PASS] Network route table has TGW route: 10.0.0.0/16 → tgw-0d99b4b89c762846e
[INFO] Checking dev VPC...
[PASS] Dev VPC found: vpc-06dfa65f4c3960a9b (CIDR: 10.0.1.0/24)
[PASS] Dev route table has TGW route: 10.0.0.0/16 → tgw-0d99b4b89c762846e
[INFO] Checking prod VPC...
[PASS] Prod VPC found: vpc-0f40843575a928f6c (CIDR: 10.0.2.0/24)
[PASS] Prod route table has TGW route: 10.0.0.0/16 → tgw-0d99b4b89c762846e

=====================================================================
 Resource Inventory
=====================================================================

 Each command is printed before its output so you can copy-paste it.
 Network account commands require: assume terraform-execute in 111111111111

[INFO] --- IPAM ---

$ aws ec2 describe-ipams --region us-west-2 \
    --query 'Ipams[].{ID:IpamId,State:State,Regions:OperatingRegions[].RegionName|join(`, `,@)}' \
    --output table
------------------------------------------------------------
|                       DescribeIpams                      |
+-------------------------+------------+-------------------+
|           ID            |  Regions   |       State       |
+-------------------------+------------+-------------------+
|  ipam-0a9f402ac01136a12 |  us-west-2 |  create-complete  |
+-------------------------+------------+-------------------+

$ aws ec2 describe-ipam-pools --region us-west-2 \
    --query 'IpamPools[].{Description:Description,PoolId:IpamPoolId,Locale:Locale,State:State}' \
    --output table
-----------------------------------------------------------------------------------------------------------------
|                                               DescribeIpamPools                                               |
+-----------------------------------------------+------------+-------------------------------+------------------+
|                  Description                  |  Locale    |            PoolId             |      State       |
+-----------------------------------------------+------------+-------------------------------+------------------+
|  Network account address pool                 |  us-west-2 |  ipam-pool-04a0449cdd3e15a7a  |  create-complete |
|  Regional pool — us-west-2                   |  us-west-2 |  ipam-pool-05f26cd57a6dbb9e0  |  create-complete |
|  Root IPv4 pool — holds entire address space |  None      |  ipam-pool-0bf4824cd0d3a4f8d  |  create-complete |
|  Dev workload address pool                    |  us-west-2 |  ipam-pool-0d9f464919796dfa6  |  create-complete |
|  Prod workload address pool                   |  us-west-2 |  ipam-pool-0da7d72722cc01006  |  create-complete |
+-----------------------------------------------+------------+-------------------------------+------------------+

[INFO]   Network account address pool:
$ aws ec2 get-ipam-pool-cidrs --ipam-pool-id ipam-pool-04a0449cdd3e15a7a \
    --region us-west-2 --output table
--------------------------------
|       GetIpamPoolCidrs       |
+--------------+---------------+
|     CIDR     |     State     |
+--------------+---------------+
|  10.0.0.0/24 |  provisioned  |
+--------------+---------------+
$ aws ec2 get-ipam-pool-allocations --ipam-pool-id ipam-pool-04a0449cdd3e15a7a \
    --region us-west-2 \
    --query 'IpamPoolAllocations[].{CIDR:Cidr,Type:ResourceType,ResourceId:ResourceId,Owner:ResourceOwner}' \
    --output table
-------------------------------------------------------------------
|                   GetIpamPoolAllocations                        |
+--------------+-------------------------+-------+--------------+
|     CIDR     |       ResourceId        | Type  |    Owner     |
+--------------+-------------------------+-------+--------------+
|  10.0.0.0/24 |  vpc-087ad34d973439867  |  vpc  | 111111111111 |
+--------------+-------------------------+-------+--------------+

[INFO]   Regional pool — us-west-2:
$ aws ec2 get-ipam-pool-cidrs --ipam-pool-id ipam-pool-05f26cd57a6dbb9e0 \
    --region us-west-2 --output table
--------------------------------
|       GetIpamPoolCidrs       |
+--------------+---------------+
|     CIDR     |     State     |
+--------------+---------------+
|  10.0.0.0/16 |  provisioned  |
+--------------+---------------+
$ aws ec2 get-ipam-pool-allocations --ipam-pool-id ipam-pool-05f26cd57a6dbb9e0 \
    --region us-west-2 \
    --query 'IpamPoolAllocations[].{CIDR:Cidr,Type:ResourceType,ResourceId:ResourceId,Owner:ResourceOwner}' \
    --output table
----------------------------------------------------------------------------
|                        GetIpamPoolAllocations                            |
+--------------+-------------------------------+------------+--------------+
|     CIDR     |          ResourceId           |   Type     |    Owner     |
+--------------+-------------------------------+------------+--------------+
|  10.0.0.0/24 |  ipam-pool-04a0449cdd3e15a7a  |  ipam-pool | 111111111111 |
|  10.0.1.0/24 |  ipam-pool-0d9f464919796dfa6  |  ipam-pool | 111111111111 |
|  10.0.2.0/24 |  ipam-pool-0da7d72722cc01006  |  ipam-pool | 111111111111 |
+--------------+-------------------------------+------------+--------------+

[INFO]   Root IPv4 pool — holds entire address space:
$ aws ec2 get-ipam-pool-cidrs --ipam-pool-id ipam-pool-0bf4824cd0d3a4f8d \
    --region us-west-2 --output table
-------------------------------
|      GetIpamPoolCidrs       |
+-------------+---------------+
|    CIDR     |     State     |
+-------------+---------------+
|  10.0.0.0/8 |  provisioned  |
+-------------+---------------+
$ aws ec2 get-ipam-pool-allocations --ipam-pool-id ipam-pool-0bf4824cd0d3a4f8d \
    --region us-west-2 \
    --query 'IpamPoolAllocations[].{CIDR:Cidr,Type:ResourceType,ResourceId:ResourceId,Owner:ResourceOwner}' \
    --output table
----------------------------------------------------------------------------
|                        GetIpamPoolAllocations                            |
+--------------+-------------------------------+------------+--------------+
|     CIDR     |          ResourceId           |   Type     |    Owner     |
+--------------+-------------------------------+------------+--------------+
|  10.0.0.0/16 |  ipam-pool-05f26cd57a6dbb9e0  |  ipam-pool | 111111111111 |
+--------------+-------------------------------+------------+--------------+

[INFO]   Dev workload address pool:
$ aws ec2 get-ipam-pool-cidrs --ipam-pool-id ipam-pool-0d9f464919796dfa6 \
    --region us-west-2 --output table
--------------------------------
|       GetIpamPoolCidrs       |
+--------------+---------------+
|     CIDR     |     State     |
+--------------+---------------+
|  10.0.1.0/24 |  provisioned  |
+--------------+---------------+
$ aws ec2 get-ipam-pool-allocations --ipam-pool-id ipam-pool-0d9f464919796dfa6 \
    --region us-west-2 \
    --query 'IpamPoolAllocations[].{CIDR:Cidr,Type:ResourceType,ResourceId:ResourceId,Owner:ResourceOwner}' \
    --output table
-------------------------------------------------------------------
|                   GetIpamPoolAllocations                        |
+--------------+-------------------------+-------+--------------+
|     CIDR     |       ResourceId        | Type  |    Owner     |
+--------------+-------------------------+-------+--------------+
|  10.0.1.0/24 |  vpc-06dfa65f4c3960a9b  |  vpc  | 222222222222 |
+--------------+-------------------------+-------+--------------+

[INFO]   Prod workload address pool:
$ aws ec2 get-ipam-pool-cidrs --ipam-pool-id ipam-pool-0da7d72722cc01006 \
    --region us-west-2 --output table
--------------------------------
|       GetIpamPoolCidrs       |
+--------------+---------------+
|     CIDR     |     State     |
+--------------+---------------+
|  10.0.2.0/24 |  provisioned  |
+--------------+---------------+
$ aws ec2 get-ipam-pool-allocations --ipam-pool-id ipam-pool-0da7d72722cc01006 \
    --region us-west-2 \
    --query 'IpamPoolAllocations[].{CIDR:Cidr,Type:ResourceType,ResourceId:ResourceId,Owner:ResourceOwner}' \
    --output table
-------------------------------------------------------------------
|                   GetIpamPoolAllocations                        |
+--------------+-------------------------+-------+--------------+
|     CIDR     |       ResourceId        | Type  |    Owner     |
+--------------+-------------------------+-------+--------------+
|  10.0.2.0/24 |  vpc-0f40843575a928f6c  |  vpc  | 333333333333 |
+--------------+-------------------------+-------+--------------+

[INFO] --- RAM Resource Shares ---

$ aws ram get-resource-shares --resource-owner SELF --region us-west-2 \
    --query 'resourceShares[].{Name:name,Status:status}' --output table
-----------------------------------------------------
|                 GetResourceShares                 |
+----------------------------------------+----------+
|                  Name                  | Status   |
+----------------------------------------+----------+
|  aws-transit-gw-learn-tgw-share        |  ACTIVE  |
|  aws-transit-gw-learn-ipam-pool-share  |  DELETED |
|  aws-transit-gw-learn-ipam-pool-share  |  ACTIVE  |
|  aws-transit-gw-learn-tgw-share        |  DELETED |
+----------------------------------------+----------+

[INFO]   aws-transit-gw-learn-tgw-share — resources:
$ aws ram list-resources --resource-owner SELF \
    --resource-share-arns arn:aws:ram:us-west-2:111111111111:resource-share/3171263a-... \
    --region us-west-2 \
    --query 'resources[].{Type:type,ARN:arn,Status:status}' --output table
--------------------------------------------------------------------------------------------------------------
|                                                ListResources                                               |
+---------------------------------------------------------------------------+---------+----------------------+
|                                    ARN                                    | Status  |        Type          |
+---------------------------------------------------------------------------+---------+----------------------+
|  arn:aws:ec2:us-west-2:111111111111:transit-gateway/tgw-0d99b4b89c762846e |  None   |  ec2:TransitGateway  |
+---------------------------------------------------------------------------+---------+----------------------+
[INFO]   aws-transit-gw-learn-tgw-share — principals:
$ aws ram list-principals --resource-owner SELF \
    --resource-share-arns arn:aws:ram:us-west-2:111111111111:resource-share/3171263a-... \
    --region us-west-2 \
    --query 'principals[].{Principal:id,Status:status}' --output table
-----------------------------------------------------------------------------
|                              ListPrincipals                               |
+-----------------------------------------------------------------+---------+
|                            Principal                            | Status  |
+-----------------------------------------------------------------+---------+
|  arn:aws:organizations::444444444444:organization/o-exampleorg  |  None   |
+-----------------------------------------------------------------+---------+

[INFO]   aws-transit-gw-learn-ipam-pool-share — resources:
$ aws ram list-resources --resource-owner SELF \
    --resource-share-arns arn:aws:ram:us-west-2:111111111111:resource-share/9df89154-... \
    --region us-west-2 \
    --query 'resources[].{Type:type,ARN:arn,Status:status}' --output table
-----------------------------------------------------------------------------------------------
|                                        ListResources                                        |
+------------------------------------------------------------------+---------+----------------+
|                                ARN                               | Status  |     Type       |
+------------------------------------------------------------------+---------+----------------+
|  arn:aws:ec2::111111111111:ipam-pool/ipam-pool-0d9f464919796dfa6 |  None   |  ec2:IpamPool  |
|  arn:aws:ec2::111111111111:ipam-pool/ipam-pool-0da7d72722cc01006 |  None   |  ec2:IpamPool  |
+------------------------------------------------------------------+---------+----------------+
[INFO]   aws-transit-gw-learn-ipam-pool-share — principals:
$ aws ram list-principals --resource-owner SELF \
    --resource-share-arns arn:aws:ram:us-west-2:111111111111:resource-share/9df89154-... \
    --region us-west-2 \
    --query 'principals[].{Principal:id,Status:status}' --output table
-----------------------------------------------------------------------------
|                              ListPrincipals                               |
+-----------------------------------------------------------------+---------+
|                            Principal                            | Status  |
+-----------------------------------------------------------------+---------+
|  arn:aws:organizations::444444444444:organization/o-exampleorg  |  None   |
+-----------------------------------------------------------------+---------+

[INFO] --- Transit Gateway ---

$ aws ec2 describe-transit-gateways --transit-gateway-ids tgw-0d99b4b89c762846e \
    --region us-west-2 \
    --query 'TransitGateways[0].{ID:TransitGatewayId,State:State,...}' \
    --output table
------------------------------------------------------------------------------------------------------------------
|                                             DescribeTransitGateways                                            |
+------------+-----------------+----------------+-------------+------------------------+-------------+-----------+
| AutoAccept | DefaultRtAssoc  | DefaultRtProp  | DnsSupport  |          ID            |    State    |  VpnEcmp  |
+------------+-----------------+----------------+-------------+------------------------+-------------+-----------+
|  enable    |  enable         |  enable        |  enable     |  tgw-0d99b4b89c762846e |  available  |  disable  |
+------------+-----------------+----------------+-------------+------------------------+-------------+-----------+

$ aws ec2 describe-transit-gateway-attachments \
    --filters 'Name=transit-gateway-id,Values=tgw-0d99b4b89c762846e' \
    --region us-west-2 \
    --query 'TransitGatewayAttachments[].{State:State,Type:ResourceType,OwnerAccount:ResourceOwnerId,ResourceId:ResourceId}' \
    --output table
-----------------------------------------------------------------------
|                DescribeTransitGatewayAttachments                    |
+--------------+-------------------------+------------+--------+
| OwnerAccount |       ResourceId        |   State    | Type   |
+--------------+-------------------------+------------+--------+
|  111111111111|  vpc-087ad34d973439867  |  available |  vpc   |
|  222222222222|  vpc-06dfa65f4c3960a9b  |  available |  vpc   |
|  333333333333|  vpc-0f40843575a928f6c  |  available |  vpc   |
+--------------+-------------------------+------------+--------+

$ aws ec2 search-transit-gateway-routes \
    --transit-gateway-route-table-id tgw-rtb-0c8ce2cd6e8298bfd \
    --filters 'Name=state,Values=active' --region us-west-2 \
    --query 'Routes[].{CIDR:DestinationCidrBlock,Type:Type,VPC:TransitGatewayAttachments[0].ResourceId,State:State}' --output table
----------------------------------------------------------------------
|                    SearchTransitGatewayRoutes                      |
+-------------+----------+--------------+---------------------------+
|    CIDR     |  State   |    Type      |           VPC             |
+-------------+----------+--------------+---------------------------+
|  10.0.0.0/24|  active  |  propagated  |  vpc-087ad34d973439867    |
|  10.0.1.0/24|  active  |  propagated  |  vpc-06dfa65f4c3960a9b    |
|  10.0.2.0/24|  active  |  propagated  |  vpc-0f40843575a928f6c    |
+-------------+----------+--------------+---------------------------+

[INFO] --- Network VPC (account 111111111111) ---

$ aws ec2 describe-subnets \
    --filters 'Name=vpc-id,Values=vpc-087ad34d973439867' --region us-west-2 \
    --query 'Subnets[].{SubnetId:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,State:State}' \
    --output table
------------------------------------------------------------------------------------
|                                 DescribeSubnets                                  |
+------------+---------------+--------+------------+-----------------------------+
|     AZ     |     CIDR      | Public |   State    |          SubnetId           |
+------------+---------------+--------+------------+-----------------------------+
|  us-west-2a|  10.0.0.0/26  |  False |  available |  subnet-0702dde763148ed68   |
|  us-west-2b|  10.0.0.64/26 |  False |  available |  subnet-06991cbf716c0c679   |
+------------+---------------+--------+------------+-----------------------------+

$ aws ec2 describe-route-tables \
    --filters 'Name=vpc-id,Values=vpc-087ad34d973439867' --region us-west-2 \
    --query 'RouteTables[].Routes[].{Destination:DestinationCidrBlock,Target:...,State:State}' \
    --output table
----------------------------------------------------
|                DescribeRouteTables               |
+--------------+---------+-------------------------+
|  Destination |  State  |         Target          |
+--------------+---------+-------------------------+
|  10.0.0.0/24 |  active |  local                  |
|  10.0.0.0/24 |  active |  local                  |
|  10.0.0.0/16 |  active |  tgw-0d99b4b89c762846e  |
+--------------+---------+-------------------------+

[INFO] --- Dev VPC (account 222222222222) ---

$ aws ec2 describe-subnets \
    --filters 'Name=vpc-id,Values=vpc-06dfa65f4c3960a9b' --region us-west-2 \
    --query 'Subnets[].{SubnetId:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,State:State}' \
    --output table
------------------------------------------------------------------------------------
|                                 DescribeSubnets                                  |
+------------+---------------+--------+------------+-----------------------------+
|     AZ     |     CIDR      | Public |   State    |          SubnetId           |
+------------+---------------+--------+------------+-----------------------------+
|  us-west-2b|  10.0.1.64/26 |  False |  available |  subnet-032e659d9216f5227   |
|  us-west-2a|  10.0.1.0/26  |  False |  available |  subnet-0bf88878293b363cb   |
+------------+---------------+--------+------------+-----------------------------+

$ aws ec2 describe-route-tables \
    --filters 'Name=vpc-id,Values=vpc-06dfa65f4c3960a9b' --region us-west-2 \
    --query 'RouteTables[].Routes[].{Destination:DestinationCidrBlock,Target:...,State:State}' \
    --output table
----------------------------------------------------
|                DescribeRouteTables               |
+--------------+---------+-------------------------+
|  Destination |  State  |         Target          |
+--------------+---------+-------------------------+
|  10.0.1.0/24 |  active |  local                  |
|  10.0.1.0/24 |  active |  local                  |
|  10.0.0.0/16 |  active |  tgw-0d99b4b89c762846e  |
+--------------+---------+-------------------------+

[INFO] --- Prod VPC (account 333333333333) ---

$ aws ec2 describe-subnets \
    --filters 'Name=vpc-id,Values=vpc-0f40843575a928f6c' --region us-west-2 \
    --query 'Subnets[].{SubnetId:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,State:State}' \
    --output table
------------------------------------------------------------------------------------
|                                 DescribeSubnets                                  |
+------------+---------------+--------+------------+-----------------------------+
|     AZ     |     CIDR      | Public |   State    |          SubnetId           |
+------------+---------------+--------+------------+-----------------------------+
|  us-west-2b|  10.0.2.64/26 |  False |  available |  subnet-0ef8f2cfd99c9b2c6   |
|  us-west-2a|  10.0.2.0/26  |  False |  available |  subnet-007331519954b9c81   |
+------------+---------------+--------+------------+-----------------------------+

$ aws ec2 describe-route-tables \
    --filters 'Name=vpc-id,Values=vpc-0f40843575a928f6c' --region us-west-2 \
    --query 'RouteTables[].Routes[].{Destination:DestinationCidrBlock,Target:...,State:State}' \
    --output table
----------------------------------------------------
|                DescribeRouteTables               |
+--------------+---------+-------------------------+
|  Destination |  State  |         Target          |
+--------------+---------+-------------------------+
|  10.0.2.0/24 |  active |  local                  |
|  10.0.2.0/24 |  active |  local                  |
|  10.0.0.0/16 |  active |  tgw-0d99b4b89c762846e  |
+--------------+---------+-------------------------+

=====================================================================
 Verification Summary
=====================================================================
 Passed: 9
 Failed: 0

 All checks passed. The Transit Gateway + IPAM deployment is healthy.
 Next: use AWS Reachability Analyzer to verify logical connectivity.
 See runbook.md#validation for Reachability Analyzer instructions.
=====================================================================
```
