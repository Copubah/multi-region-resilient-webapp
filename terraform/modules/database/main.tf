# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-db-subnet-group"
    Environment = var.environment
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-${var.environment}-rds-"
  vpc_id      = var.vpc_id

  ingress {
    description = "MySQL/Aurora"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-sg"
    Environment = var.environment
  }
}

# RDS Aurora Global Cluster (only create in primary region)
resource "aws_rds_global_cluster" "main" {
  count = var.is_primary ? 1 : 0

  global_cluster_identifier = "${var.project_name}-global-cluster"
  engine                   = "aurora-mysql"
  engine_version           = "8.0.mysql_aurora.3.02.0"
  database_name            = var.database_name
  master_username          = var.master_username
  master_password          = var.master_password
  backup_retention_period  = 7
  preferred_backup_window  = "07:00-09:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  deletion_protection      = false

  lifecycle {
    ignore_changes = [master_password]
  }
}

# Aurora Cluster (Primary)
resource "aws_rds_cluster" "primary" {
  count = var.is_primary ? 1 : 0

  cluster_identifier      = "${var.project_name}-${var.environment}-cluster"
  global_cluster_identifier = aws_rds_global_cluster.main[0].id
  engine                 = "aurora-mysql"
  engine_version         = "8.0.mysql_aurora.3.02.0"
  database_name          = var.database_name
  master_username        = var.master_username
  master_password        = var.master_password
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  deletion_protection    = false

  lifecycle {
    ignore_changes = [master_password]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-cluster"
    Environment = var.environment
  }
}

# Aurora Cluster (Secondary)
resource "aws_rds_cluster" "secondary" {
  count = var.is_primary ? 0 : 1

  cluster_identifier         = "${var.project_name}-${var.environment}-cluster"
  global_cluster_identifier  = var.global_cluster_identifier
  engine                    = "aurora-mysql"
  engine_version            = "8.0.mysql_aurora.3.02.0"
  db_subnet_group_name      = aws_db_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.rds.id]
  skip_final_snapshot       = true
  deletion_protection       = false

  depends_on = [var.primary_cluster_arn]

  tags = {
    Name        = "${var.project_name}-${var.environment}-cluster"
    Environment = var.environment
  }
}

# Aurora Cluster Instances
resource "aws_rds_cluster_instance" "cluster_instances" {
  count = 2

  identifier         = "${var.project_name}-${var.environment}-${count.index}"
  cluster_identifier = var.is_primary ? aws_rds_cluster.primary[0].id : aws_rds_cluster.secondary[0].id
  instance_class     = var.db_instance_class
  engine             = "aurora-mysql"
  engine_version     = "8.0.mysql_aurora.3.02.0"

  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.rds_enhanced_monitoring.arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-instance-${count.index}"
    Environment = var.environment
  }
}

# IAM Role for Enhanced Monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}