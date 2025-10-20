terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Primary region provider
provider "aws" {
  region = var.region
}

# US East 1 provider for CloudFront certificates
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Random password for database
resource "random_password" "db_password" {
  length  = 16
  special = true
}

# Networking
module "networking" {
  source = "../../modules/networking"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

# Database
module "database" {
  source = "../../modules/database"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.networking.vpc_id
  vpc_cidr_block        = module.networking.vpc_cidr_block
  database_subnet_ids   = module.networking.database_subnet_ids
  db_instance_class     = var.db_instance_class
  master_password       = random_password.db_password.result
  is_primary            = true
}

# Compute
module "compute" {
  source = "../../modules/compute"

  project_name        = var.project_name
  environment         = var.environment
  region              = var.region
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids
  container_image     = var.container_image
  container_port      = var.container_port
  desired_count       = var.desired_count
}

# Storage
module "storage" {
  source = "../../modules/storage"

  project_name              = var.project_name
  environment               = var.environment
  is_primary                = true
  replication_bucket_arn    = data.terraform_remote_state.secondary.outputs.storage_bucket_arn
  cloudfront_distribution_arn = module.cdn.distribution_arn
}

# DNS
module "dns" {
  source = "../../modules/dns"

  project_name             = var.project_name
  domain_name              = var.domain_name
  is_primary               = true
  primary_region           = var.region
  secondary_region         = "us-west-2"
  primary_alb_dns_name     = module.compute.load_balancer_dns_name
  primary_alb_zone_id      = module.compute.load_balancer_zone_id
  secondary_alb_dns_name   = data.terraform_remote_state.secondary.outputs.load_balancer_dns_name
  secondary_alb_zone_id    = data.terraform_remote_state.secondary.outputs.load_balancer_zone_id
}

# CDN
module "cdn" {
  source = "../../modules/cdn"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name             = var.project_name
  domain_name              = var.domain_name
  hosted_zone_id           = module.dns.hosted_zone_id
  primary_s3_bucket_id     = module.storage.bucket_id
  primary_s3_domain_name   = module.storage.bucket_regional_domain_name
  primary_alb_dns_name     = module.compute.load_balancer_dns_name
  secondary_alb_dns_name   = data.terraform_remote_state.secondary.outputs.load_balancer_dns_name
}

# Monitoring
module "monitoring" {
  source = "../../modules/monitoring"

  project_name              = var.project_name
  environment               = var.environment
  region                    = var.region
  notification_email        = var.notification_email
  ecs_cluster_name          = module.compute.ecs_cluster_name
  ecs_service_name          = module.compute.ecs_service_name
  load_balancer_arn_suffix  = split("/", module.compute.load_balancer_arn)[1]
  target_group_arn_suffix   = split("/", module.compute.target_group_arn)[1]
  db_cluster_identifier     = module.database.cluster_identifier
}

# Data source for secondary region state
data "terraform_remote_state" "secondary" {
  backend = "local"

  config = {
    path = "../secondary/terraform.tfstate"
  }
}