# Optional real probes. terraform test always replaces AWS with a mock provider.
variable "enable_probes" {
  description = "Explicit opt-in for the temporary private EC2 probe."
  type        = bool
  default     = false
}

variable "enable_public_probe" {
  description = "Launch the public comparison after collecting the private positive control. Requires enable_probes."
  type        = bool
  default     = false
}

variable "probe_ami_id" {
  description = "Verified regional Amazon Linux 2023 standard x86_64 AMI, pinned by ID."
  type        = string
  default     = null
  validation {
    condition     = var.probe_ami_id == null || can(regex("^ami-[0-9a-f]{17}$", var.probe_ami_id))
    error_message = "Use a pinned ami- ID with 17 hexadecimal digits."
  }
}

variable "probe_run_id" {
  description = "Unique ID for synthetic fixtures and evidence. Keep unchanged when adding the public probe."
  type        = string
  default     = null
  validation {
    condition     = var.probe_run_id == null || can(regex("^[A-Za-z0-9_-]{1,64}$", var.probe_run_id))
    error_message = "Use 1-64 letters, digits, underscores or hyphens."
  }
}

resource "terraform_data" "probe_guard" {
  count = var.enable_probes || var.enable_public_probe ? 1 : 0
  lifecycle {
    precondition {
      condition     = var.enable_probes && var.probe_ami_id != null && var.probe_run_id != null
      error_message = "Probes require enable_probes, a verified probe_ami_id and a unique probe_run_id."
    }
  }
}

data "aws_ami" "probe" {
  count       = var.enable_probes && var.probe_ami_id != null ? 1 : 0
  owners      = ["amazon"]
  most_recent = false
  filter {
    name   = "image-id"
    values = [var.probe_ami_id]
  }
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  depends_on = [terraform_data.probe_guard]
}

locals {
  probe_sources = {
    "probe_common.py"  = filebase64("${path.module}/scripts/probe_common.py")
    "private_probe.py" = filebase64("${path.module}/scripts/private_probe.py")
    "public_probe.py"  = filebase64("${path.module}/scripts/public_probe.py")
  }
  probe_arguments = [
    "--execute", "--region", var.aws_region, "--account-id", var.aws_account_id,
    "--role-name", aws_iam_role.app.name,
    "--documents-bucket", var.documents_bucket_name, "--logs-bucket", var.logs_bucket_name,
    "--prefix", var.document_prefix, "--run-id", coalesce(var.probe_run_id, "disabled"),
  ]
  private_user_data = base64gzip(templatefile("${path.module}/scripts/probe_bootstrap.sh.tftpl", {
    sources   = local.probe_sources
    location  = "private"
    arguments = join(" ", [for value in local.probe_arguments : "'${value}'"])
  }))
  public_user_data = var.enable_probes && var.enable_public_probe ? base64gzip(templatefile("${path.module}/scripts/probe_bootstrap.sh.tftpl", {
    sources  = local.probe_sources
    location = "public"
    arguments = join(" ", [for value in concat(local.probe_arguments, [
      "--private-ip", aws_instance.private_probe[0].private_ip, "--trail-arn", local.trail_arn
    ]) : "'${value}'"])
  })) : null
}

resource "aws_instance" "private_probe" {
  count                       = var.enable_probes ? 1 : 0
  ami                         = try(data.aws_ami.probe[0].id, "ami-00000000000000000")
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  user_data_base64            = local.private_user_data
  user_data_replace_on_change = true
  # A local 30-minute watchdog stops the VM; termination remains an operator step.
  instance_initiated_shutdown_behavior = "stop"
  credit_specification {
    cpu_credits = "standard"
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }
  tags        = { Name = "${var.project_name}-private-probe", ProbeRun = coalesce(var.probe_run_id, "disabled") }
  volume_tags = { Project = var.project_name, Purpose = "SecurityLearning" }
  lifecycle {
    precondition {
      condition     = length(local.private_user_data) <= 21844
      error_message = "Compressed user data exceeds EC2's 16 KiB limit before base64 encoding."
    }
  }
  depends_on = [
    terraform_data.probe_guard, aws_route_table_association.private,
    aws_iam_role_policy.app,
    aws_s3_bucket_policy.documents, aws_cloudtrail.lab,
    aws_vpc_security_group_egress_rule.s3_https,
  ]
}

resource "aws_security_group" "public_probe" {
  count       = var.enable_probes && var.enable_public_probe ? 1 : 0
  name        = "${var.project_name}-public-probe"
  description = "Temporary comparison probe: no ingress, HTTPS and private listener egress only"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.project_name}-public-probe" }
}

resource "aws_vpc_security_group_egress_rule" "public_https" {
  count             = var.enable_probes && var.enable_public_probe ? 1 : 0
  security_group_id = aws_security_group.public_probe[0].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "public_listener" {
  count             = var.enable_probes && var.enable_public_probe ? 1 : 0
  security_group_id = aws_security_group.public_probe[0].id
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = "${aws_instance.private_probe[0].private_ip}/32"
}

resource "aws_instance" "public_probe" {
  count                                = var.enable_probes && var.enable_public_probe ? 1 : 0
  ami                                  = data.aws_ami.probe[0].id
  instance_type                        = "t3.micro"
  subnet_id                            = aws_subnet.public.id
  associate_public_ip_address          = true
  vpc_security_group_ids               = [aws_security_group.public_probe[0].id]
  iam_instance_profile                 = aws_iam_instance_profile.app.name
  user_data_base64                     = local.public_user_data
  user_data_replace_on_change          = true
  instance_initiated_shutdown_behavior = "stop"
  credit_specification {
    cpu_credits = "standard"
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }
  tags        = { Name = "${var.project_name}-public-probe", ProbeRun = coalesce(var.probe_run_id, "disabled") }
  volume_tags = { Project = var.project_name, Purpose = "SecurityLearning" }
  lifecycle {
    precondition {
      condition     = length(local.public_user_data) <= 21844
      error_message = "Compressed user data exceeds EC2's 16 KiB limit before base64 encoding."
    }
  }
  depends_on = [
    aws_route.public_default, aws_route_table_association.public,
    aws_vpc_security_group_egress_rule.public_https,
    aws_vpc_security_group_egress_rule.public_listener,
  ]
}

output "probes" {
  description = "Temporary probes, absent by default. Collect complete console summaries before termination."
  value = {
    private_instance_id = try(aws_instance.private_probe[0].id, null)
    public_instance_id  = try(aws_instance.public_probe[0].id, null)
    private_ip          = try(aws_instance.private_probe[0].private_ip, null)
    run_id              = var.probe_run_id
  }
}
