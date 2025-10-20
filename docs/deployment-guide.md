# Deployment Guide

This guide walks you through deploying the multi-region resilient web application from scratch.

## Prerequisites

### Required Tools
- Terraform >= 1.0
- AWS CLI >= 2.0
- Docker
- Git

### AWS Setup
1. AWS Account: Active AWS account with appropriate permissions
2. IAM User: User with programmatic access and required permissions
3. AWS CLI Configuration: Configured with credentials for both regions

```bash
# Configure AWS CLI
aws configure
# Enter your Access Key ID, Secret Access Key, and default region

# Verify access to both regions
aws sts get-caller-identity --region us-east-1
aws sts get-caller-identity --region us-west-2
```

### Required IAM Permissions
Your AWS user/role needs permissions for:
- EC2 (VPC, Security Groups, Load Balancers)
- ECS (Clusters, Services, Tasks)
- RDS (Aurora Global Database)
- S3 (Buckets, Replication)
- Route 53 (Hosted Zones, Health Checks)
- CloudFront (Distributions)
- CloudWatch (Alarms, Dashboards)
- SNS (Topics, Subscriptions)
- IAM (Roles, Policies)

## Step 1: Prepare the Application

### Build and Push Docker Image

1. Build the FastAPI Application
   ```bash
   cd application/fastapi-app
   
   # Build Docker image
   docker build -t resilient-webapp:latest .
   
   # Test locally
   docker run -p 8000:8000 resilient-webapp:latest
   ```

2. Create ECR Repositories
   ```bash
   # Create ECR repository in primary region
   aws ecr create-repository \
     --repository-name resilient-webapp \
     --region us-east-1
   
   # Create ECR repository in secondary region
   aws ecr create-repository \
     --repository-name resilient-webapp \
     --region us-west-2
   ```

3. Push Images to ECR
   ```bash
   # Get login token for primary region
   aws ecr get-login-password --region us-east-1 | \
     docker login --username AWS --password-stdin \
     YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
   
   # Tag and push to primary region
   docker tag resilient-webapp:latest \
     YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/resilient-webapp:latest
   docker push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/resilient-webapp:latest
   
   # Repeat for secondary region
   aws ecr get-login-password --region us-west-2 | \
     docker login --username AWS --password-stdin \
     YOUR_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com
   
   docker tag resilient-webapp:latest \
     YOUR_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/resilient-webapp:latest
   docker push YOUR_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/resilient-webapp:latest
   ```

## Step 2: Configure Terraform Variables

### Primary Region Configuration
```bash
cd terraform/environments/primary
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
project_name       = "resilient-webapp"
environment        = "primary"
region             = "us-east-1"
domain_name        = "your-domain.com"  # Replace with your domain
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
container_image    = "YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/resilient-webapp:latest"
container_port     = 8000
desired_count      = 2
db_instance_class  = "db.r5.large"
notification_email = "your-email@example.com"  # Replace with your email
```

### Secondary Region Configuration
```bash
cd terraform/environments/secondary
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
project_name       = "resilient-webapp"
environment        = "secondary"
region             = "us-west-2"
vpc_cidr           = "10.1.0.0/16"
availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
container_image    = "YOUR_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/resilient-webapp:latest"
container_port     = 8000
desired_count      = 2
db_instance_class  = "db.r5.large"
notification_email = "your-email@example.com"  # Replace with your email
```

## Step 3: Deploy Infrastructure

### Deploy Primary Region
```bash
cd terraform/environments/primary

# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

Important: Note the outputs from the primary region deployment, especially:
- `global_cluster_identifier`
- `primary_cluster_arn`
- `hosted_zone_id`

### Deploy Secondary Region
```bash
cd terraform/environments/secondary

# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Update Primary Region with Secondary Information
After secondary region deployment, update the primary region to complete cross-region setup:

```bash
cd terraform/environments/primary

# Re-run terraform apply to update DNS and CDN configurations
terraform apply
```

## Step 4: Configure Domain DNS

### Update Domain Name Servers
1. Get the name servers from Terraform output:
   ```bash
   cd terraform/environments/primary
   terraform output name_servers
   ```

2. Update your domain registrar's DNS settings to use the Route 53 name servers.

3. Wait for DNS propagation (can take up to 48 hours, usually much faster).

## Step 5: Verify Deployment

### Test Application Endpoints
```bash
# Test main application
curl https://your-domain.com/

# Test health endpoint
curl https://your-domain.com/health

# Test API endpoints
curl https://your-domain.com/api/status
curl https://your-domain.com/api/data
```

### Verify SSL Certificate
```bash
# Check SSL certificate
openssl s_client -connect your-domain.com:443 -servername your-domain.com
```

### Test Database Connectivity
```bash
# Check database operations
curl -s https://your-domain.com/api/data | jq '.'
```

## Step 6: Configure Monitoring

### Confirm SNS Subscriptions
1. Check your email for SNS subscription confirmations
2. Click the confirmation links to activate alerts

### Verify CloudWatch Dashboards
1. Navigate to CloudWatch in both regions
2. Check that dashboards are created and showing data
3. Verify alarms are in OK state

### Test Alerting
```bash
# Trigger a test alarm by scaling down the service temporarily
aws ecs update-service \
  --cluster resilient-webapp-primary \
  --service resilient-webapp-primary \
  --desired-count 0 \
  --region us-east-1

# Wait for alert, then restore
aws ecs update-service \
  --cluster resilient-webapp-primary \
  --service resilient-webapp-primary \
  --desired-count 2 \
  --region us-east-1
```

## Step 7: Upload Static Assets (Optional)

### Upload Sample Static Files
```bash
# Create sample static files
mkdir -p static-assets
echo "<h1>Welcome to Resilient Web App</h1>" > static-assets/index.html

# Upload to primary S3 bucket
aws s3 cp static-assets/ s3://YOUR_PRIMARY_BUCKET_NAME/ --recursive

# Files will automatically replicate to secondary region
```

## Deployment Validation Checklist

- [ ] Application accessible via domain name
- [ ] SSL certificate valid and trusted
- [ ] Health checks passing in both regions
- [ ] Database connectivity working
- [ ] Static assets loading from CloudFront
- [ ] Route 53 health checks configured
- [ ] CloudWatch alarms created
- [ ] SNS notifications configured
- [ ] Cross-region replication working

## Post-Deployment Tasks

### Security Hardening
1. Review Security Groups: Ensure minimal required access
2. Enable VPC Flow Logs: For network monitoring
3. Configure AWS Config: For compliance monitoring
4. Set up AWS GuardDuty: For threat detection

### Performance Optimization
1. Configure Auto Scaling: Based on your traffic patterns
2. Optimize CloudFront: Cache behaviors and TTLs
3. Database Performance: Monitor and tune queries
4. Cost Optimization: Review resource utilization

### Backup and Recovery
1. Test Database Backups: Verify backup restoration
2. Document Recovery Procedures: Update runbooks
3. Schedule Regular Backups: Automate backup processes

## Troubleshooting Common Issues

### Terraform Deployment Failures

Issue: Resource already exists
```bash
# Import existing resource
terraform import aws_s3_bucket.example bucket-name
```

Issue: Insufficient permissions
```bash
# Check current permissions
aws sts get-caller-identity
aws iam get-user
```

### Application Deployment Issues

Issue: ECS tasks failing to start
```bash
# Check ECS service events
aws ecs describe-services \
  --cluster resilient-webapp-primary \
  --services resilient-webapp-primary

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/ecs/resilient-webapp"
```

Issue: Database connection failures
```bash
# Verify security group rules
aws ec2 describe-security-groups --group-ids YOUR_RDS_SECURITY_GROUP_ID

# Check database status
aws rds describe-db-clusters --db-cluster-identifier resilient-webapp-primary-cluster
```

### DNS and SSL Issues

Issue: SSL certificate not validating
```bash
# Check certificate status
aws acm list-certificates --region us-east-1
aws acm describe-certificate --certificate-arn YOUR_CERT_ARN --region us-east-1
```

Issue: DNS not resolving
```bash
# Check Route 53 configuration
aws route53 list-resource-record-sets --hosted-zone-id YOUR_HOSTED_ZONE_ID
```

## Maintenance and Updates

### Application Updates
1. Build new Docker image with updated code
2. Push to ECR repositories in both regions
3. Update ECS service with new task definition
4. Monitor deployment progress

### Infrastructure Updates
1. Update Terraform configurations
2. Plan changes with `terraform plan`
3. Apply changes with `terraform apply`
4. Verify functionality after updates

### Security Updates
1. Regularly update base Docker images
2. Apply security patches to infrastructure
3. Review and update IAM policies
4. Monitor security advisories

## Cost Management

### Monitor Costs
- Set up billing alerts
- Use AWS Cost Explorer
- Review resource utilization regularly
- Implement cost allocation tags

### Optimize Resources
- Use Spot instances where appropriate
- Implement lifecycle policies for S3
- Review and adjust auto-scaling policies
- Consider Reserved Instances for predictable workloads