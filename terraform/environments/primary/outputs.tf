output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = module.compute.load_balancer_dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = module.compute.load_balancer_zone_id
}

output "database_endpoint" {
  description = "RDS cluster endpoint"
  value       = module.database.cluster_endpoint
  sensitive   = true
}

output "storage_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = module.storage.bucket_arn
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = module.cdn.distribution_id
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = module.cdn.distribution_domain_name
}

output "hosted_zone_id" {
  description = "ID of the Route 53 hosted zone"
  value       = module.dns.hosted_zone_id
}

output "name_servers" {
  description = "Name servers for the hosted zone"
  value       = module.dns.name_servers
}

output "global_cluster_identifier" {
  description = "Global cluster identifier"
  value       = module.database.global_cluster_identifier
}

output "primary_cluster_arn" {
  description = "ARN of the primary cluster"
  value       = module.database.cluster_arn
}