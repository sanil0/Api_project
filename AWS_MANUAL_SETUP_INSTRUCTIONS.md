# AWS Manual Infrastructure Setup - DDoS Detection Gateway

## Architecture Overview
- **Pre-LB Architecture**: Internet → ML Gateway (Port 80) → Internal ALB → Webservers (Port 9000)
- **Region**: us-east-1
- **Instance Type**: t3.micro (Free Tier eligible)

---

## STEP 1: Create VPC and Networking

### 1.1 Create VPC
- Navigate to: **VPC Dashboard → Your VPCs**
- Click: **Create VPC**
- Settings:
  - Name: `ddos-vpc`
  - IPv4 CIDR: `10.0.0.0/16`
  - Click: **Create**

### 1.2 Create Internet Gateway
- Navigate to: **VPC Dashboard → Internet Gateways**
- Click: **Create Internet Gateway**
- Settings:
  - Name: `ddos-igw`
  - Click: **Create**
- Select created IGW, click: **Attach to VPC**
- Choose: `ddos-vpc`

### 1.3 Create Public Subnets (for Gateway instances)
- Navigate to: **VPC Dashboard → Subnets**
- Click: **Create Subnet**

**Subnet 1:**
- VPC: `ddos-vpc`
- Name: `gateway-subnet-1`
- Availability Zone: `us-east-1a`
- IPv4 CIDR: `10.0.1.0/24`
- Click: **Create**

**Subnet 2:**
- VPC: `ddos-vpc`
- Name: `gateway-subnet-2`
- Availability Zone: `us-east-1b`
- IPv4 CIDR: `10.0.2.0/24`
- Click: **Create**

### 1.4 Configure Public Route Table
- Navigate to: **VPC Dashboard → Route Tables**
- Click: **Create Route Table**
- Settings:
  - Name: `public-rt`
  - VPC: `ddos-vpc`
  - Click: **Create**

- Select the route table, click: **Edit Routes**
- Click: **Add Route**
  - Destination: `0.0.0.0/0`
  - Target: Select **Internet Gateway** → `ddos-igw`
  - Click: **Save**

- Click: **Subnet Associations** tab
- Click: **Edit Subnet Associations**
- Select both `gateway-subnet-1` and `gateway-subnet-2`
- Click: **Save**

### 1.5 Create Private Subnets (for Webserver instances)
**Subnet 1:**
- VPC: `ddos-vpc`
- Name: `webserver-subnet-1`
- Availability Zone: `us-east-1a`
- IPv4 CIDR: `10.0.101.0/24`
- Click: **Create**

**Subnet 2:**
- VPC: `ddos-vpc`
- Name: `webserver-subnet-2`
- Availability Zone: `us-east-1b`
- IPv4 CIDR: `10.0.102.0/24`
- Click: **Create**

### 1.6 Create Private Route Table (no internet access)
- Click: **Create Route Table**
- Settings:
  - Name: `private-rt`
  - VPC: `ddos-vpc`
- Click: **Subnet Associations** → **Edit Subnet Associations**
- Select `webserver-subnet-1` and `webserver-subnet-2`
- Click: **Save**

---

## STEP 2: Create Security Groups

### 2.1 Gateway Security Group
- Navigate to: **EC2 Dashboard → Security Groups**
- Click: **Create Security Group**
- Settings:
  - Name: `gateway-sg`
  - VPC: `ddos-vpc`
  - Description: "Gateway instances - Pre-LB DDoS detection"

- **Inbound Rules:**
  1. HTTP from Anywhere
     - Type: HTTP
     - Protocol: TCP
     - Port: 80
     - Source: `0.0.0.0/0`
  
  2. SSH from Anywhere
     - Type: SSH
     - Protocol: TCP
     - Port: 22
     - Source: `0.0.0.0/0`

- Click: **Create Security Group**

### 2.2 Webserver Security Group
- Click: **Create Security Group**
- Settings:
  - Name: `webserver-sg`
  - VPC: `ddos-vpc`
  - Description: "Backend webservers"

- **Inbound Rules:**
  1. HTTP from Gateway SG
     - Type: HTTP
     - Protocol: TCP
     - Port: 9000
     - Source: Custom → Search for `gateway-sg` → select it

- Click: **Create Security Group**

---

## STEP 3: Launch Gateway Instances

### 3.1 Launch Gateway Instance 1
- Navigate to: **EC2 Dashboard → Instances**
- Click: **Launch Instance**

**Basic Details:**
- Name: `gateway-1`
- AMI: Ubuntu 20.04 LTS (ami-0c55b159cbfafe1f0 or search for latest)
- Instance Type: `t3.micro`
- Key Pair: Create new or select existing
  - If new: Name `ddos-key`, download `.pem` file, save securely

**Network Settings:**
- VPC: `ddos-vpc`
- Subnet: `gateway-subnet-1` (us-east-1a)
- Auto-assign public IP: **Enable**
- Security Group: `gateway-sg`

**Advanced Details → User Data:**
Copy and paste this script:
```bash
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

# Create FastAPI application with complete feature set
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

    # Rate limiting - adjust based on expected load
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
```

- Click: **Launch Instance**

### 3.2 Launch Gateway Instance 2
- Repeat same process
- Name: `gateway-2`
- Subnet: `gateway-subnet-2` (us-east-1b)
- Use same user data script
- Same security group and key pair

---

## STEP 4: Verify Gateway Instances

### 4.1 Get Public IPs
- Navigate to: **EC2 Dashboard → Instances**
- Wait for both instances to show "Running"
- Note the **Public IPv4 addresses** for both

### 4.2 Test Health Endpoints
Wait 3-5 minutes for initialization (pip install, venv setup, systemd service startup), then test:

```bash
# Replace with your actual IPs
curl http://GATEWAY1_IP/health
curl http://GATEWAY2_IP/health
curl http://GATEWAY1_IP/stats
```

**Expected Response:**
```json
{
    "status": "ok",
    "uptime_sec": 245.67,
    "blocked_ips": 0,
    "total_requests": 0,
    "blocked_requests": 0
}
```

### 4.3 Debug Connection Issues

**SSH into gateway instance:**
```bash
ssh -i ddos-key.pem ubuntu@GATEWAY_IP

# Check if FastAPI is running
ps aux | grep uvicorn

# Check systemd service status
sudo systemctl status ddos-gateway

# View application logs
sudo journalctl -u ddos-gateway -f

# Test localhost connection
curl http://localhost:8000/health

# Check Nginx status
sudo systemctl status nginx

# View Nginx error log
sudo tail -f /var/log/nginx/error.log

# Verify port 8000 is listening
sudo netstat -tlnp | grep 8000
```

---

## STEP 5: Create Internal Load Balancer (Optional - for future webserver routing)

### 5.1 Create Target Group
- Navigate to: **EC2 Dashboard → Target Groups**
- Click: **Create Target Group**
- Settings:
  - Name: `backend-tg`
  - Protocol: HTTP
  - Port: 9000
  - VPC: `ddos-vpc`
  - Health Check Path: `/health`
  - Click: **Create**

### 5.2 Create Internal ALB
- Navigate to: **EC2 Dashboard → Load Balancers**
- Click: **Create Load Balancer** → **Application Load Balancer**
- Settings:
  - Name: `backend-alb`
  - Scheme: **Internal**
  - VPC: `ddos-vpc`
  - Subnets: Select `webserver-subnet-1` and `webserver-subnet-2`
  - Security Group: `webserver-sg`

- **Listener:**
  - Protocol: HTTP
  - Port: 9000
  - Forward to: `backend-tg`

- Click: **Create**

---

## STEP 6: Launch Webserver Instances (Optional - for future use)

### 6.1 Launch Webserver Instance 1
- Navigate to: **EC2 Dashboard → Instances → Launch Instance**

**Basic Details:**
- Name: `webserver-1`
- AMI: Ubuntu 20.04 LTS
- Instance Type: `t3.micro`
- Key Pair: `ddos-key`

**Network Settings:**
- VPC: `ddos-vpc`
- Subnet: `webserver-subnet-1`
- Auto-assign public IP: **Disable** (private only)
- Security Group: `webserver-sg`

**User Data:**
```bash
#!/bin/bash
apt-get update -y
apt-get install -y python3 python3-pip
pip3 install fastapi uvicorn

mkdir -p /app
cd /app

cat > main.py << 'PYEOF'
from fastapi import FastAPI
app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/")
def root():
    return {"message": "Backend server ready"}
PYEOF

python3 -m uvicorn main:app --host 0.0.0.0 --port 9000 &
```

- Click: **Launch**

### 6.2 Register Webserver with Target Group
- Go to **Target Groups → backend-tg**
- Click: **Register Targets**
- Select `webserver-1`
- Port: `9000`
- Click: **Register as Pending Below**

---

## TESTING

### Test Gateway /health endpoint
```bash
curl http://GATEWAY_IP/health
```

### Test Gateway /stats endpoint
```bash
curl http://GATEWAY_IP/stats
```

### SSH into Gateway Instance
```bash
ssh -i ddos-key.pem ubuntu@GATEWAY_IP
# Check logs
tail -f /var/log/app.log
tail -f /var/log/nginx/error.log
```

---

## CLEANUP (When Done)

### Delete Resources in Order:
1. **Instances**: Select all → Instance State → Terminate
2. **Load Balancers**: Delete ALB and target groups
3. **Security Groups**: Delete all custom SGs
4. **Subnets**: Delete all subnets
5. **Route Tables**: Delete custom route tables
6. **Internet Gateway**: Detach from VPC, then delete
7. **VPC**: Delete VPC (will cascade delete associated resources)

---

## KEY POINTS

✅ **Ports:**
- Gateway: Port 80 (public)
- Internal ALB: Port 9000 (private)
- Webservers: Port 9000 (private)

✅ **Networking:**
- Gateway instances in public subnets (have internet access)
- Webserver instances in private subnets (no internet)
- Security groups control inter-subnet communication

✅ **Free Tier:**
- t3.micro instances qualify for Free Tier
- Monitor your account to avoid charges

✅ **Monitoring:**
- Check CloudWatch metrics
- Monitor instance CPU, network, disk usage
- Set up alarms for auto-scaling

---

## TROUBLESHOOTING

**Port 80 returns 502/503 error?**
- App is still initializing, wait 3-5 minutes
- SSH and check: `sudo systemctl status ddos-gateway`
- View logs: `sudo journalctl -u ddos-gateway -n 50`
- Restart service: `sudo systemctl restart ddos-gateway`

**Port 80 not responding at all?**
- Verify security group allows port 80: Check in AWS Console
- Verify Nginx is running: `sudo systemctl status nginx`
- Check Nginx config: `sudo nginx -t`
- View Nginx errors: `sudo tail -f /var/log/nginx/error.log`
- Restart Nginx: `sudo systemctl restart nginx`

**App not starting in systemd?**
- Check service status: `sudo systemctl status ddos-gateway`
- View full logs: `sudo journalctl -u ddos-gateway -n 100`
- Check venv exists: `ls -la /home/ddos/venv/bin/uvicorn`
- Verify permissions: `ls -la /home/ddos/app/`
- Try manual start: `cd /home/ddos/app && /home/ddos/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000`

**Python version mismatch?**
- Verify Python: `python3 --version` (should be 3.8+)
- Check venv: `source /home/ddos/venv/bin/activate && pip list`

**Backend URL not working?**
- Set in systemd service: `sudo nano /etc/systemd/system/ddos-gateway.service`
- Update `Environment="BACKEND_URL=http://your-backend:9000"`
- Reload: `sudo systemctl daemon-reload && sudo systemctl restart ddos-gateway`

**Can't SSH?**
- Verify security group allows port 22 from your IP
- Check key pair permissions: `chmod 400 ddos-key.pem`
- Use correct username: `ubuntu` for Ubuntu AMI
- Verify instance has public IP assigned

---

**Done!** Your manual AWS infrastructure is ready for the hybrid ML gateway.
