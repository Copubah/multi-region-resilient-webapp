variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "database_subnet_ids" {
  description = "IDs of the database subnets"
  type        = list(string)
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "webapp"
}

variable "master_username" {
  description = "Master username for the database"
  type        = string
  default     = "admin"
}

variable "master_password" {
  description = "Master password for the database"
  type        = string
  sensitive   = true
}

variable "is_primary" {
  description = "Whether this is the primary region"
  type        = bool
  default     = false
}

variable "global_cluster_identifier" {
  description = "Global cluster identifier (for secondary regions)"
  type        = string
  default     = ""
}

variable "primary_cluster_arn" {
  description = "ARN of the primary cluster (for secondary regions)"
  type        = string
  default     = ""
}