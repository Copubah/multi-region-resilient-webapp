#!/bin/bash

# Multi-Region Resilient Web Application Deployment Script
# This script automates the deployment of the entire infrastructure

set -e

# Configuration
PROJECT_NAME="resilient-webapp"
PRIMARY_REGION="us-east-1"
SECONDARY_REGION="us-west-2"
DOMAIN_NAME=""
NOTIFICATION_EMAIL=""
AWS_ACCOUNT_ID=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required tools
    for tool in terraform aws docker jq; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Get AWS Account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "Using AWS Account ID: $AWS_ACCOUNT_ID"
    
    success "Prerequisites check passed"
}

# Prompt for configuration
get_configuration() {
    log "Getting deployment configuration..."
    
    if [ -z "$DOMAIN_NAME" ]; then
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
    fi
    
    if [ -z "$NOTIFICATION_EMAIL" ]; then
        read -p "Enter your notification email: " NOTIFICATION_EMAIL
    fi
    
    log "Configuration:"
    log "  Domain: $DOMAIN_NAME"
    log "  Email: $NOTIFICATION_EMAIL"
    log "  Primary Region: $PRIMARY_REGION"
    log "  Secondary Region: $SECONDARY_REGION"
}

# Build and push Docker images
build_and_push_images() {
    log "Building and pushing Docker images..."
    
    cd application/fastapi-app
    
    # Build Docker image
    log "Building Docker image..."
    docker build -t $PROJECT_NAME:latest .
    
    # Create ECR repositories
    log "Creating ECR repositories..."
    
    # Primary region
    aws ecr describe-repositories --repository-names $PROJECT_NAME --region $PRIMARY_REGION &> /dev/null || \
        aws ecr create-repository --repository-name $PROJECT_NAME --region $PRIMARY_REGION
    
    # Secondary region
    aws ecr describe-repositories --repository-names $PROJECT_NAME --region $SECONDARY_REGION &> /dev/null || \
        aws ecr create-repository --repository-name $PROJECT_NAME --region $SECONDARY_REGION
    
    # Push to primary region
    log "Pushing image to primary region ECR..."
    aws ecr get-login-password --region $PRIMARY_REGION | \
        docker login --username AWS --password-stdin \
        $AWS_ACCOUNT_ID.dkr.ecr.$PRIMARY_REGION.amazonaws.com
    
    docker tag $PROJECT_NAME:latest \
        $AWS_ACCOUNT_ID.dkr.ecr.$PRIMARY_REGION.amazonaws.com/$PROJECT_NAME:latest
    docker push $AWS_ACCOUNT_ID.dkr.ecr.$PRIMARY_REGION.amazonaws.com/$PROJECT_NAME:latest
    
    # Push to secondary region
    log "Pushing image to secondary region ECR..."
    aws ecr get-login-password --region $SECONDARY_REGION | \
        docker login --username AWS --password-stdin \
        $AWS_ACCOUNT_ID.dkr.ecr.$SECONDARY_REGION.amazonaws.com
    
    docker tag $PROJECT_NAME:latest \
        $AWS_ACCOUNT_ID.dkr.ecr.$SECONDARY_REGION.amazonaws.com/$PROJECT_NAME:latest
    docker push $AWS_ACCOUNT_ID.dkr.ecr.$SECONDARY_REGION.amazonaws.com/$PROJECT_NAME:latest
    
    cd ../..
    success "Docker images built and pushed successfully"
}

# Create Terraform variable files
create_terraform_vars() {
    log "Creating Terraform variable files..."
    
    # Primary region variables
    cat > terraform/environments/primary/terraform.tfvars << EOF
project_name       = "$PROJECT_NAME"
environment        = "primary"
region             = "$PRIMARY_REGION"
domain_name        = "$DOMAIN_NAME"
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["${PRIMARY_REGION}a", "${PRIMARY_REGION}b", "${PRIMARY_REGION}c"]
container_image    = "$AWS_ACCOUNT_ID.dkr.ecr.$PRIMARY_REGION.amazonaws.com/$PROJECT_NAME:latest"
container_port     = 8000
desired_count      = 2
db_instance_class  = "db.r5.large"
notification_email = "$NOTIFICATION_EMAIL"
EOF
    
    # Secondary region variables
    cat > terraform/environments/secondary/terraform.tfvars << EOF
project_name       = "$PROJECT_NAME"
environment        = "secondary"
region             = "$SECONDARY_REGION"
vpc_cidr           = "10.1.0.0/16"
availability_zones = ["${SECONDARY_REGION}a", "${SECONDARY_REGION}b", "${SECONDARY_REGION}c"]
container_image    = "$AWS_ACCOUNT_ID.dkr.ecr.$SECONDARY_REGION.amazonaws.com/$PROJECT_NAME:latest"
container_port     = 8000
desired_count      = 2
db_instance_class  = "db.r5.large"
notification_email = "$NOTIFICATION_EMAIL"
EOF
    
    success "Terraform variable files created"
}

# Deploy primary region
deploy_primary() {
    log "Deploying primary region infrastructure..."
    
    cd terraform/environments/primary
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    log "Planning primary region deployment..."
    terraform plan -out=tfplan
    
    # Apply deployment
    log "Applying primary region deployment..."
    terraform apply tfplan
    
    # Save outputs
    terraform output -json > ../../../primary-outputs.json
    
    cd ../../..
    success "Primary region deployed successfully"
}

# Deploy secondary region
deploy_secondary() {
    log "Deploying secondary region infrastructure..."
    
    cd terraform/environments/secondary
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    log "Planning secondary region deployment..."
    terraform plan -out=tfplan
    
    # Apply deployment
    log "Applying secondary region deployment..."
    terraform apply tfplan
    
    # Save outputs
    terraform output -json > ../../../secondary-outputs.json
    
    cd ../../..
    success "Secondary region deployed successfully"
}

# Update primary region with cross-region configuration
update_primary() {
    log "Updating primary region with cross-region configuration..."
    
    cd terraform/environments/primary
    
    # Re-apply to update DNS and CDN configurations
    terraform apply -auto-approve
    
    cd ../../..
    success "Primary region updated successfully"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Wait for DNS propagation
    log "Waiting for DNS propagation (this may take a few minutes)..."
    sleep 60
    
    # Test health endpoint
    log "Testing health endpoint..."
    for i in {1..10}; do
        if curl -f -s "https://$DOMAIN_NAME/health" > /dev/null; then
            success "Health endpoint is responding"
            break
        else
            warning "Health endpoint not ready, retrying in 30 seconds... ($i/10)"
            sleep 30
        fi
    done
    
    # Test API endpoints
    log "Testing API endpoints..."
    curl -s "https://$DOMAIN_NAME/api/status" | jq '.'
    
    success "Deployment verification completed"
}

# Display deployment information
display_info() {
    log "Deployment completed successfully!"
    echo
    echo "=== Deployment Information ==="
    echo "Domain: https://$DOMAIN_NAME"
    echo "Health Check: https://$DOMAIN_NAME/health"
    echo "API Status: https://$DOMAIN_NAME/api/status"
    echo
    echo "=== Next Steps ==="
    echo "1. Update your domain's nameservers with the following Route 53 nameservers:"
    
    if [ -f "primary-outputs.json" ]; then
        jq -r '.name_servers.value[]' primary-outputs.json
    fi
    
    echo
    echo "2. Confirm SNS subscription in your email"
    echo "3. Test failover using the guide in docs/failover-testing.md"
    echo "4. Monitor your application using CloudWatch dashboards"
    echo
    echo "=== Useful Commands ==="
    echo "# Check application status"
    echo "curl https://$DOMAIN_NAME/api/status"
    echo
    echo "# Monitor ECS services"
    echo "aws ecs describe-services --cluster $PROJECT_NAME-primary --services $PROJECT_NAME-primary --region $PRIMARY_REGION"
    echo "aws ecs describe-services --cluster $PROJECT_NAME-secondary --services $PROJECT_NAME-secondary --region $SECONDARY_REGION"
    echo
    echo "# Check Route 53 health checks"
    echo "aws route53 list-health-checks"
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -f primary-outputs.json secondary-outputs.json
    rm -f terraform/environments/*/tfplan
}

# Main deployment function
main() {
    log "Starting multi-region resilient web application deployment"
    
    check_prerequisites
    get_configuration
    build_and_push_images
    create_terraform_vars
    deploy_primary
    deploy_secondary
    update_primary
    verify_deployment
    display_info
    cleanup
    
    success "Deployment completed successfully!"
}

# Handle script interruption
trap cleanup EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        --email)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--domain DOMAIN_NAME] [--email EMAIL]"
            echo "  --domain: Your domain name (e.g., example.com)"
            echo "  --email:  Your notification email address"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main