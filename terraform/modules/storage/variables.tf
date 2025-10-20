variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "is_primary" {
  description = "Whether this is the primary region"
  type        = bool
  default     = false
}

variable "replication_bucket_arn" {
  description = "ARN of the bucket to replicate to (for primary region)"
  type        = string
  default     = ""
}

variable "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  type        = string
  default     = ""
}