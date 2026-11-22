# All providers are mocked. No AWS credentials or AWS API calls are used.
mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = { id = "ami-0123456789abcdef0" }
  }
}

override_resource {
  target = aws_iam_role.app
  values = {
    arn = "arn:aws:iam::123456789012:role/cloud-security-lab-app"
  }
}

override_resource {
  target = aws_vpc_endpoint.s3
  values = {
    id             = "vpce-0123456789abcdef0"
    prefix_list_id = "pl-0123456789abcdef0"
  }
}

override_resource {
  target = aws_subnet.public
  values = { id = "subnet-00000000000000001" }
}

override_resource {
  target = aws_subnet.private
  values = { id = "subnet-00000000000000002" }
}

override_resource {
  target = aws_route_table.public
  values = { id = "rtb-00000000000000001" }
}

override_resource {
  target = aws_route_table.private
  values = { id = "rtb-00000000000000002" }
}

variables {
  aws_account_id        = "123456789012"
  documents_bucket_name = "cslab-test-documents-123456789012"
  logs_bucket_name      = "cslab-test-logs-123456789012"
}

run "security_contract" {
  command = apply

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.app.policy).Statement) == 1 &&
      jsondecode(aws_iam_role_policy.app.policy).Statement[0].Effect == "Allow" &&
      toset(jsondecode(aws_iam_role_policy.app.policy).Statement[0].Action) == toset(["s3:GetObject", "s3:PutObject"]) &&
      jsondecode(aws_iam_role_policy.app.policy).Statement[0].Resource == "arn:aws:s3:::cslab-test-documents-123456789012/app/documents/*"
    )
    error_message = "Application grants must contain only GetObject/PutObject within the exact authorized prefix."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role.app.assume_role_policy).Statement) == 1 &&
      jsondecode(aws_iam_role.app.assume_role_policy).Statement[0].Effect == "Allow" &&
      jsondecode(aws_iam_role.app.assume_role_policy).Statement[0].Action == "sts:AssumeRole" &&
      jsondecode(aws_iam_role.app.assume_role_policy).Statement[0].Principal == { Service = "ec2.amazonaws.com" }
    )
    error_message = "The application trust policy must trust only EC2."
  }

  assert {
    condition = (
      aws_subnet.public.cidr_block == "10.42.0.0/24" &&
      aws_subnet.private.cidr_block == "10.42.1.0/24" &&
      !aws_subnet.private.map_public_ip_on_launch &&
      !aws_subnet.public.map_public_ip_on_launch &&
      aws_route_table_association.private.subnet_id == aws_subnet.private.id &&
      aws_route_table_association.private.route_table_id == aws_route_table.private.id &&
      aws_route_table_association.public.subnet_id == aws_subnet.public.id &&
      aws_route_table_association.public.route_table_id == aws_route_table.public.id &&
      aws_route.public_default.route_table_id == aws_route_table.public.id &&
      aws_route.public_default.destination_cidr_block == "0.0.0.0/0" &&
      aws_route.public_default.gateway_id == aws_internet_gateway.lab.id &&
      length(aws_route_table.private.route) == 0 &&
      aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" &&
      aws_vpc_endpoint.s3.service_name == "com.amazonaws.eu-west-1.s3" &&
      toset(aws_vpc_endpoint.s3.route_table_ids) == toset([aws_route_table.private.id])
    )
    error_message = "Only the public table may route to the IGW; S3 must attach only to the private table."
  }

  assert {
    condition = (
      length(aws_security_group.app.ingress) == 0 &&
      length(aws_security_group.app.egress) == 0 &&
      aws_vpc_security_group_egress_rule.s3_https.security_group_id == aws_security_group.app.id &&
      aws_vpc_security_group_egress_rule.s3_https.ip_protocol == "tcp" &&
      aws_vpc_security_group_egress_rule.s3_https.from_port == 443 &&
      aws_vpc_security_group_egress_rule.s3_https.to_port == 443 &&
      aws_vpc_security_group_egress_rule.s3_https.prefix_list_id == aws_vpc_endpoint.s3.prefix_list_id &&
      aws_vpc_security_group_egress_rule.s3_https.cidr_ipv4 == null &&
      aws_vpc_security_group_egress_rule.s3_https.cidr_ipv6 == null
    )
    error_message = "The application SG must have no ingress and only the separate S3 HTTPS egress rule."
  }

  assert {
    condition = (
      length(jsondecode(aws_vpc_endpoint.s3.policy).Statement) == 1 &&
      jsondecode(aws_vpc_endpoint.s3.policy).Statement[0].Effect == "Allow" &&
      toset(jsondecode(aws_vpc_endpoint.s3.policy).Statement[0].Action) == toset(["s3:GetObject", "s3:PutObject"]) &&
      jsondecode(aws_vpc_endpoint.s3.policy).Statement[0].Resource == "arn:aws:s3:::cslab-test-documents-123456789012/app/documents/*" &&
      jsondecode(aws_vpc_endpoint.s3.policy).Statement[0].Condition.ArnEquals["aws:PrincipalArn"] == aws_iam_role.app.arn
    )
    error_message = "The endpoint must restrict actions, prefix and application identity."
  }

  assert {
    condition = alltrue([
      for block in aws_s3_bucket_public_access_block.lab :
      block.block_public_acls && block.block_public_policy && block.ignore_public_acls && block.restrict_public_buckets
    ])
    error_message = "Both buckets require all four public access blocks."
  }

  assert {
    condition = (
      alltrue([for bucket in aws_s3_bucket_versioning.lab : one(bucket.versioning_configuration).status == "Enabled"]) &&
      alltrue([for bucket in aws_s3_bucket_ownership_controls.lab : one(bucket.rule).object_ownership == "BucketOwnerEnforced"]) &&
      alltrue([for bucket in aws_s3_bucket_server_side_encryption_configuration.lab : one(one(bucket.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"]) &&
      !aws_s3_bucket.documents.force_destroy && !aws_s3_bucket.logs.force_destroy
    )
    error_message = "Both buckets require versioning, SSE-S3, disabled ACLs and deliberate emptying."
  }

  assert {
    condition = alltrue([
      for policy in [aws_s3_bucket_policy.documents.policy, aws_s3_bucket_policy.logs.policy] :
      length([for s in jsondecode(policy).Statement : s if s.Sid == "DenyInsecureTransport" && s.Effect == "Deny" && s.Principal == "*" && s.Action == "s3:*" && try(s.Condition.Bool["aws:SecureTransport"], "") == "false" && try(s.Condition.Bool["aws:PrincipalIsAWSService"], "") == "false"]) == 1
    ])
    error_message = "Both policies must deny insecure transport without blocking service delivery."
  }

  assert {
    condition = length([
      for s in jsondecode(aws_s3_bucket_policy.documents.policy).Statement : s
      if s.Sid == "DenyApplicationOutsideEndpoint" && s.Effect == "Deny" && s.Action == "s3:*" &&
      try(s.Condition.ArnEquals["aws:PrincipalArn"], "") == aws_iam_role.app.arn &&
      try(s.Condition.StringNotEquals["aws:SourceVpce"], "") == aws_vpc_endpoint.s3.id &&
      toset(s.Resource) == toset(["arn:aws:s3:::cslab-test-documents-123456789012", "arn:aws:s3:::cslab-test-documents-123456789012/*"])
    ]) == 1
    error_message = "Document access outside the endpoint must be denied specifically to the application role."
  }

  assert {
    condition = length([
      for s in jsondecode(aws_s3_bucket_policy.logs.policy).Statement : s
      if s.Sid == "DenyApplicationAuditAccess" && s.Effect == "Deny" && s.Action == "s3:*" &&
      try(s.Condition.ArnEquals["aws:PrincipalArn"], "") == aws_iam_role.app.arn &&
      try(toset(s.Resource), toset([])) == toset(["arn:aws:s3:::cslab-test-logs-123456789012", "arn:aws:s3:::cslab-test-logs-123456789012/*"])
    ]) == 1
    error_message = "The log bucket and all its objects must explicitly deny application access."
  }

  assert {
    condition = (
      length([for s in jsondecode(aws_s3_bucket_policy.logs.policy).Statement : s if s.Effect == "Allow"]) == 2 &&
      alltrue([
        for s in jsondecode(aws_s3_bucket_policy.logs.policy).Statement :
        try(s.Principal.Service, "") == "cloudtrail.amazonaws.com" &&
        try(s.Condition.StringEquals["aws:SourceArn"], "") == "arn:aws:cloudtrail:eu-west-1:123456789012:trail/cloud-security-lab-audit"
        if s.Effect == "Allow"
      ]) &&
      length([
        for s in jsondecode(aws_s3_bucket_policy.logs.policy).Statement : s
        if s.Sid == "CloudTrailWrite" && s.Action == "s3:PutObject" &&
        s.Resource == "arn:aws:s3:::cslab-test-logs-123456789012/AWSLogs/123456789012/*" &&
        try(s.Condition.StringEquals["s3:x-amz-acl"], "") == "bucket-owner-full-control"
      ]) == 1
    )
    error_message = "Only the named trail may deliver logs into the account-specific prefix."
  }

  assert {
    condition = (
      aws_cloudtrail.lab.enable_logging &&
      aws_cloudtrail.lab.is_multi_region_trail &&
      aws_cloudtrail.lab.include_global_service_events &&
      aws_cloudtrail.lab.enable_log_file_validation &&
      aws_cloudtrail.lab.s3_bucket_name == aws_s3_bucket.logs.id &&
      length(aws_cloudtrail.lab.event_selector) == 1 &&
      one(aws_cloudtrail.lab.event_selector).include_management_events &&
      one(aws_cloudtrail.lab.event_selector).read_write_type == "All" &&
      length(one(aws_cloudtrail.lab.event_selector).data_resource) == 1 &&
      one(one(aws_cloudtrail.lab.event_selector).data_resource).type == "AWS::S3::Object" &&
      toset(one(one(aws_cloudtrail.lab.event_selector).data_resource).values) == toset(["arn:aws:s3:::cslab-test-documents-123456789012/"])
    )
    error_message = "Audit must include global management events and only document-bucket S3 data events, with integrity validation."
  }
}

run "reject_wildcard_prefix" {
  command = plan
  variables { document_prefix = "app/*/" }
  expect_failures = [var.document_prefix]
}

run "reject_empty_prefix" {
  command = plan
  variables { document_prefix = "" }
  expect_failures = [var.document_prefix]
}

run "reject_prefix_without_boundary" {
  command = plan
  variables { document_prefix = "app/documents" }
  expect_failures = [var.document_prefix]
}

run "reject_invalid_account" {
  command = plan
  variables { aws_account_id = "not-an-account" }
  expect_failures = [var.aws_account_id]
}

run "reject_shared_bucket" {
  command = plan
  variables { logs_bucket_name = "cslab-test-documents-123456789012" }
  expect_failures = [aws_s3_bucket.logs]
}

run "reject_invalid_network" {
  command = plan
  variables { vpc_cidr = "10.42.0.0/24" }
  expect_failures = [var.vpc_cidr]
}

run "probes_disabled_by_default" {
  command = apply
  assert {
    condition = (
      length(aws_instance.private_probe) == 0 && length(aws_instance.public_probe) == 0 &&
      length(data.aws_ami.probe) == 0 && length(aws_security_group.public_probe) == 0 &&
      output.probes.private_instance_id == null && output.probes.public_instance_id == null
    )
    error_message = "Default configuration must not launch EC2, public probe networking or AMI queries."
  }
}

run "private_probe_contract" {
  command = apply
  variables {
    enable_probes = true
    probe_ami_id  = "ami-0123456789abcdef0"
    probe_run_id  = "local-mock-only"
  }
  override_resource {
    target = aws_instance.private_probe[0]
    values = { private_ip = "10.42.1.10" }
  }
  assert {
    condition = (
      length(aws_instance.private_probe) == 1 && length(aws_instance.public_probe) == 0 &&
      aws_instance.private_probe[0].ami == "ami-0123456789abcdef0" &&
      aws_instance.private_probe[0].subnet_id == aws_subnet.private.id &&
      !aws_instance.private_probe[0].associate_public_ip_address &&
      toset(aws_instance.private_probe[0].vpc_security_group_ids) == toset([aws_security_group.app.id]) &&
      aws_instance.private_probe[0].iam_instance_profile == aws_iam_instance_profile.app.name &&
      aws_instance.private_probe[0].instance_type == "t3.micro" &&
      one(aws_instance.private_probe[0].credit_specification).cpu_credits == "standard" &&
      one(aws_instance.private_probe[0].metadata_options).http_tokens == "required" &&
      one(aws_instance.private_probe[0].metadata_options).http_put_response_hop_limit == 1 &&
      one(aws_instance.private_probe[0].root_block_device).encrypted &&
      one(aws_instance.private_probe[0].root_block_device).delete_on_termination &&
      one(aws_instance.private_probe[0].root_block_device).volume_size == 8 &&
      aws_instance.private_probe[0].instance_initiated_shutdown_behavior == "stop" &&
      aws_instance.private_probe[0].user_data_replace_on_change &&
      length(aws_instance.private_probe[0].user_data_base64) <= 21844
    )
    error_message = "Private probe must use the app profile, private network, IMDSv2 and encrypted disposable EBS."
  }
}

run "public_probe_contract" {
  command = apply
  variables {
    enable_probes       = true
    enable_public_probe = true
    probe_ami_id        = "ami-0123456789abcdef0"
    probe_run_id        = "local-mock-only"
  }
  override_resource {
    target = aws_instance.private_probe[0]
    values = { private_ip = "10.42.1.10" }
  }
  assert {
    condition = (
      length(aws_instance.public_probe) == 1 &&
      aws_instance.public_probe[0].subnet_id == aws_subnet.public.id &&
      aws_instance.public_probe[0].associate_public_ip_address &&
      aws_instance.public_probe[0].iam_instance_profile == aws_iam_instance_profile.app.name &&
      toset(aws_instance.public_probe[0].vpc_security_group_ids) == toset([aws_security_group.public_probe[0].id]) &&
      length(aws_security_group.public_probe[0].ingress) == 0 &&
      length(aws_security_group.public_probe[0].egress) == 0 &&
      aws_vpc_security_group_egress_rule.public_https[0].cidr_ipv4 == "0.0.0.0/0" &&
      aws_vpc_security_group_egress_rule.public_https[0].from_port == 443 &&
      aws_vpc_security_group_egress_rule.public_https[0].to_port == 443 &&
      aws_vpc_security_group_egress_rule.public_listener[0].cidr_ipv4 == "10.42.1.10/32" &&
      aws_vpc_security_group_egress_rule.public_listener[0].from_port == 8080 &&
      aws_vpc_security_group_egress_rule.public_listener[0].to_port == 8080 &&
      one(aws_instance.public_probe[0].metadata_options).http_tokens == "required" &&
      one(aws_instance.public_probe[0].root_block_device).encrypted &&
      one(aws_instance.public_probe[0].root_block_device).delete_on_termination &&
      one(aws_instance.public_probe[0].credit_specification).cpu_credits == "standard" &&
      length(aws_instance.public_probe[0].user_data_base64) <= 21844
    )
    error_message = "Public comparison must have the same role, no ingress, and bounded egress to the listener."
  }
}

run "reject_unconfigured_probes" {
  command = plan
  variables { enable_probes = true }
  expect_failures = [terraform_data.probe_guard[0]]
}

run "reject_public_without_private" {
  command = plan
  variables { enable_public_probe = true }
  expect_failures = [terraform_data.probe_guard[0]]
}

run "reject_fixture_prefix_collision" {
  command = plan
  variables { document_prefix = "restricted/" }
  expect_failures = [var.document_prefix]
}

run "reject_unsafe_probe_run_id" {
  command = plan
  variables { probe_run_id = "bad';echo injected" }
  expect_failures = [var.probe_run_id]
}
