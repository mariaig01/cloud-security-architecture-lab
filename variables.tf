variable "aws_account_id" {
  description = "Expected 12-digit AWS account ID. Never put credentials here."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must contain exactly 12 digits."
  }
}

variable "aws_region" {
  description = "Commercial AWS region; both buckets and the S3 endpoint use this region."
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^(af|ap|ca|eu|il|me|mx|sa|us)-(central|east|west|north|south|northeast|northwest|southeast|southwest)-[1-9]$", var.aws_region))
    error_message = "Use a commercial AWS region, for example eu-west-1."
  }
}

variable "availability_zone" {
  description = "Optional existing AZ in aws_region; defaults to the region's a zone."
  type        = string
  default     = null
  nullable    = true
}

variable "project_name" {
  description = "Short prefix for named lab resources."
  type        = string
  default     = "cloud-security-lab"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.project_name))
    error_message = "Use 3-30 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "documents_bucket_name" {
  description = "Globally unique documents bucket name; this lab uses names without dots."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.documents_bucket_name))
    error_message = "Use 3-63 lowercase letters, digits or hyphens, with alphanumeric ends."
  }
}

variable "logs_bucket_name" {
  description = "Globally unique audit bucket name, distinct from the documents bucket."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.logs_bucket_name))
    error_message = "Use 3-63 lowercase letters, digits or hyphens, with alphanumeric ends."
  }
}

variable "document_prefix" {
  description = "Authorized key prefix with a trailing slash; no IAM wildcards or empty segments."
  type        = string
  default     = "app/documents/"

  validation {
    condition = (
      can(regex("^([A-Za-z0-9_-]+/)+$", var.document_prefix)) && length(var.document_prefix) <= 200 &&
      !startswith(var.document_prefix, "restricted/") && !startswith(var.document_prefix, "probe-fixtures/")
    )
    error_message = "Use safe segments ending in / (max 200 characters), outside restricted/ and probe-fixtures/ reserved for negative controls."
  }
}

variable "vpc_cidr" {
  description = "IPv4 /16 VPC network. The lab derives two /24 subnets from it."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && try(cidrnetmask(var.vpc_cidr) == "255.255.0.0", false)
    error_message = "vpc_cidr must be an IPv4 /16 network."
  }
}
