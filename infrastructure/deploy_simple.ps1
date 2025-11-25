# PowerShell Deployment Script for Hybrid DDoS Detection System
# Phase 3: AWS Infrastructure Deployment

param(
    [string]$AwsRegion = "us-east-1",
    [switch]$SkipConfirmation
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ">> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "SUCCESS: $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "WARNING: $Message" -ForegroundColor Yellow
}

# Configuration
$ProjectName = "hybrid-ddos-detection"
$TerraformDir = "terraform"
$ModelsDir = "..\models"

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "DEPLOYING HYBRID DDOS DETECTION SYSTEM TO AWS" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Step "Starting deployment of Hybrid DDoS Detection System..."

# Check prerequisites
Write-Step "Checking prerequisites..."

# Check if AWS CLI is installed
try {
    $awsVersion = aws --version 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI not found"
    }
    Write-Success "AWS CLI found: $($awsVersion.Split(' ')[0])"
}
catch {
    Write-Error "AWS CLI not found. Please install AWS CLI first."
    Write-Host "Download from: https://aws.amazon.com/cli/"
    exit 1
}

# Check if Terraform is installed
try {
    $terraformVersion = terraform version 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform not found"
    }
    Write-Success "Terraform found: $($terraformVersion[0])"
}
catch {
    Write-Error "Terraform not found. Please install Terraform first."
    Write-Host "Download from: https://www.terraform.io/downloads.html"
    exit 1
}

# Check AWS credentials
Write-Step "Checking AWS credentials..."
try {
    $callerIdentity = aws sts get-caller-identity 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "AWS credentials not configured"
    }
    Write-Success "AWS credentials configured for: $($callerIdentity.Arn)"
}
catch {
    Write-Error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
}

# Check if models exist
Write-Step "Checking if models exist locally..."
$RequiredModels = @(
    "hybrid_stage1_model_v2.pkl",
    "hybrid_stage1_scaler_v2.pkl",
    "hybrid_stage2_model_v3_real_benign.pkl",
    "hybrid_stage2_scaler_v3_real_benign.pkl"
)

foreach ($model in $RequiredModels) {
    $modelPath = Join-Path $ModelsDir $model
    if (Test-Path $modelPath) {
        Write-Success "Found: $model"
    }
    else {
        Write-Error "Missing model: $model"
        Write-Error "Please ensure all models are trained and saved in $ModelsDir"
        exit 1
    }
}

# Create S3 bucket for models
Write-Step "Creating S3 bucket for model storage..."
$timestamp = [int]((Get-Date).ToUniversalTime() - (Get-Date "1970-01-01")).TotalSeconds
$BucketName = "$ProjectName-models-$timestamp"

try {
    aws s3 mb "s3://$BucketName" --region $AwsRegion 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create S3 bucket"
    }
    Write-Success "Created S3 bucket: $BucketName"
}
catch {
    Write-Error "Failed to create S3 bucket: $_"
    exit 1
}

# Upload models to S3
Write-Step "Uploading models to S3..."
foreach ($model in $RequiredModels) {
    $modelPath = Join-Path $ModelsDir $model
    try {
        aws s3 cp $modelPath "s3://$BucketName/" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to upload $model"
        }
        Write-Success "Uploaded: $model"
    }
    catch {
        Write-Error "Failed to upload: $model"
        exit 1
    }
}

# Create EC2 key pair if it doesn't exist
$KeyPairName = "$ProjectName-key"
Write-Step "Checking for EC2 key pair: $KeyPairName..."

try {
    $keyExists = aws ec2 describe-key-pairs --key-names $KeyPairName --region $AwsRegion --output text 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Warning "Key pair $KeyPairName already exists"
    }
    else {
        Write-Step "Creating EC2 key pair..."
        $keyMaterial = aws ec2 create-key-pair --key-name $KeyPairName --region $AwsRegion --query 'KeyMaterial' --output text
        if ($LASTEXITCODE -eq 0) {
            $keyMaterial | Out-File -FilePath "$KeyPairName.pem" -Encoding ASCII
            Write-Success "Created key pair: $KeyPairName.pem"
        }
        else {
            throw "Failed to create key pair"
        }
    }
}
catch {
    Write-Error "Error with key pair: $($_.Exception.Message)"
    exit 1
}

# Prepare Terraform configuration
Write-Step "Preparing Terraform configuration..."
Set-Location $TerraformDir

# Create terraform.tfvars if it doesn't exist
if (-not (Test-Path "terraform.tfvars")) {
    Write-Step "Creating terraform.tfvars from template..."
    Copy-Item "terraform.tfvars.example" "terraform.tfvars"
    
    # Update key name and S3 bucket in terraform.tfvars
    $content = Get-Content "terraform.tfvars"
    $content = $content -replace 'your-key-pair-name', $KeyPairName
    $content = $content -replace 'us-east-1', $AwsRegion
    
    # Add S3 bucket name to terraform.tfvars
    $content += ""
    $content += "# S3 Configuration"
    $content += "s3_bucket_models = `"$BucketName`""
    
    $content | Set-Content "terraform.tfvars"
    
    Write-Success "Created terraform.tfvars with S3 bucket: $BucketName"
}

# Initialize Terraform
Write-Step "Initializing Terraform..."
try {
    terraform init
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform initialization failed"
    }
    Write-Success "Terraform initialized"
}
catch {
    Write-Error "Terraform initialization failed: $_"
    exit 1
}

# Plan Terraform deployment
Write-Step "Planning Terraform deployment..."
try {
    terraform plan -out=tfplan
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform plan failed"
    }
    Write-Success "Terraform plan completed"
}
catch {
    Write-Error "Terraform plan failed: $_"
    exit 1
}

# Confirm deployment
if (-not $SkipConfirmation) {
    Write-Host ""
    Write-Warning "This will create AWS resources and incur costs!"
    Write-Host "Resources to be created:"
    Write-Host "  - VPC with public/private subnets"
    Write-Host "  - Application Load Balancer"
    Write-Host "  - Auto Scaling Group (2-10 instances)"
    Write-Host "  - S3 bucket for models"
    Write-Host "  - CloudWatch monitoring"
    Write-Host ""
    
    $response = Read-Host "Continue with deployment? (y/N)"
    if ($response -notmatch "^[Yy]$") {
        Write-Warning "Deployment cancelled"
        exit 0
    }
}

# Apply Terraform deployment
Write-Step "Applying Terraform deployment..."
try {
    terraform apply tfplan
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform apply failed"
    }
    Write-Success "Infrastructure deployed successfully!"
}
catch {
    Write-Error "Terraform apply failed: $_"
    exit 1
}

# Get outputs
Write-Step "Getting deployment outputs..."
try {
    $LoadBalancerDns = terraform output -raw load_balancer_dns
    $LoadBalancerUrl = terraform output -raw load_balancer_url
    $S3Bucket = terraform output -raw s3_bucket_name
    $VpcId = terraform output -raw vpc_id
    
    # Display results
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host "DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Deployment Information:" -ForegroundColor Cyan
    Write-Host "  Load Balancer URL: $LoadBalancerUrl"
    Write-Host "  Load Balancer DNS: $LoadBalancerDns"
    Write-Host "  S3 Bucket: $S3Bucket"
    Write-Host "  VPC ID: $VpcId"
    Write-Host "  SSH Key: $KeyPairName.pem"
    Write-Host ""
    
    Write-Host "API Endpoints:" -ForegroundColor Cyan
    Write-Host "  Health Check: $LoadBalancerUrl/health"
    Write-Host "  DDoS Detection: $LoadBalancerUrl/detect"
    Write-Host "  System Stats: $LoadBalancerUrl/stats"
    Write-Host ""
    
    Write-Host "Testing:" -ForegroundColor Cyan
    Write-Host "  Invoke-RestMethod -Uri $LoadBalancerUrl/health"
    Write-Host ""
    
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Wait 5-10 minutes for instances to fully initialize"
    Write-Host "  2. Test the health endpoint"
    Write-Host "  3. Run performance tests with test_deployment.py"
    Write-Host "  4. Monitor CloudWatch metrics"
    Write-Host ""
    
    Write-Host "================================================================================" -ForegroundColor Green
    
    # Save deployment info
    $deploymentInfo = @{
        deployment_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        load_balancer_url = $LoadBalancerUrl
        load_balancer_dns = $LoadBalancerDns
        s3_bucket = $S3Bucket
        vpc_id = $VpcId
        key_pair = $KeyPairName
        aws_region = $AwsRegion
        project_name = $ProjectName
    }
    
    $deploymentInfo | ConvertTo-Json -Depth 3 | Out-File "deployment_info.json" -Encoding UTF8
    Write-Success "Deployment information saved to deployment_info.json"
    
    Write-Step "Deployment script completed successfully!"
}
catch {
    Write-Error "Failed to get deployment outputs: $_"
    exit 1
}