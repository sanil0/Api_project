#!/bin/bash

# Deployment script for Hybrid DDoS Detection System - PRE-LB Architecture
# Phase 4: AWS Infrastructure Deployment with Gateway-First Design
#
# Architecture:
#   Internet → ML Gateway (Port 80, Public) → Internal ALB → Webservers (Port 9000, Private)
#
# This script automates the deployment of the new pre-LB architecture

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[✅ SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[⚠️ WARNING]${NC} $1"
}

info() {
    echo -e "${CYAN}[ℹ️ INFO]${NC} $1"
}

# Configuration
PROJECT_NAME="hybrid-ddos-detection"
TERRAFORM_DIR="terraform"
MODELS_DIR="models"
AWS_REGION=${AWS_REGION:-"us-east-1"}

echo
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  ML DDoS Detection System - Pre-LB Architecture Deployment${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo

log "Starting deployment of Pre-LB ML Gateway Architecture..."

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI first."
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    error "Terraform not found. Please install Terraform first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

success "Prerequisites check passed!"

# Display architecture info
echo
info "NEW ARCHITECTURE:"
info "  ┌──────────────────────────────────────────────────────────────┐"
info "  │ Internet → Gateway (Port 80) → Internal ALB → Webservers    │"
info "  │           (Public)                              (Private)    │"
info "  │                                                              │"
info "  │ Benefits:                                                    │"
info "  │  • Single ML model (resource efficient)                      │"
info "  │  • DDoS attacks blocked before reaching backend              │"
info "  │  • Better security posture (webservers isolated)             │"
info "  │  • Cleaner traffic flow                                      │"
info "  └──────────────────────────────────────────────────────────────┘"
echo

# Check if models exist
log "Checking if models exist locally..."
REQUIRED_MODELS=(
    "hybrid_stage1_model_v2.pkl"
    "hybrid_stage1_scaler_v2.pkl"
    "hybrid_stage2_model_v3_real_benign.pkl"
    "hybrid_stage2_scaler_v3_real_benign.pkl"
)

MISSING_MODELS=0
for model in "${REQUIRED_MODELS[@]}"; do
    if [[ -f "$MODELS_DIR/$model" ]]; then
        success "Found: $model"
    else
        warn "Missing model: $model"
        MISSING_MODELS=$((MISSING_MODELS + 1))
    fi
done

if [[ $MISSING_MODELS -gt 0 ]]; then
    warn "Some models are missing. They will be downloaded from S3 during initialization."
fi

# Create S3 bucket for models
log "Creating S3 bucket for model storage..."
BUCKET_NAME="$PROJECT_NAME-models-$(date +%s)"

if aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null || aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
    success "S3 bucket ready: $BUCKET_NAME"
else
    error "Failed to create/access S3 bucket"
    exit 1
fi

# Upload available models to S3
log "Uploading models to S3..."
for model in "${REQUIRED_MODELS[@]}"; do
    if [[ -f "$MODELS_DIR/$model" ]]; then
        if aws s3 cp "$MODELS_DIR/$model" "s3://$BUCKET_NAME/"; then
            success "Uploaded: $model"
        else
            error "Failed to upload: $model"
        fi
    fi
done

# Create EC2 key pair if it doesn't exist
KEY_PAIR_NAME="$PROJECT_NAME-key"
log "Checking for EC2 key pair: $KEY_PAIR_NAME..."

if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" &> /dev/null; then
    log "Creating EC2 key pair..."
    aws ec2 create-key-pair --key-name "$KEY_PAIR_NAME" --region "$AWS_REGION" --query 'KeyMaterial' --output text > "$KEY_PAIR_NAME.pem"
    chmod 600 "$KEY_PAIR_NAME.pem"
    success "Created key pair: $KEY_PAIR_NAME.pem"
else
    warn "Key pair $KEY_PAIR_NAME already exists"
fi

# Prepare Terraform variables
log "Preparing Terraform configuration..."
cd "$TERRAFORM_DIR"

# Create terraform.tfvars if it doesn't exist
if [[ ! -f "terraform.tfvars" ]]; then
    log "Creating terraform.tfvars from template..."
    if [[ -f "terraform.tfvars.example" ]]; then
        cp terraform.tfvars.example terraform.tfvars
    else
        # Create default terraform.tfvars
        cat > terraform.tfvars << EOF
aws_region              = "$AWS_REGION"
project_name            = "$PROJECT_NAME"
environment             = "production"
key_pair_name           = "$KEY_PAIR_NAME"

# Gateway configuration
gateway_instance_type   = "t2.medium"
gateway_min_instances   = 2
gateway_max_instances   = 4
gateway_desired_instances = 2

# Webserver configuration
webserver_instance_type = "t2.micro"
webserver_min_instances = 2
webserver_max_instances = 10
webserver_desired_instances = 3

# Network
vpc_cidr               = "10.0.0.0/16"
public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]
ssh_cidr_blocks       = ["0.0.0.0/0"]
EOF
        success "Created default terraform.tfvars"
    fi
fi

# Initialize Terraform
log "Initializing Terraform..."
if terraform init -upgrade; then
    success "Terraform initialized"
else
    error "Terraform initialization failed"
    exit 1
fi

# Validate Terraform
log "Validating Terraform configuration..."
if terraform validate; then
    success "Terraform configuration is valid"
else
    error "Terraform validation failed"
    exit 1
fi

# Plan Terraform deployment
log "Planning Terraform deployment..."
if terraform plan -out=tfplan; then
    success "Terraform plan completed"
    echo
    info "Review the plan above and confirm to proceed with deployment"
else
    error "Terraform plan failed"
    exit 1
fi

# Apply Terraform deployment
log "Applying Terraform deployment..."
echo
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║ This will create AWS resources and may incur costs.             ║${NC}"
echo -e "${YELLOW}║                                                                ║${NC}"
echo -e "${YELLOW}║ Resources to be created:                                       ║${NC}"
echo -e "${YELLOW}║   • ML Gateway ASG (2-4 instances, t2.medium)                  ║${NC}"
echo -e "${YELLOW}║   • Webserver ASG (2-10 instances, t2.micro)                   ║${NC}"
echo -e "${YELLOW}║   • VPC with public and private subnets                        ║${NC}"
echo -e "${YELLOW}║   • Internal ALB for backend routing                           ║${NC}"
echo -e "${YELLOW}║   • Security groups and network configuration                  ║${NC}"
echo -e "${YELLOW}║   • S3 bucket for model storage                                ║${NC}"
echo -e "${YELLOW}║                                                                ║${NC}"
echo -e "${YELLOW}║ Continue? (yes/no)${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
read -r response
if [[ "$response" == "yes" ]]; then
    if terraform apply tfplan; then
        success "Infrastructure deployed successfully!"
    else
        error "Terraform apply failed"
        exit 1
    fi
else
    warn "Deployment cancelled"
    exit 0
fi

# Get outputs
log "Gathering deployment outputs..."
GATEWAY_ASG=$(terraform output -raw gateway_asg_name 2>/dev/null || echo "N/A")
WEBSERVER_ASG=$(terraform output -raw webserver_asg_name 2>/dev/null || echo "N/A")
BACKEND_ALB_DNS=$(terraform output -raw backend_alb_dns 2>/dev/null || echo "N/A")
BACKEND_TG_ARN=$(terraform output -raw backend_target_group_arn 2>/dev/null || echo "N/A")
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "N/A")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "N/A")
GATEWAY_SG=$(terraform output -raw gateway_security_group_id 2>/dev/null || echo "N/A")
WEBSERVER_SG=$(terraform output -raw webserver_security_group_id 2>/dev/null || echo "N/A")

# Display results
echo
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🚀 DEPLOYMENT COMPLETED SUCCESSFULLY!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════${NC}"
echo
echo -e "${CYAN}📋 DEPLOYMENT INFORMATION:${NC}"
echo "  Project: $PROJECT_NAME"
echo "  Environment: production"
echo "  Region: $AWS_REGION"
echo
echo -e "${CYAN}🏗️ INFRASTRUCTURE:${NC}"
echo "  Gateway ASG: $GATEWAY_ASG"
echo "  Webserver ASG: $WEBSERVER_ASG"
echo "  Backend ALB: $BACKEND_ALB_DNS"
echo "  VPC ID: $VPC_ID"
echo
echo -e "${CYAN}🔐 SECURITY:${NC}"
echo "  Gateway SG: $GATEWAY_SG"
echo "  Webserver SG: $WEBSERVER_SG"
echo "  SSH Key: $KEY_PAIR_NAME.pem"
echo
echo -e "${CYAN}📦 STORAGE:${NC}"
echo "  S3 Bucket: $S3_BUCKET"
echo
echo -e "${CYAN}🌐 ACCESS:${NC}"
echo "  Gateway instances automatically deployed in public subnets"
echo "  Webserver instances deployed in private subnets"
echo "  All traffic flows through Gateway for DDoS filtering"
echo
echo -e "${YELLOW}⏱️  NEXT STEPS:${NC}"
echo "  1. Wait 5-10 minutes for all instances to initialize"
echo "  2. Verify Gateway instances are healthy in AWS Console"
echo "  3. SSH into Gateway: ssh -i $KEY_PAIR_NAME.pem ubuntu@<gateway-public-ip>"
echo "  4. Check logs: tail -f /var/log/user-data.log"
echo "  5. Test gateway health: curl http://<gateway-ip>/health"
echo "  6. Run performance tests from test_gateway.py"
echo
echo -e "${YELLOW}📊 MONITORING:${NC}"
echo "  • CloudWatch metrics available in AWS Console"
echo "  • Gateway logs: /var/log/ml-gateway.log"
echo "  • Webapp logs: /var/log/webapp.log"
echo "  • System logs: /var/log/user-data.log"
echo
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════${NC}"

# Save deployment info
cat > deployment_info_pre_lb.json << EOF
{
  "architecture": "pre-lb",
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "gateway_asg": "$GATEWAY_ASG",
  "webserver_asg": "$WEBSERVER_ASG",
  "backend_alb": "$BACKEND_ALB_DNS",
  "backend_target_group": "$BACKEND_TG_ARN",
  "s3_bucket": "$S3_BUCKET",
  "vpc_id": "$VPC_ID",
  "gateway_security_group": "$GATEWAY_SG",
  "webserver_security_group": "$WEBSERVER_SG",
  "key_pair": "$KEY_PAIR_NAME",
  "aws_region": "$AWS_REGION",
  "project_name": "$PROJECT_NAME",
  "description": "ML Gateway positioned before ALB for traffic filtering"
}
EOF

success "Deployment information saved to deployment_info_pre_lb.json"

# Clean up
rm -f tfplan

log "Deployment script completed!"
echo

# Check if models exist
log "Checking if models exist locally..."
REQUIRED_MODELS=(
    "hybrid_stage1_model_v2.pkl"
    "hybrid_stage1_scaler_v2.pkl"
    "hybrid_stage2_model_v3_real_benign.pkl"
    "hybrid_stage2_scaler_v3_real_benign.pkl"
)

for model in "${REQUIRED_MODELS[@]}"; do
    if [[ -f "$MODELS_DIR/$model" ]]; then
        success "Found: $model"
    else
        error "Missing model: $model"
        error "Please ensure all models are trained and saved in $MODELS_DIR"
        exit 1
    fi
done

# Create S3 bucket for models
log "Creating S3 bucket for model storage..."
BUCKET_NAME="$PROJECT_NAME-models-$(date +%s)"

if aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"; then
    success "Created S3 bucket: $BUCKET_NAME"
else
    error "Failed to create S3 bucket"
    exit 1
fi

# Upload models to S3
log "Uploading models to S3..."
for model in "${REQUIRED_MODELS[@]}"; do
    if aws s3 cp "$MODELS_DIR/$model" "s3://$BUCKET_NAME/"; then
        success "Uploaded: $model"
    else
        error "Failed to upload: $model"
        exit 1
    fi
done

# Create EC2 key pair if it doesn't exist
KEY_PAIR_NAME="$PROJECT_NAME-key"
log "Checking for EC2 key pair: $KEY_PAIR_NAME..."

if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" &> /dev/null; then
    log "Creating EC2 key pair..."
    aws ec2 create-key-pair --key-name "$KEY_PAIR_NAME" --region "$AWS_REGION" --query 'KeyMaterial' --output text > "$KEY_PAIR_NAME.pem"
    chmod 600 "$KEY_PAIR_NAME.pem"
    success "Created key pair: $KEY_PAIR_NAME.pem"
else
    warn "Key pair $KEY_PAIR_NAME already exists"
fi

# Prepare Terraform variables
log "Preparing Terraform configuration..."
cd "$TERRAFORM_DIR"

# Create terraform.tfvars if it doesn't exist
if [[ ! -f "terraform.tfvars" ]]; then
    log "Creating terraform.tfvars from template..."
    cp terraform.tfvars.example terraform.tfvars
    
    # Update key name in terraform.tfvars
    sed -i "s/your-key-pair-name/$KEY_PAIR_NAME/" terraform.tfvars
    
    success "Created terraform.tfvars"
fi

# Initialize Terraform
log "Initializing Terraform..."
if terraform init; then
    success "Terraform initialized"
else
    error "Terraform initialization failed"
    exit 1
fi

# Plan Terraform deployment
log "Planning Terraform deployment..."
if terraform plan -out=tfplan; then
    success "Terraform plan completed"
else
    error "Terraform plan failed"
    exit 1
fi

# Apply Terraform deployment
log "Applying Terraform deployment..."
echo -e "${YELLOW}This will create AWS resources and incur costs. Continue? (y/N)${NC}"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    if terraform apply tfplan; then
        success "Infrastructure deployed successfully!"
    else
        error "Terraform apply failed"
        exit 1
    fi
else
    warn "Deployment cancelled"
    exit 0
fi

# Get outputs
log "Getting deployment outputs..."
LOAD_BALANCER_DNS=$(terraform output -raw load_balancer_dns)
LOAD_BALANCER_URL=$(terraform output -raw load_balancer_url)
S3_BUCKET=$(terraform output -raw s3_bucket_name)
VPC_ID=$(terraform output -raw vpc_id)

# Display results
echo
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🚀 DEPLOYMENT COMPLETED SUCCESSFULLY!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}"
echo
echo -e "${BLUE}Deployment Information:${NC}"
echo "  🌐 Load Balancer URL: $LOAD_BALANCER_URL"
echo "  📊 Load Balancer DNS: $LOAD_BALANCER_DNS"
echo "  🪣 S3 Bucket: $S3_BUCKET"
echo "  🏗️ VPC ID: $VPC_ID"
echo "  🔐 SSH Key: $KEY_PAIR_NAME.pem"
echo
echo -e "${BLUE}API Endpoints:${NC}"
echo "  Health Check: $LOAD_BALANCER_URL/health"
echo "  DDoS Detection: $LOAD_BALANCER_URL/detect"
echo "  System Stats: $LOAD_BALANCER_URL/stats"
echo
echo -e "${BLUE}Testing:${NC}"
echo "  curl $LOAD_BALANCER_URL/health"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Wait 5-10 minutes for instances to fully initialize"
echo "  2. Test the health endpoint"
echo "  3. Run performance tests"
echo "  4. Monitor CloudWatch metrics"
echo
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════════${NC}"

# Save deployment info
cat > deployment_info.json << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "load_balancer_url": "$LOAD_BALANCER_URL",
  "load_balancer_dns": "$LOAD_BALANCER_DNS",
  "s3_bucket": "$S3_BUCKET",
  "vpc_id": "$VPC_ID",
  "key_pair": "$KEY_PAIR_NAME",
  "aws_region": "$AWS_REGION",
  "project_name": "$PROJECT_NAME"
}
EOF

success "Deployment information saved to deployment_info.json"

log "Deployment script completed!"