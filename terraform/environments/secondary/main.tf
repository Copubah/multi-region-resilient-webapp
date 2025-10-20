terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
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

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.networking.vpc_id
  vpc_cidr_block            = module.networking.vpc_cidr_block
  database_subnet_ids       = module.networking.database_subnet_ids
  db_instance_class         = var.db_instance_class
  master_password           = "dummy-password" # Not used for secondary
  is_primary                = false
  global_cluster_identifier = data.terraform_remote_state.primary.outputs.global_cluster_identifier
  primary_cluster_arn       = data.terraform_remote_state.primary.outputs.primary_cluster_arn
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

  project_name = var.project_name
  environment  = var.environment
  is_primary   = false
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

# Data source for primary region state
data "terraform_remote_state" "primary" {
  backend = "local"

  config = {
    path = "../primary/terraform.tfstate"
  }
}