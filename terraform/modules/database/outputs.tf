output "cluster_endpoint" {
  description = "RDS cluster endpoint"
  value       = var.is_primary ? aws_rds_cluster.primary[0].endpoint : aws_rds_cluster.secondary[0].endpoint
}

output "cluster_reader_endpoint" {
  description = "RDS cluster reader endpoint"
  value       = var.is_primary ? aws_rds_cluster.primary[0].reader_endpoint : aws_rds_cluster.secondary[0].reader_endpoint
}

output "cluster_identifier" {
  description = "RDS cluster identifier"
  value       = var.is_primary ? aws_rds_cluster.primary[0].cluster_identifier : aws_rds_cluster.secondary[0].cluster_identifier
}

output "cluster_arn" {
  description = "RDS cluster ARN"
  value       = var.is_primary ? aws_rds_cluster.primary[0].arn : aws_rds_cluster.secondary[0].arn
}

output "global_cluster_identifier" {
  description = "Global cluster identifier"
  value       = var.is_primary ? aws_rds_global_cluster.main[0].id : var.global_cluster_identifier
}