resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-public" }

  lifecycle {
    precondition {
      condition     = startswith(local.availability_zone, var.aws_region)
      error_message = "availability_zone must belong to aws_region."
    }
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-private" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.project_name}-public" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.project_name}-private" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.lab.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  policy            = jsonencode(local.endpoint_policy)
  tags              = { Name = "${var.project_name}-s3" }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app"
  description = "No inbound; HTTPS to regional S3 only. VPC DNS and IMDS have AWS exceptions."
  vpc_id      = aws_vpc.lab.id
  # AWS's default allow-all egress rule is removed by this Terraform resource.
  tags = { Name = "${var.project_name}-app" }
}

resource "aws_vpc_security_group_egress_rule" "s3_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to regional S3 through the private route table"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
}
