output "tgw_id" {
  description = "Transit Gateway ID. Pass this to workload environments as transit_gateway_id."
  value       = aws_ec2_transit_gateway.main.id
}

output "tgw_arn" {
  description = "Transit Gateway ARN."
  value       = aws_ec2_transit_gateway.main.arn
}

output "tgw_default_route_table_id" {
  description = "ID of the TGW default route table. Use this to verify propagated routes after attachments are created."
  value       = aws_ec2_transit_gateway.main.association_default_route_table_id
}

output "ram_share_arn" {
  description = "ARN of the RAM resource share for the Transit Gateway."
  value       = aws_ram_resource_share.tgw.arn
}
