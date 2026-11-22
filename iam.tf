resource "aws_iam_role" "app" {
  name                 = "${var.project_name}-app"
  description          = "Lab application: read and overwrite known document keys only"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EC2Only"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "app" {
  name   = "DocumentAccess"
  role   = aws_iam_role.app.id
  policy = jsonencode(local.application_policy)
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-app"
  role = aws_iam_role.app.name
}

locals {
  application_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadWriteKnownDocuments"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = local.document_objects_arn
    }]
  }

  endpoint_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ApplicationDocumentsOnly"
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:PutObject"]
      Resource  = local.document_objects_arn
      Condition = { ArnEquals = { "aws:PrincipalArn" = aws_iam_role.app.arn } }
    }]
  }
}
