above file
# Manual Backend Deployment on AWS - Step by Step

## Overview
**Instance:** webserver-1 (10.0.101.216)  
**Port:** 9000  
**Application:** PDF Library (FastAPI)  
**Status:** Currently showing "backend unavailable"

---

## Prerequisites
- Access to AWS Console: https://console.aws.amazon.com
- IAM role with Systems Manager permissions (already configured)
- Backend_DDoS.git repository already cloned to `/home/ubuntu/Backend_DDoS`

---

## Step 1: Connect to Backend Instance via AWS Systems Manager

### Method: Using AWS Systems Manager Session Manager (No Public IP Needed)

1. **Open AWS Console**
   - Go to: https://console.aws.amazon.com
   - Select Region: **us-east-1**

2. **Navigate to EC2 Instances**
   - Click **EC2** in Services
   - Click **Instances** (left sidebar)
   - Find: **webserver-1** instance
   - Status should be: **running ✅**
   - Note: No public IP (uses private subnet)

3. **Connect Using Session Manager**
   - Right-click **webserver-1**
   - Select **Connect**
   - Click tab: **Session Manager**
   - Click button: **Connect**
   - You'll see a terminal in your browser ✅

---

## Step 2: Navigate to Backend Application (Already Cloned ✅)

The Backend_DDoS repository has already been cloned and venv is already created!

```bash
# You should be here (or navigate to it):
cd /home/ssm-user/Backend_DDoS

# Verify files
ls -la

# Expected output:
# .git/                (git repository)
# library_app/         (folder with main.py) ✅
# config/              (folder with nginx.conf) ✅
# requirements.txt     (file) ✅
# venv/                (Python virtual environment) ✅
```

---

## Step 3: Activate Python Virtual Environment (Already Created ✅)

The venv is already created. Just activate it:

```bash
# Make sure you're in the Backend_DDoS directory
cd /home/ssm-user/Backend_DDoS
pwd  # Should show /home/ssm-user/Backend_DDoS

# If you're using sh shell, use . instead of source:
. venv/bin/activate

# OR if you're using bash, you can use:
source venv/bin/activate

# You should see (venv) at the start of your terminal prompt
# Example: (venv) ssm-user@ip-10-0-101-216:~/Backend_DDoS$
```

**Note:** If you get "source: not found", you're using `sh`. Use `. venv/bin/activate` instead.

---

## Step 4: Install Python Dependencies

```bash
# Make sure virtualenv is activated (should see (venv) in prompt)
# If not, run: . /home/ssm-user/Backend_DDoS/venv/bin/activate

# Install requirements
pip install -r requirements.txt

# Expected packages:
# - fastapi==0.104.1
# - uvicorn[standard]==0.24.0
# - aiofiles==23.2.1
# - jinja2==3.1.2
# - PyPDF2==3.0.1
# - httpx==0.25.0
# - python-multipart==0.0.6
```

**Wait for installation to complete** (usually takes 2-3 minutes)

---

## Step 5: Test the Application Locally

```bash
# Make sure you're in Backend_DDoS directory
cd /home/ssm-user/Backend_DDoS

# Activate virtualenv if not already activated (use . instead of source for sh)
. venv/bin/activate

# Start the FastAPI server on port 8000 (internal)
# This is the actual Python application running directly
uvicorn library_app.main:app --host 0.0.0.0 --port 8000

# Expected output:
# INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

**Architecture Note:**
- Port **8000** = FastAPI application (runs here during development/testing)
- Port **9000** = Nginx reverse proxy (will be exposed externally after Step 6)
- Nginx proxies: requests on 9000 → forward to 8000

**Test if it works (open new Session Manager terminal):**
```bash
# Open another Session Manager terminal and test the running app
curl http://localhost:8000/health

# Expected response:
# {"status":"ok","service":"library-backend"}

# Also test root
curl http://localhost:8000/

# You should get a response
```

**Stop the server:** Press `CTRL+C` in the first terminal

---

## Step 6: Install and Configure Nginx

```bash
# Install Nginx
sudo apt-get install -y nginx

# Enable Nginx to start on boot
sudo systemctl enable nginx

# Create Nginx configuration for port 9000
sudo tee /etc/nginx/sites-available/backend << 'EOF'
server {
    listen 9000 default_server;
    server_name _;

    client_max_body_size 10M;
    client_body_timeout 10s;
    client_header_timeout 10s;
    keepalive_timeout 15s;
    send_timeout 10s;

    location / {
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
EOF

# Enable this configuration
sudo ln -sf /etc/nginx/sites-available/backend /etc/nginx/sites-enabled/backend

# Remove default configuration
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
sudo nginx -t

# Expected output:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful

# Start Nginx
sudo systemctl start nginx

# Check status
sudo systemctl status nginx
```

---

## Step 7: Create Systemd Service for Backend App

```bash
# Create systemd service file
# Note: Update the path based on where ssm-user's home directory is
sudo tee /etc/systemd/system/ddos-backend.service << 'EOF'
[Unit]
Description=DDoS Backend - PDF Library
After=network.target

[Service]
Type=simple
User=ssm-user
WorkingDirectory=/home/ssm-user/Backend_DDoS
Environment="PATH=/home/ssm-user/Backend_DDoS/venv/bin"
ExecStart=/home/ssm-user/Backend_DDoS/venv/bin/uvicorn library_app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
sudo systemctl enable ddos-backend.service

# Start the service
sudo systemctl start ddos-backend.service

# Check if it's running
sudo systemctl status ddos-backend.service

# Expected output:
# ● ddos-backend.service - DDoS Backend - PDF Library
#    Loaded: loaded (/etc/systemd/system/ddos-backend.service; enabled; vendor preset: enabled)
#    Active: active (running) since ...
```

---

## Step 8: Verify Backend is Working

```bash
# Check if port 8000 is listening (FastAPI)
ss -tlnp | grep 8000

# Check if port 9000 is listening (Nginx)
ss -tlnp | grep 9000

# Expected output:
# LISTEN  0  2048  0.0.0.0:8000  0.0.0.0:*  users:(("python3",pid=XXXX,fd=X))
# LISTEN  0  511   0.0.0.0:9000  0.0.0.0:*  users:(("nginx",pid=XXXX,fd=X))

# Test health endpoint through Nginx (port 9000)
curl http://localhost:9000/health

# Expected response:
# {"status":"ok","service":"library-backend"}
```

---

## Step 9: Check Security Group Configuration

Go back to AWS Console:

1. **Navigate to Security Groups**
   - EC2 → Security Groups
   - Find: **webserver-sg** (or similar)

2. **Inbound Rules** should have:
   - Port **9000** open from: **gateway-sg** (or 0.0.0.0/0 for testing)
   - Port **22** open from: your IP (for SSH)

3. **If not configured, add rule:**
   - Click **Edit inbound rules**
   - Add rule:
     - Type: Custom TCP
     - Port: 9000
     - Source: sg-xxxxxx (gateway-sg)
   - Click **Save rules**

---

## Step 10: Verify Backend is Working Before Testing ALB

```bash
# Check if backend service is running
sudo systemctl status ddos-backend.service

# Check if Nginx is running
sudo systemctl status nginx

# Check if ports are listening
sudo netstat -tlnp | grep -E '(8000|9000)'

# Expected output:
# tcp  0  0 0.0.0.0:8000  0.0.0.0:*  LISTEN  <pid>/python3
# tcp  0  0 0.0.0.0:9000  0.0.0.0:*  LISTEN  <pid>/nginx: master process

# Test health endpoint through Nginx (port 9000)
curl http://localhost:9000/health

# Expected response:
# {"status":"ok","service":"library-backend"}
```

---

## Step 11: Check Security Group Configuration

Go back to AWS Console:

1. **Navigate to Security Groups**
   - EC2 → Security Groups
   - Find: **webserver-sg** (or similar)

2. **Inbound Rules** should have:
   - Port **9000** open from: **gateway-sg** (or 0.0.0.0/0 for testing)
   - Port **22** open from: your IP (for SSH) - NOT NEEDED with Session Manager
   - Note: Since you're using Session Manager, no need for public IP

3. **If not configured, add rule:**
   - Click **Edit inbound rules**
   - Add rule:
     - Type: Custom TCP
     - Port: 9000
     - Source: sg-xxxxxx (gateway-sg)
   - Click **Save rules**

---

## Step 12: Test from Gateway Instance

SSH (or Session Manager) into one of the Gateway instances and test:

```bash
# Test backend connectivity from gateway
curl http://10.0.101.216:9000/health

# Expected response:
# {"status":"ok","service":"library-backend"}
```

---

## Step 13: Test from Browser (Final Test)

Open your browser and go to:

```
http://ddos-alb-40013909.us-east-1.elb.amazonaws.com/
```

**Expected:** See the library website (instead of "backend unavailable")

---

## Troubleshooting

### If you see "backend unavailable":

1. **Check if backend service is running:**
```bash
sudo systemctl status ddos-backend.service

# If not running, start it:
sudo systemctl start ddos-backend.service

# Check logs:
sudo journalctl -u ddos-backend.service -f
```

2. **Check if Nginx is running:**
```bash
sudo systemctl status nginx

# If not running:
sudo systemctl start nginx
```

3. **Check if ports are listening:**
```bash
sudo netstat -tlnp | grep -E '(8000|9000)'
```

4. **Check security group allows traffic from gateway:**
```bash
# Verify on AWS Console:
# EC2 → Security Groups → webserver-sg
# Inbound: Port 9000 should allow gateway-sg
```

5. **Check application logs:**
```bash
# View recent logs
sudo journalctl -u ddos-backend.service --no-pager -n 50

# Follow logs in real time
sudo journalctl -u ddos-backend.service -f
```

6. **Manual test of each layer:**
```bash
# Layer 1: FastAPI on port 8000
curl http://localhost:8000/health

# Layer 2: Nginx proxy on port 9000
curl http://localhost:9000/health

# Layer 3: From gateway instance (10.0.101.216 is webserver-1)
# Run from gateway: curl http://10.0.101.216:9000/health

# Layer 4: Through ALB (from your browser)
# http://ddos-alb-40013909.us-east-1.elb.amazonaws.com/
```

---

## Quick Commands Reference

```bash
# View application status
sudo systemctl status ddos-backend.service

# View application logs
sudo journalctl -u ddos-backend.service -f

# Restart application
sudo systemctl restart ddos-backend.service

# Stop application
sudo systemctl stop ddos-backend.service

# Start application
sudo systemctl start ddos-backend.service

# View Nginx status
sudo systemctl status nginx

# Test Nginx config
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx

# Check if ports are open
sudo netstat -tlnp
```

---

## Appendix: Gateway Instance Setup Script

If you need to (re)configure a gateway instance, use this script:

```bash
#!/bin/bash
set -euo pipefail

apt-get update -y
apt-get install -y python3 python3-pip python3-venv nginx

useradd -m ddos || true
su - ddos -c "python3 -m venv ~/venv && ~/venv/bin/pip install fastapi uvicorn httpx"

cat >/home/ddos/app.py <<'PY'
from fastapi import FastAPI, Request, Response
import time, httpx

app = FastAPI()
START = time.time()
BLOCKLIST = set()

BACKEND_URL = "http://10.0.101.216:9000"  # Backend instance private IP

@app.get("/health")
def health():
    return {"status":"ok","uptime_sec": round(time.time()-START,2),"blocked": len(BLOCKLIST)}

@app.get("/stats")
def stats():
    return {"requests": "placeholder", "blocked": len(BLOCKLIST)}

@app.middleware("http")
async def simple_gate(req: Request, call_next):
    ip = req.client.host
    if ip in BLOCKLIST:
        return Response(status_code=403, content="blocked")
    # TODO: plug in feature extraction + classifier here
    return await call_next(req)

@app.get("/{path:path}")
async def proxy(path: str, request: Request):
    # simple reverse proxy to backend
    async with httpx.AsyncClient(timeout=5.0) as client:
        r = await client.request(
            request.method,
            f"{BACKEND_URL}/{path}",
            headers={k:v for k,v in request.headers.items() if k.lower() != 'host'},
            content=await request.body(),
        )
        return Response(content=r.content, status_code=r.status_code, headers=dict(r.headers))
PY

chown ddos:ddos /home/ddos/app.py

cat >/etc/systemd/system/ddos-gateway.service <<'UNIT'
[Unit]
Description=DDoS Gateway API
After=network.target

[Service]
User=ddos
ExecStart=/home/ddos/venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000
WorkingDirectory=/home/ddos
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now ddos-gateway

# Nginx reverse proxy on :80 with basic hardening
cat >/etc/nginx/sites-available/ddos <<'NG'
server {
    listen 80 default_server;
    server_name _;

    # Timeouts to curb slowloris
    client_body_timeout 5s;
    client_header_timeout 5s;
    keepalive_timeout 10s;
    send_timeout 5s;

    # Basic rate limiting (tune as needed)
    limit_req_zone $binary_remote_addr zone=reqperip:10m rate=10r/s;

    location / {
        limit_req zone=reqperip burst=20 nodelay;
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 10s;
    }
}
NG

ln -sf /etc/nginx/sites-available/ddos /etc/nginx/sites-enabled/ddos
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx
```

---

## Expected Final Result

✅ **When everything is working:**

1. Gateway instances (Port 80) running gateway service
2. Backend instance (Port 9000) running library_app/
3. ALB routes safe traffic from Gateway to Backend
4. Browser shows library website instead of "backend unavailable"

```
Internet → ALB (Port 80) → Gateway (Port 80) → [DDoS Detection] → Backend (Port 9000) → Library App
```

---

**Last Updated:** November 23, 2025  
**Status:** Deployment complete - Gateway forwarding to backend
