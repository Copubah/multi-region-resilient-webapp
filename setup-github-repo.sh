#!/bin/bash

# GitHub Repository Setup Script
# This script will create the GitHub repository and push all files

set -e

# Configuration
REPO_NAME="multi-region-resilient-webapp"
DESCRIPTION="Production-ready multi-region resilient web application on AWS with automatic failover, built with Terraform, ECS Fargate, Aurora Global Database, and Route 53"
TOPICS="aws,terraform,multi-region,high-availability,disaster-recovery,ecs-fargate,aurora-global-database,route53,cloudfront,fastapi,infrastructure-as-code,devops,cloud-architecture,resilience,failover,monitoring,production-ready"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if GitHub CLI is installed
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) is not installed."
        echo "Please install it from: https://cli.github.com/"
        echo "Or use the manual method described in the README."
        exit 1
    fi
}

# Check if user is authenticated with GitHub CLI
check_gh_auth() {
    if ! gh auth status &> /dev/null; then
        error "You are not authenticated with GitHub CLI."
        echo "Please run: gh auth login"
        exit 1
    fi
}

# Create GitHub repository
create_repo() {
    log "Creating GitHub repository: $REPO_NAME"
    
    if gh repo view "$REPO_NAME" &> /dev/null; then
        error "Repository $REPO_NAME already exists!"
        read -p "Do you want to continue with the existing repository? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        gh repo create "$REPO_NAME" \
            --public \
            --description "$DESCRIPTION" \
            --clone=false
        
        success "Repository created successfully!"
    fi
}

# Add topics to repository
add_topics() {
    log "Adding topics to repository..."
    
    # Split topics and add them one by one (GitHub CLI limitation)
    IFS=',' read -ra TOPIC_ARRAY <<< "$TOPICS"
    for topic in "${TOPIC_ARRAY[@]}"; do
        gh repo edit "$REPO_NAME" --add-topic "$topic"
    done
    
    success "Topics added successfully!"
}

# Initialize git and push code
setup_git() {
    log "Setting up git repository..."
    
    # Check if git is already initialized
    if [ ! -d ".git" ]; then
        git init
        success "Git repository initialized"
    else
        log "Git repository already exists"
    fi
    
    # Get GitHub username
    GITHUB_USER=$(gh api user --jq .login)
    REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
    
    log "Adding remote origin: $REPO_URL"
    
    # Remove existing origin if it exists
    git remote remove origin 2>/dev/null || true
    git remote add origin "$REPO_URL"
    
    # Add all files
    log "Adding files to git..."
    git add .
    
    # Check if there are changes to commit
    if git diff --staged --quiet; then
        log "No changes to commit"
    else
        log "Committing files..."
        git commit -m "Initial commit: Multi-region resilient web application with automatic failover

Features:
- Multi-region deployment (us-east-1, us-west-2)
- Automatic failover with Route 53 health checks
- ECS Fargate with auto-scaling
- Aurora Global Database with cross-region replication
- S3 cross-region replication for static assets
- CloudFront CDN with origin failover
- Comprehensive monitoring and alerting
- Infrastructure as Code with Terraform
- Automated deployment and testing scripts

Architecture provides 99.99% availability with <5min RTO and <1sec RPO."
        success "Files committed successfully!"
    fi
    
    # Set main branch
    git branch -M main
    
    # Push to GitHub
    log "Pushing to GitHub..."
    git push -u origin main
    
    success "Code pushed to GitHub successfully!"
}

# Display repository information
show_repo_info() {
    GITHUB_USER=$(gh api user --jq .login)
    REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME"
    
    echo
    echo "=========================================="
    echo "Repository Setup Complete!"
    echo "=========================================="
    echo "Repository URL: $REPO_URL"
    echo "Clone URL: $REPO_URL.git"
    echo
    echo "Next steps:"
    echo "1. Visit your repository: $REPO_URL"
    echo "2. Configure AWS credentials for deployment"
    echo "3. Run: ./scripts/deploy.sh --domain your-domain.com --email your-email@example.com"
    echo "4. Test failover: ./scripts/test-failover.sh --domain your-domain.com"
    echo
    echo "Documentation:"
    echo "- Architecture: $REPO_URL/blob/main/docs/architecture.md"
    echo "- Deployment Guide: $REPO_URL/blob/main/docs/deployment-guide.md"
    echo "- Failover Testing: $REPO_URL/blob/main/docs/failover-testing.md"
    echo "- Resilience Explanation: $REPO_URL/blob/main/docs/resilience-explanation.md"
    echo "=========================================="
}

# Main execution
main() {
    log "Starting GitHub repository setup for $REPO_NAME"
    
    check_gh_cli
    check_gh_auth
    create_repo
    add_topics
    setup_git
    show_repo_info
    
    success "GitHub repository setup completed successfully!"
}

# Run main function
main "$@"