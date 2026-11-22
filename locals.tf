locals {
  availability_zone    = coalesce(var.availability_zone, "${var.aws_region}a")
  documents_bucket_arn = "arn:aws:s3:::${var.documents_bucket_name}"
  logs_bucket_arn      = "arn:aws:s3:::${var.logs_bucket_name}"
  document_objects_arn = "${local.documents_bucket_arn}/${var.document_prefix}*"
  trail_name           = "${var.project_name}-audit"
  # Constructing the ARN avoids a cycle between the trail and its delivery policy.
  trail_arn = "arn:aws:cloudtrail:${var.aws_region}:${var.aws_account_id}:trail/${local.trail_name}"
}
