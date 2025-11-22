# AWS CLI Deployment Guide - DDoS Gateway with FastAPI

This guide provides automated PowerShell commands to deploy the complete infrastructure and application to AWS.

## Prerequisites
- AWS CLI installed and configured with credentials
- PowerShell 5.1 or higher
- Region set to: `us-east-1`
- Ubuntu 22.04 AMI ID: `ami-0c55b159cbfafe1f0` (update if needed for your region)

---

## STEP 1: Create VPC and Network Infrastructure

```powershell
# Create VPC
$VPC = aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=ddos-vpc}]' | ConvertFrom-Json
$VPC_ID = $VPC.Vpc.VpcId
Write-Host "VPC Created: $VPC_ID"

# Create Internet Gateway
$IGW = aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=ddos-igw}]' | ConvertFrom-Json
$IGW_ID = $IGW.InternetGateway.InternetGatewayId
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
Write-Host "IGW Created and attached: $IGW_ID"

# Create Public Subnets for Gateway
$SUBNET1 = aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=gateway-subnet-1}]' | ConvertFrom-Json
$SUBNET1_ID = $SUBNET1.Subnet.SubnetId
Write-Host "Gateway Subnet 1 Created: $SUBNET1_ID"

$SUBNET2 = aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=gateway-subnet-2}]' | ConvertFrom-Json
$SUBNET2_ID = $SUBNET2.Subnet.SubnetId
Write-Host "Gateway Subnet 2 Created: $SUBNET2_ID"

# Create Private Subnets for Webservers (optional)
$SUBNET3 = aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.101.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=webserver-subnet-1}]' | ConvertFrom-Json
$SUBNET3_ID = $SUBNET3.Subnet.SubnetId
Write-Host "Webserver Subnet 1 Created: $SUBNET3_ID"

$SUBNET4 = aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.102.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=webserver-subnet-2}]' | ConvertFrom-Json
$SUBNET4_ID = $SUBNET4.Subnet.SubnetId
Write-Host "Webserver Subnet 2 Created: $SUBNET4_ID"

# Enable public IPs for gateway subnets
aws ec2 modify-subnet-attribute --subnet-id $SUBNET1_ID --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET2_ID --map-public-ip-on-launch

# Create and configure Route Table
$RT = aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=ddos-rt}]' | ConvertFrom-Json
$RT_ID = $RT.RouteTable.RouteTableId
aws ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --subnet-id $SUBNET1_ID --route-table-id $RT_ID
aws ec2 associate-route-table --subnet-id $SUBNET2_ID --route-table-id $RT_ID
Write-Host "Route Table Created and configured: $RT_ID"
```

---

## STEP 2: Create Security Groups

```powershell
# Create Gateway Security Group
$GW_SG = aws ec2 create-security-group --group-name ddos-gateway-sg --description "DDoS Gateway Security Group" --vpc-id $VPC_ID | ConvertFrom-Json
$GW_SG_ID = $GW_SG.GroupId
Write-Host "Gateway SG Created: $GW_SG_ID"

# Add Gateway SG rules
aws ec2 authorize-security-group-ingress --group-id $GW_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $GW_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $GW_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
Write-Host "Gateway SG rules added"

# Create Webserver Security Group
$WEB_SG = aws ec2 create-security-group --group-name ddos-webserver-sg --description "DDoS Webserver Security Group" --vpc-id $VPC_ID | ConvertFrom-Json
$WEB_SG_ID = $WEB_SG.GroupId
Write-Host "Webserver SG Created: $WEB_SG_ID"

# Add Webserver SG rules
aws ec2 authorize-security-group-ingress --group-id $WEB_SG_ID --protocol tcp --port 9000 --source-security-group-id $GW_SG_ID
aws ec2 authorize-security-group-ingress --group-id $WEB_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
Write-Host "Webserver SG rules added"
```

---

## STEP 3: Create Key Pair

```powershell
# Create key pair and save locally
aws ec2 create-key-pair --key-name ddos-key --query 'KeyMaterial' --output text | Out-File -FilePath ddos-key.pem -Encoding ASCII
Write-Host "Key pair created: ddos-key.pem"

# Fix permissions (Windows)
icacls ddos-key.pem /inheritance:r /grant:r "$env:username`:F"
Write-Host "Key permissions fixed"
```

---

## STEP 4: Prepare User Data Script with Application

```powershell
# Save the complete user data script to file
$UserDataScript = @'
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "[START] Gateway initialization"
echo "Timestamp: $(date)"

# Update system
apt-get update -y
apt-get upgrade -y

# Install packages
apt-get install -y python3 python3-pip python3-venv nginx curl wget git

# Create ddos user for running app
useradd -m -s /bin/bash ddos || true

# Setup Python virtual environment for ddos user
su - ddos -c "python3 -m venv ~/venv"
su - ddos -c "~/venv/bin/pip install --upgrade pip"
su - ddos -c "~/venv/bin/pip install fastapi uvicorn httpx"

# Create app directory
mkdir -p /home/ddos/app
cd /home/ddos/app

# Create FastAPI application
cat > /home/ddos/app/main.py << 'PYEOF'
import os
import time
import httpx
from fastapi import FastAPI, Request, Response
from typing import Optional

app = FastAPI(title="DDoS Gateway")
START = time.time()
BLOCKLIST = set()
REQUEST_COUNT = 0
BLOCKED_COUNT = 0

BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:9000")

@app.get("/health")
def health():
    return {
        "status": "ok",
        "uptime_sec": round(time.time() - START, 2),
        "blocked_ips": len(BLOCKLIST),
        "total_requests": REQUEST_COUNT,
        "blocked_requests": BLOCKED_COUNT
    }

@app.get("/stats")
def stats():
    return {
        "total_requests": REQUEST_COUNT,
        "blocked_requests": BLOCKED_COUNT,
        "unique_blocked_ips": len(BLOCKLIST),
        "uptime_minutes": round((time.time() - START) / 60, 2)
    }

@app.middleware("http")
async def simple_gate(req: Request, call_next):
    global REQUEST_COUNT, BLOCKED_COUNT
    REQUEST_COUNT += 1
    
    ip = req.client.host
    if ip in BLOCKLIST:
        BLOCKED_COUNT += 1
        return Response(status_code=403, content="blocked")
    
    response = await call_next(req)
    return response

@app.get("/{path:path}")
@app.post("/{path:path}")
@app.put("/{path:path}")
@app.delete("/{path:path}")
async def proxy(path: str, request: Request):
    """Reverse proxy to backend"""
    try:
        url = f"{BACKEND_URL}/{path}"
        if request.url.query:
            url += f"?{request.url.query}"
        
        async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
            r = await client.request(
                request.method,
                url,
                headers={k: v for k, v in request.headers.items() if k.lower() not in ['host', 'connection']},
                content=await request.body(),
            )
            return Response(
                content=r.content,
                status_code=r.status_code,
                headers=dict(r.headers)
            )
    except httpx.ConnectError:
        return Response(status_code=502, content="backend unavailable")
    except httpx.TimeoutException:
        return Response(status_code=504, content="backend timeout")
    except Exception as e:
        return Response(status_code=500, content=f"error: {str(e)}")
PYEOF

chown ddos:ddos /home/ddos/app/main.py

# Create systemd service for reliable startup and restart
cat > /etc/systemd/system/ddos-gateway.service << 'SVCEOF'
[Unit]
Description=DDoS Gateway API
After=network.target

[Service]
User=ddos
ExecStart=/home/ddos/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
WorkingDirectory=/home/ddos/app
Restart=always
RestartSec=5
Environment="BACKEND_URL=http://localhost:9000"

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now ddos-gateway

# Wait for app to start
sleep 5

# Configure Nginx as reverse proxy on port 80
cat > /etc/nginx/sites-available/ddos << 'NGXEOF'
server {
    listen 80 default_server;
    server_name _;

    # Timeouts to curb slowloris attacks
    client_body_timeout 10s;
    client_header_timeout 10s;
    keepalive_timeout 15s;
    send_timeout 10s;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=reqperip:10m rate=50r/s;
    limit_conn_zone $binary_remote_addr zone=connperip:10m;

    location / {
        limit_req zone=reqperip burst=100 nodelay;
        limit_conn connperip 10;
        
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 15s;
        proxy_connect_timeout 10s;
    }
}
NGXEOF

ln -sf /etc/nginx/sites-available/ddos /etc/nginx/sites-enabled/ddos
rm -f /etc/nginx/sites-enabled/default

# Test Nginx config before restart
nginx -t
systemctl restart nginx

echo "[OK] Gateway initialized successfully"
echo "Timestamp: $(date)"
echo "App running on: http://127.0.0.1:8000"
echo "Nginx reverse proxy: http://0.0.0.0:80"
'@

# Save to file
$UserDataScript | Out-File -FilePath user-data.sh -Encoding ASCII
Write-Host "User data script saved"

# Encode to base64 for AWS CLI
$UserDataBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($UserDataScript))
Write-Host "User data encoded for AWS"
```

---

## STEP 5: Launch Gateway Instances

```powershell
# Launch Gateway Instance 1
$INSTANCE1 = aws ec2 run-instances `
  --image-id ami-0c55b159cbfafe1f0 `
  --instance-type t3.micro `
  --key-name ddos-key `
  --security-group-ids $GW_SG_ID `
  --subnet-id $SUBNET1_ID `
  --user-data $UserDataScript `
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=gateway-1}]' `
  --monitoring Enabled=false | ConvertFrom-Json

$INSTANCE1_ID = $INSTANCE1.Instances[0].InstanceId
Write-Host "Gateway Instance 1 launched: $INSTANCE1_ID"

# Launch Gateway Instance 2
$INSTANCE2 = aws ec2 run-instances `
  --image-id ami-0c55b159cbfafe1f0 `
  --instance-type t3.micro `
  --key-name ddos-key `
  --security-group-ids $GW_SG_ID `
  --subnet-id $SUBNET2_ID `
  --user-data $UserDataScript `
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=gateway-2}]' `
  --monitoring Enabled=false | ConvertFrom-Json

$INSTANCE2_ID = $INSTANCE2.Instances[0].InstanceId
Write-Host "Gateway Instance 2 launched: $INSTANCE2_ID"

# Wait for instances to be running
Write-Host "Waiting for instances to start..."
aws ec2 wait instance-running --instance-ids $INSTANCE1_ID $INSTANCE2_ID

# Get Public IPs
Start-Sleep -Seconds 5
$IP1 = aws ec2 describe-instances --instance-ids $INSTANCE1_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
$IP2 = aws ec2 describe-instances --instance-ids $INSTANCE2_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text

Write-Host "Gateway 1 IP: $IP1"
Write-Host "Gateway 2 IP: $IP2"
Write-Host "Instances launched. Initializing app (wait 5-7 minutes)..."
```

---

## STEP 6: Verify Deployment

```powershell
# Test Health Endpoints (wait 5-7 minutes after launch)
Write-Host "Testing health endpoints..."
Start-Sleep -Seconds 30

$HealthTest1 = curl.exe -s http://$IP1/health
$HealthTest2 = curl.exe -s http://$IP2/health

Write-Host "Gateway 1 /health response:"
Write-Host $HealthTest1

Write-Host "Gateway 2 /health response:"
Write-Host $HealthTest2

# If you see {"status":"ok",...} then deployment succeeded
Write-Host "`nDeployment Status:"
if ($HealthTest1 -like "*ok*") {
    Write-Host "✓ Gateway 1 operational"
} else {
    Write-Host "✗ Gateway 1 not responding - wait a few minutes and try again"
}

if ($HealthTest2 -like "*ok*") {
    Write-Host "✓ Gateway 2 operational"
} else {
    Write-Host "✗ Gateway 2 not responding - wait a few minutes and try again"
}
```

---

## STEP 7: SSH into Instance (For Debugging)

```powershell
# SSH into gateway instance
ssh -i ddos-key.pem ubuntu@$IP1

# Commands to run inside instance:
# Check app status
sudo systemctl status ddos-gateway

# View application logs
sudo journalctl -u ddos-gateway -f

# Verify Nginx is running
sudo systemctl status nginx

# Check if ports are listening
sudo netstat -tlnp | grep -E '8000|80'

# Manually test local endpoint
curl http://localhost:8000/health

# View user-data.log
sudo cat /var/log/user-data.log
```

---

## STEP 8: Optional - Create Internal Load Balancer

```powershell
# Create Target Group for webservers
$TG = aws elbv2 create-target-group `
  --name backend-tg `
  --protocol HTTP `
  --port 9000 `
  --vpc-id $VPC_ID `
  --health-check-path /health `
  --health-check-interval-seconds 30 `
  --health-check-timeout-seconds 5 `
  --healthy-threshold-count 2 `
  --unhealthy-threshold-count 2 | ConvertFrom-Json

$TG_ARN = $TG.TargetGroups[0].TargetGroupArn
Write-Host "Target Group created: $TG_ARN"

# Create Internal ALB
$ALB = aws elbv2 create-load-balancer `
  --name backend-alb `
  --subnets $SUBNET3_ID $SUBNET4_ID `
  --security-groups $WEB_SG_ID `
  --scheme internal | ConvertFrom-Json

$ALB_ARN = $ALB.LoadBalancers[0].LoadBalancerArn
Write-Host "ALB created: $ALB_ARN"

# Create Listener
aws elbv2 create-listener `
  --load-balancer-arn $ALB_ARN `
  --protocol HTTP `
  --port 9000 `
  --default-actions Type=forward,TargetGroupArn=$TG_ARN

Write-Host "ALB listener created"
```

---

## Quick Summary

| Step | Command | Output |
|------|---------|--------|
| 1 | Create VPC + Subnets | VPC_ID, SUBNET1_ID, SUBNET2_ID |
| 2 | Security Groups | GW_SG_ID, WEB_SG_ID |
| 3 | Key Pair | ddos-key.pem file |
| 4 | User Data Script | Complete FastAPI app ready to deploy |
| 5 | Launch Instances | IP1, IP2 (gateway instance IPs) |
| 6 | Verify | curl http://IP1/health → {status:ok} |
| 7 | Debug | SSH and check systemd service logs |
| 8 | ALB (Optional) | Internal load balancer for webservers |

---

## Troubleshooting

**App not responding after 5 minutes?**
```bash
# SSH into instance and check
sudo journalctl -u ddos-gateway -n 50
sudo systemctl restart ddos-gateway
```

**Port 80 returns 502 Bad Gateway?**
```bash
# Uvicorn might be starting up, wait another minute or two
# Then check if process is actually running
ps aux | grep uvicorn
```

**Can't SSH?**
```bash
# Verify security group allows port 22
# Check key pair is in current directory
# Use correct IP address and username (ubuntu)
```

---

Done! Your AWS infrastructure with FastAPI DDoS gateway is deployed and operational.
