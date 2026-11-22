resource "aws_s3_bucket" "documents" {
  bucket        = var.documents_bucket_name
  force_destroy = false
}

resource "aws_s3_bucket" "logs" {
  bucket        = var.logs_bucket_name
  force_destroy = false

  lifecycle {
    precondition {
      condition     = var.logs_bucket_name != var.documents_bucket_name
      error_message = "Documents and audit logs must use distinct buckets."
    }
  }
}

locals {
  buckets = {
    documents = aws_s3_bucket.documents.id
    logs      = aws_s3_bucket.logs.id
  }
}

resource "aws_s3_bucket_public_access_block" "lab" {
  for_each = local.buckets
  bucket   = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "lab" {
  for_each = local.buckets
  bucket   = each.value
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lab" {
  for_each = local.buckets
  bucket   = each.value
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "lab" {
  for_each = local.buckets
  bucket   = each.value
  versioning_configuration {
    status = "Enabled"
  }
}

locals {
  documents_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.documents_bucket_arn, "${local.documents_bucket_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } }
      },
      {
        Sid       = "DenyApplicationOutsideEndpoint"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.documents_bucket_arn, "${local.documents_bucket_arn}/*"]
        Condition = {
          ArnEquals       = { "aws:PrincipalArn" = aws_iam_role.app.arn }
          StringNotEquals = { "aws:SourceVpce" = aws_vpc_endpoint.s3.id }
        }
      }
    ]
  }

  logs_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.logs_bucket_arn, "${local.logs_bucket_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } }
      },
      {
        Sid       = "DenyApplicationAuditAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.logs_bucket_arn, "${local.logs_bucket_arn}/*"]
        Condition = { ArnEquals = { "aws:PrincipalArn" = aws_iam_role.app.arn } }
      },
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = local.logs_bucket_arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn } }
      },
      {
        Sid       = "CloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${local.logs_bucket_arn}/AWSLogs/${var.aws_account_id}/*"
        Condition = { StringEquals = {
          "aws:SourceArn" = local.trail_arn
          "s3:x-amz-acl"  = "bucket-owner-full-control"
        } }
      }
    ]
  }
}

resource "aws_s3_bucket_policy" "documents" {
  bucket = aws_s3_bucket.documents.id
  policy = jsonencode(local.documents_policy)
  depends_on = [
    aws_s3_bucket_public_access_block.lab,
    aws_s3_bucket_ownership_controls.lab,
  ]
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode(local.logs_policy)
  depends_on = [
    aws_s3_bucket_public_access_block.lab,
    aws_s3_bucket_ownership_controls.lab,
  ]
}
