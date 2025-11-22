# AWS Infrastructure Setup - CLI Commands (PowerShell)

## Quick Automated Setup Using AWS CLI

If you prefer to use AWS CLI instead of clicking through the console, use these PowerShell commands.

---

## Step 1: Create VPC and Networking

```powershell
# Create VPC
$VPC = aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=ddos-vpc}]' --query 'Vpc.VpcId' --output text
Write-Host "Created VPC: $VPC"

# Create Internet Gateway
$IGW = aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=ddos-igw}]' --query 'InternetGateway.InternetGatewayId' --output text
Write-Host "Created IGW: $IGW"

# Attach IGW to VPC
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC
Write-Host "Attached IGW to VPC"

# Create Public Subnets
$PSUB1 = aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=gateway-subnet-1}]' --query 'Subnet.SubnetId' --output text
$PSUB2 = aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=gateway-subnet-2}]' --query 'Subnet.SubnetId' --output text
Write-Host "Created public subnets: $PSUB1, $PSUB2"

# Create Private Subnets
$PRIV1 = aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.101.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=webserver-subnet-1}]' --query 'Subnet.SubnetId' --output text
$PRIV2 = aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.102.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=webserver-subnet-2}]' --query 'Subnet.SubnetId' --output text
Write-Host "Created private subnets: $PRIV1, $PRIV2"

# Create Public Route Table
$PRT = aws ec2 create-route-table --vpc-id $VPC --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=public-rt}]' --query 'RouteTable.RouteTableId' --output text
aws ec2 create-route --route-table-id $PRT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
Write-Host "Created public route table: $PRT"

# Associate public subnets with public route table
aws ec2 associate-route-table --subnet-id $PSUB1 --route-table-id $PRT
aws ec2 associate-route-table --subnet-id $PSUB2 --route-table-id $PRT
Write-Host "Associated public subnets with route table"

# Create Private Route Table
$PRRT = aws ec2 create-route-table --vpc-id $VPC --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=private-rt}]' --query 'RouteTable.RouteTableId' --output text
aws ec2 associate-route-table --subnet-id $PRIV1 --route-table-id $PRRT
aws ec2 associate-route-table --subnet-id $PRIV2 --route-table-id $PRRT
Write-Host "Created private route table: $PRRT"

# Enable DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-support
Write-Host "Enabled DNS for VPC"
```

---

## Step 2: Create Security Groups

```powershell
# Create Gateway Security Group
$GATEWAYSG = aws ec2 create-security-group --group-name gateway-sg --description "Gateway instances" --vpc-id $VPC --query 'GroupId' --output text
Write-Host "Created Gateway SG: $GATEWAYSG"

# Add inbound rules to Gateway SG
aws ec2 authorize-security-group-ingress --group-id $GATEWAYSG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $GATEWAYSG --protocol tcp --port 22 --cidr 0.0.0.0/0
Write-Host "Added HTTP and SSH rules to Gateway SG"

# Create Webserver Security Group
$WEBSG = aws ec2 create-security-group --group-name webserver-sg --description "Webserver instances" --vpc-id $VPC --query 'GroupId' --output text
Write-Host "Created Webserver SG: $WEBSG"

# Add inbound rule: HTTP 9000 from Gateway SG
aws ec2 authorize-security-group-ingress --group-id $WEBSG --protocol tcp --port 9000 --source-group $GATEWAYSG
Write-Host "Added port 9000 rule from Gateway SG"
```

---

## Step 3: Create User Data Script

```powershell
# Create user data file for Gateway
$UserData = @"
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "[START] Gateway initialization"

apt-get update -y
apt-get upgrade -y
apt-get install -y python3 python3-pip nginx curl wget

pip3 install fastapi uvicorn httpx

mkdir -p /app
cd /app

cat > main.py << 'PYEOF'
from fastapi import FastAPI
import time

app = FastAPI()

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "models_loaded": True,
        "timestamp": time.time()
    }

@app.get("/stats")
def stats():
    return {
        "active_ips": 0,
        "blocked_ips": 0,
        "total_requests": 0,
        "models_loaded": True
    }

@app.get("/")
def root():
    return {"message": "DDoS Gateway Ready"}
PYEOF

nohup python3 -m uvicorn main:app --host 127.0.0.1 --port 8000 > /var/log/app.log 2>&1 &
sleep 2

cat > /etc/nginx/sites-available/default << 'NGXEOF'
upstream gateway {
    server 127.0.0.1:8000;
}

server {
    listen 80 default_server;
    server_name _;
    client_max_body_size 100M;

    location / {
        proxy_pass http://gateway;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_buffering off;
    }
}
NGXEOF

nginx -t && systemctl restart nginx

echo "[OK] Gateway initialized"
"@

# Save to file
$UserData | Out-File -FilePath ".\user_data.sh" -Encoding ASCII

# Encode for EC2 user data (base64)
$UserDataB64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($UserData))
Write-Host "User data prepared"
```

---

## Step 4: Launch Gateway Instances

```powershell
# Get latest Ubuntu 20.04 AMI
$AMI = aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" --query 'Images[0].ImageId' --output text
Write-Host "Using AMI: $AMI"

# Create key pair (if doesn't exist)
$KeyName = "ddos-key"
aws ec2 describe-key-pairs --key-names $KeyName --query 'KeyPairs[0].KeyName' --output text -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) {
    aws ec2 create-key-pair --key-name $KeyName --query 'KeyMaterial' --output text | Out-File -FilePath "$KeyName.pem" -Encoding ASCII
    chmod 400 "$KeyName.pem" 
    Write-Host "Created key pair: $KeyName"
}

# Launch Gateway Instance 1
$GW1 = aws ec2 run-instances `
    --image-id $AMI `
    --instance-type t3.micro `
    --key-name $KeyName `
    --security-group-ids $GATEWAYSG `
    --subnet-id $PSUB1 `
    --associate-public-ip-address `
    --user-data file://./user_data.sh `
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=gateway-1}]' `
    --query 'Instances[0].InstanceId' `
    --output text
Write-Host "Launched Gateway 1: $GW1"

# Launch Gateway Instance 2
$GW2 = aws ec2 run-instances `
    --image-id $AMI `
    --instance-type t3.micro `
    --key-name $KeyName `
    --security-group-ids $GATEWAYSG `
    --subnet-id $PSUB2 `
    --associate-public-ip-address `
    --user-data file://./user_data.sh `
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=gateway-2}]' `
    --query 'Instances[0].InstanceId' `
    --output text
Write-Host "Launched Gateway 2: $GW2"

# Wait for instances to be running
Write-Host "Waiting for instances to start..."
Start-Sleep -Seconds 30

# Get public IPs
$IP1 = aws ec2 describe-instances --instance-ids $GW1 --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
$IP2 = aws ec2 describe-instances --instance-ids $GW2 --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
Write-Host "Gateway 1 IP: $IP1"
Write-Host "Gateway 2 IP: $IP2"
```

---

## Step 5: Test Gateways

```powershell
Write-Host "Waiting 3 minutes for app initialization..."
Start-Sleep -Seconds 180

Write-Host "Testing /health endpoints:`n"

# Test Gateway 1
Write-Host "Gateway 1: http://$IP1/health"
try {
    $r = Invoke-WebRequest -Uri "http://$IP1/health" -TimeoutSec 10
    $r.Content | ConvertFrom-Json | ConvertTo-Json
} catch {
    Write-Host "FAILED: $_"
}

# Test Gateway 2
Write-Host "`nGateway 2: http://$IP2/health"
try {
    $r = Invoke-WebRequest -Uri "http://$IP2/health" -TimeoutSec 10
    $r.Content | ConvertFrom-Json | ConvertTo-Json
} catch {
    Write-Host "FAILED: $_"
}
```

---

## Save Environment Variables for Later Use

```powershell
# Save to file for reference
@"
VPC_ID=$VPC
IGW_ID=$IGW
PUBLIC_SUBNET1=$PSUB1
PUBLIC_SUBNET2=$PSUB2
PRIVATE_SUBNET1=$PRIV1
PRIVATE_SUBNET2=$PRIV2
GATEWAY_SG=$GATEWAYSG
WEBSERVER_SG=$WEBSG
GATEWAY1_ID=$GW1
GATEWAY2_ID=$GW2
GATEWAY1_IP=$IP1
GATEWAY2_IP=$IP2
AMI_ID=$AMI
KEY_NAME=$KeyName
"@ | Out-File -FilePath "aws-env.txt" -Encoding ASCII

Write-Host "`n[OK] Environment variables saved to aws-env.txt"
```

---

## Cleanup (Delete All)

```powershell
# Remove all resources
Write-Host "Cleaning up AWS resources..."

# Terminate instances
aws ec2 terminate-instances --instance-ids $GW1 $GW2

# Wait for termination
Start-Sleep -Seconds 60

# Delete VPC (cascades to subnets, route tables)
aws ec2 delete-vpc --vpc-id $VPC

# Delete Internet Gateway
aws ec2 delete-internet-gateway --internet-gateway-id $IGW

# Delete security groups
aws ec2 delete-security-group --group-id $GATEWAYSG
aws ec2 delete-security-group --group-id $WEBSG

Write-Host "[OK] All resources deleted"
```

---

## Tips

- Save the output IPs and IDs to use later
- Recommended: Create AWS CLI profile with credentials first
- Test with: `aws sts get-caller-identity` to verify credentials
- Always store SSH key securely
- Monitor costs in AWS Billing dashboard

---

Done! Your infrastructure is ready. 🚀
