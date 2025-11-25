# Deployment script for Hybrid DDoS Detection System - Pre-LB Architecture
# PowerShell Version (Windows-compatible)
# 
# Architecture:
#   Internet → ML Gateway (Port 80, Public) → Internal ALB → Webservers (Port 9000, Private)

param(
    [string]$AwsRegion = "us-east-1",
    [string]$ProjectName = "hybrid-ddos-detection",
    [string]$Environment = "production"
)

# Color codes for output
$ColorSuccess = "Green"
$ColorError = "Red"
$ColorWarning = "Yellow"
$ColorInfo = "Cyan"
$ColorDefault = "White"

# Configuration
$TerraformDir = "terraform"
$ModelsDir = "..\models"
$KeyPairName = "$ProjectName-key"

# Helper functions
function Write-Success {
    param([string]$Message)
    Write-Host "[✅ SUCCESS] $Message" -ForegroundColor $ColorSuccess
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[❌ ERROR] $Message" -ForegroundColor $ColorError
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[⚠️  WARNING] $Message" -ForegroundColor $ColorWarning
}

function Write-Info {
    param([string]$Message)
    Write-Host "[ℹ️  INFO] $Message" -ForegroundColor $ColorInfo
}

# Header
Clear-Host
Write-Host "═════════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorInfo
Write-Host "  ML DDoS Detection System - Pre-LB Architecture Deployment" -ForegroundColor $ColorInfo
Write-Host "  PowerShell Version" -ForegroundColor $ColorInfo
Write-Host "═════════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorInfo
Write-Host ""

Write-Info "Starting deployment of Pre-LB ML Gateway Architecture..."
Write-Info "AWS Region: $AwsRegion"
Write-Info "Project: $ProjectName"
Write-Info ""

# Step 1: Check prerequisites
Write-Host "Step 1: Checking Prerequisites..." -ForegroundColor $ColorInfo
Write-Host "────────────────────────────────────────────────────────────────────────" -ForegroundColor $ColorDefault

$PrerequisitesFailed = $false

# Check AWS CLI
if (Get-Command aws -ErrorAction SilentlyContinue) {
    Write-Success "AWS CLI found"
} else {
    Write-Error-Custom "AWS CLI not found. Please install AWS CLI."
    $PrerequisitesFailed = $true
}

# Check Terraform
if (Get-Command terraform -ErrorAction SilentlyContinue) {
    $TerraformVersion = terraform version | Select-Object -First 1
    Write-Success "Terraform found: $TerraformVersion"
} else {
    Write-Error-Custom "Terraform not found. Please install Terraform."
    $PrerequisitesFailed = $true
}

# Check AWS credentials
try {
    $Identity = aws sts get-caller-identity --region $AwsRegion 2>$null | ConvertFrom-Json
    Write-Success "AWS credentials configured (Account: $($Identity.Account))"
} catch {
    Write-Error-Custom "AWS credentials not configured. Please run 'aws configure' first."
    $PrerequisitesFailed = $true
}

if ($PrerequisitesFailed) {
    Write-Error-Custom "Prerequisites check failed. Please fix the issues above."
    exit 1
}

Write-Host ""

# Step 2: Check models
Write-Host "Step 2: Checking Models..." -ForegroundColor $ColorInfo
Write-Host "────────────────────────────────────────────────────────────────────────" -ForegroundColor $ColorDefault

$RequiredModels = @(
    "hybrid_stage1_model_v2.pkl",
    "hybrid_stage1_scaler_v2.pkl",
    "hybrid_stage2_model_v3_real_benign.pkl",
    "hybrid_stage2_scaler_v3_real_benign.pkl"
)

$MissingModels = 0
foreach ($Model in $RequiredModels) {
    $ModelPath = Join-Path $ModelsDir $Model
    if (Test-Path $ModelPath) {
        Write-Success "Found: $Model"
    } else {
        Write-Warning-Custom "Missing: $Model"
        $MissingModels++
    }
}

if ($MissingModels -gt 0) {
    Write-Warning-Custom "$MissingModels models missing. They will be downloaded during initialization."
} else {
    Write-Success "All models found!"
}

Write-Host ""

# Step 3: Create S3 bucket
Write-Host "Step 3: Creating S3 Bucket..." -ForegroundColor $ColorInfo
Write-Host "────────────────────────────────────────────────────────────────────────" -ForegroundColor $ColorDefault

$BucketName = "$ProjectName-models-$(Get-Random -Minimum 10000 -Maximum 99999)"

try {
    $BucketCheck = aws s3 ls "s3://$BucketName" --region $AwsRegion 2>&1
    if ($BucketCheck -match "NoSuchBucket" -or $BucketCheck -match "not exist") {
        # Bucket doesn't exist, create it
        aws s3 mb "s3://$BucketName" --region $AwsRegion 2>$null
        Start-Sleep -Seconds 2
        Write-Success "Created S3 bucket: $BucketName"
    } else {
        Write-Success "S3 bucket ready: $BucketName"
    }
} catch {
    Write-Error-Custom "Failed to create/access S3 bucket: $_"
    exit 1
}

Write-Host ""

# Step 4: Upload models to S3
Write-Host "Step 4: Uploading Models to S3..." -ForegroundColor $ColorInfo
Write-Host "────────────────────────────────────────────────────────────────────────" -ForegroundColor $ColorDefault

foreach ($Model in $RequiredModels) {
    $ModelPath = Join-Path $ModelsDir $Model
    if (Test-Path $ModelPath) {
        try {
            aws s3 cp $ModelPath "s3://$BucketName/" --region $AwsRegion 2>$null
            Write-Success "Uploaded: $Model"
        } catch {
            Write-Warning-Custom "Failed to upload: $Model ($_)"
        }
    }
}

Write-Host ""

# Step 5: Create/verify EC2 key pair
Write-Host "Step 5: Managing EC2 Key Pair..." -ForegroundColor $ColorInfo
Write-Host "────────────────────────────────────────────────────────────────────────" -ForegroundColor $ColorDefault

try {
    $KeyCheck = aws ec2 describe-key-pairs --key-names $KeyPairName --region $AwsRegion 2>&1
    if ($KeyCheck -match "InvalidKeyPair" -or -not $KeyCheck) {
        # Key doesn't exist, create it
        Write-Info "Creating new EC2 key pair..."
        aws ec2 create-key-pair --key-name $KeyPairName --region $AwsRegion --query 'KeyMaterial' --output text | Set-Content "$KeyPairName.pem"
        
        # Adjust permissions (Windows-specific)
        Write-Success "Created key pair: $KeyPairName.pem"
    } else {
        Write-Warning-Custom "Key pair $KeyPairName already exists"
    }
} catch {
    Write-Error-Custom "Failed to manage key pair: $_"
}

Write-Host ""

# Step 6: Prepare Terraform
Write-Host "Step 6: Preparing Terraform..." -ForegroundColor $ColorInfo
Write-Host "────────────────────────────────────────────────────────────────────────" -ForegroundColor $ColorDefault

Push-Location $TerraformDir

# Check if terraform.tfvars exists
if (-not (Test-Path "terraform.tfvars")) {
    Write-Info "Creating terraform.tfvars..."
    
    $TfVarsContent = @"
aws_region              = "$AwsRegion"
project_name            = "$ProjectName"
environment             = "$Environment"
key_pair_name           = "$KeyPairName"

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
"@
    
    $TfVarsContent | Out-File -FilePath "terraform.tfvars" -Encoding UTF8
    Write-Success "Created terraform.tfvars"
} else {
    Write-Info "terraform.tfvars already exists"
}

Write-Host ""

# Step 7: Terraform init
Write-Host "Step 7: Initializing Terraform..." -ForegroundColor $ColorInfo
Write-Host "────────────────────────────────────────────────────────────────────────" -ForegroundColor $ColorDefault

terraform init -upgrade
if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Terraform initialization failed"
    Pop-Location
    exit 1
}
Write-Success "Terraform initialized"
Write-Host ""

# Step 8: Terraform validate
Write-Host "Step 8: Validating Terraform Configuration..." -ForegroundColor $ColorInfo
Write-Host "────────────────────────────────────────────────────────────────────────" -ForegroundColor $ColorDefault

terraform validate
if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Terraform validation failed"
    Pop-Location
    exit 1
}
Write-Success "Terraform configuration is valid"
Write-Host ""

# Step 9: Terraform plan
Write-Host "Step 9: Planning Terraform Deployment..." -ForegroundColor $ColorInfo
Write-Host "────────────────────────────────────────────────────────────────────────" -ForegroundColor $ColorDefault

terraform plan -out=tfplan
if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Terraform plan failed"
    Pop-Location
    exit 1
}
Write-Success "Terraform plan completed"
Write-Host ""

# Step 10: Confirm deployment
Write-Host "Step 10: Confirming Deployment..." -ForegroundColor $ColorWarning
Write-Host "════════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorWarning
Write-Host ""
Write-Host "This will create AWS resources and may incur costs." -ForegroundColor $ColorWarning
Write-Host ""
Write-Host "Resources to be created:" -ForegroundColor $ColorWarning
Write-Host "  • ML Gateway ASG (2-4 instances, t2.medium)" -ForegroundColor $ColorWarning
Write-Host "  • Webserver ASG (2-10 instances, t2.micro)" -ForegroundColor $ColorWarning
Write-Host "  • VPC with public and private subnets" -ForegroundColor $ColorWarning
Write-Host "  • Internal ALB for backend routing" -ForegroundColor $ColorWarning
Write-Host "  • Security groups and network configuration" -ForegroundColor $ColorWarning
Write-Host "  • S3 bucket for model storage" -ForegroundColor $ColorWarning
Write-Host ""
Write-Host "Estimated Monthly Cost: ~\$47.50" -ForegroundColor $ColorWarning
Write-Host ""

$Response = Read-Host "Continue? (yes/no)"

if ($Response -ne "yes") {
    Write-Warning-Custom "Deployment cancelled"
    Remove-Item -Path "tfplan" -Force -ErrorAction SilentlyContinue
    Pop-Location
    exit 0
}

Write-Host ""

# Step 11: Apply Terraform
Write-Host "Step 11: Applying Terraform Configuration..." -ForegroundColor $ColorInfo
Write-Host "════════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorDefault

terraform apply tfplan
if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Terraform apply failed"
    Pop-Location
    exit 1
}

Write-Success "Infrastructure deployed successfully!"
Write-Host ""

# Step 12: Gather outputs
Write-Host "Step 12: Gathering Deployment Outputs..." -ForegroundColor $ColorInfo
Write-Host "────────────────────────────────────────────────────────────────────────" -ForegroundColor $ColorDefault

try {
    $GatewayAsg = terraform output -raw gateway_asg_name 2>$null
    $WebserverAsg = terraform output -raw webserver_asg_name 2>$null
    $BackendAlbDns = terraform output -raw backend_alb_dns 2>$null
    $BackendTgArn = terraform output -raw backend_target_group_arn 2>$null
    $S3Bucket = terraform output -raw s3_bucket_name 2>$null
    $VpcId = terraform output -raw vpc_id 2>$null
    $GatewaySg = terraform output -raw gateway_security_group_id 2>$null
    $WebserverSg = terraform output -raw webserver_security_group_id 2>$null
} catch {
    Write-Warning-Custom "Could not retrieve all outputs"
}

Write-Host ""

# Display results
Write-Host "════════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorSuccess
Write-Host "🚀 DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor $ColorSuccess
Write-Host "════════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorSuccess
Write-Host ""

Write-Host "📋 DEPLOYMENT INFORMATION:" -ForegroundColor $ColorInfo
Write-Host "  Project: $ProjectName"
Write-Host "  Environment: $Environment"
Write-Host "  Region: $AwsRegion"
Write-Host ""

Write-Host "🏗️ INFRASTRUCTURE:" -ForegroundColor $ColorInfo
Write-Host "  Gateway ASG: $GatewayAsg"
Write-Host "  Webserver ASG: $WebserverAsg"
Write-Host "  Backend ALB: $BackendAlbDns"
Write-Host "  VPC ID: $VpcId"
Write-Host ""

Write-Host "🔐 SECURITY:" -ForegroundColor $ColorInfo
Write-Host "  Gateway SG: $GatewaySg"
Write-Host "  Webserver SG: $WebserverSg"
Write-Host "  SSH Key: $KeyPairName.pem"
Write-Host ""

Write-Host "📦 STORAGE:" -ForegroundColor $ColorInfo
Write-Host "  S3 Bucket: $S3Bucket"
Write-Host ""

Write-Host "🌐 ACCESS:" -ForegroundColor $ColorInfo
Write-Host "  Gateway instances automatically deployed in public subnets"
Write-Host "  Webserver instances deployed in private subnets"
Write-Host "  All traffic flows through Gateway for DDoS filtering"
Write-Host ""

Write-Host "⏱️  NEXT STEPS:" -ForegroundColor $ColorWarning
Write-Host "  1. Wait 5-10 minutes for all instances to initialize"
Write-Host "  2. Verify Gateway instances are healthy in AWS Console"
Write-Host "  3. Get gateway public IP:"
Write-Host "     aws ec2 describe-instances --filters Name=tag:Role,Values=Gateway Name=instance-state-name,Values=running --query Reservations[0].Instances[0].PublicIpAddress --output text"
Write-Host "  4. Test gateway health:"
Write-Host "     curl http://<gateway-ip>/health"
Write-Host "  5. Check detection stats:"
Write-Host "     curl http://<gateway-ip>/stats | jq"
Write-Host ""

Write-Host "📊 MONITORING:" -ForegroundColor $ColorWarning
Write-Host "  • CloudWatch metrics available in AWS Console"
Write-Host "  • Gateway logs: /var/log/ml-gateway.log (on gateway instance)"
Write-Host "  • Webapp logs: /var/log/webapp.log (on webserver instance)"
Write-Host "  • System logs: /var/log/user-data.log"
Write-Host ""

Write-Host "════════════════════════════════════════════════════════════════════════" -ForegroundColor $ColorSuccess

# Save deployment info
$DeploymentInfo = @{
    architecture = "pre-lb"
    deployment_timestamp = (Get-Date -Format "o")
    gateway_asg = $GatewayAsg
    webserver_asg = $WebserverAsg
    backend_alb = $BackendAlbDns
    backend_target_group = $BackendTgArn
    s3_bucket = $S3Bucket
    vpc_id = $VpcId
    gateway_security_group = $GatewaySg
    webserver_security_group = $WebserverSg
    key_pair = $KeyPairName
    aws_region = $AwsRegion
    project_name = $ProjectName
    description = "ML Gateway positioned before ALB for traffic filtering"
} | ConvertTo-Json

$DeploymentInfo | Out-File -FilePath "deployment_info_pre_lb.json" -Encoding UTF8

Write-Success "Deployment information saved to deployment_info_pre_lb.json"

# Cleanup
Remove-Item -Path "tfplan" -Force -ErrorAction SilentlyContinue

Write-Info "Deployment script completed!"

Pop-Location

Write-Host ""
    
    Write-Step "Deployment script completed successfully!"
}
catch {
    Write-Error "Failed to get deployment outputs: $_"
    exit 1
}