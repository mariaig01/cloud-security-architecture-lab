output "network" {
  description = "Network identifiers used by the optional temporary probes."
  value = {
    vpc_id                 = aws_vpc.lab.id
    public_subnet_id       = aws_subnet.public.id
    private_subnet_id      = aws_subnet.private.id
    private_route_table_id = aws_route_table.private.id
    app_security_group_id  = aws_security_group.app.id
    s3_endpoint_id         = aws_vpc_endpoint.s3.id
    s3_prefix_list_id      = aws_vpc_endpoint.s3.prefix_list_id
  }
}

output "storage" {
  description = "Bucket names, ARNs and the only application-authorized key prefix."
  value = {
    documents_bucket     = aws_s3_bucket.documents.id
    documents_bucket_arn = local.documents_bucket_arn
    logs_bucket          = aws_s3_bucket.logs.id
    logs_bucket_arn      = local.logs_bucket_arn
    document_prefix      = var.document_prefix
  }
}

output "application" {
  description = "Attach this profile only to the authorized lab probes."
  value = {
    role_arn              = aws_iam_role.app.arn
    role_name             = aws_iam_role.app.name
    instance_profile_name = aws_iam_instance_profile.app.name
  }
}

output "audit" {
  description = "Trail to inspect from the operator's authenticated environment."
  value = {
    trail_arn = aws_cloudtrail.lab.arn
    region    = var.aws_region
  }
}
