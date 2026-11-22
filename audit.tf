resource "aws_cloudtrail" "lab" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  enable_logging                = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  event_selector {
    include_management_events = true
    read_write_type           = "All"

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${local.documents_bucket_arn}/"]
    }
  }

  depends_on = [
    aws_s3_bucket_policy.logs,
    aws_s3_bucket_server_side_encryption_configuration.lab,
    aws_s3_bucket_versioning.lab,
  ]
}
