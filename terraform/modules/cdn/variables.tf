variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}

variable "primary_s3_bucket_id" {
  description = "ID of the primary S3 bucket"
  type        = string
}

variable "primary_s3_domain_name" {
  description = "Domain name of the primary S3 bucket"
  type        = string
}

variable "primary_alb_dns_name" {
  description = "DNS name of the primary ALB"
  type        = string
}

variable "secondary_alb_dns_name" {
  description = "DNS name of the secondary ALB"
  type        = string
}