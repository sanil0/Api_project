# Fix: Backend Unavailable Error

## Problem
When accessing the DDoS ALB, you see: **"backend unavailable"**

This means:
- ✅ Gateway instances are running and accepting traffic on port 80
- ❌ Backend instance (webserver-1) is NOT serving requests on port 9000

---

## Root Cause

The backend instance **webserver-1** (IP: 10.0.101.216) is running but:
1. Backend application is NOT deployed
2. Port 9000 is NOT responding

---

## Quick Fix

### Option 1: Manual Deployment (SSH)

```bash
# 1. SSH into webserver-1 (10.0.101.216)
ssh -i your-key.pem ubuntu@10.0.101.216

# 2. Clone backend repository
git clone https://github.com/sanil0/Backend_DDoS.git ~/backend_app
cd ~/backend_app

# 3. Create virtual environment
python3 -m venv venv
source venv/bin/activate

# 4. Install dependencies
pip install -r requirements.txt

# 5. Start application
uvicorn library_app.main:app --host 0.0.0.0 --port 8000
```

### Option 2: Automated Deployment Script

```bash
# Copy deploy_backend.sh to webserver-1
scp -i your-key.pem deploy_backend.sh ubuntu@10.0.101.216:/tmp/

# SSH and run it
ssh -i your-key.pem ubuntu@10.0.101.216
bash /tmp/deploy_backend.sh
```

### Option 3: Terminate and Relaunch with Proper User Data

```bash
# Terminate current webserver-1
aws ec2 terminate-instances --instance-ids i-003e1ad33a0e81b66

# Update user_data_webserver.sh with deployment code
# Then relaunch instance
```

---

## Verification

After deployment, test:

```bash
# From your local machine
curl http://ddos-alb-40013909.us-east-1.elb.amazonaws.com/health

# Or directly to backend
curl http://10.0.101.216:9000/health
```

Expected response:
```json
{"status":"ok","service":"library-backend"}
```

---

## What Needs to Happen

### On Backend Instance (Port 8000 - Internal)
```
FastAPI Application
├─ library_app/main.py
├─ Running on 127.0.0.1:8000
└─ Requires: fastapi, uvicorn, jinja2, aiofiles, etc.
```

### On Backend Instance (Port 9000 - Public)
```
Nginx Reverse Proxy
├─ Listens on 0.0.0.0:9000
├─ Forwards to 127.0.0.1:8000
└─ Exposed to ALB from gateway
```

### Gateway → Backend Flow
```
Gateway Instance (Port 80)
    ↓ (detects traffic is safe)
Internal ALB (Port 9000)
    ↓ (routes to target)
Nginx on Backend (Port 9000)
    ↓ (forwards internally)
FastAPI on Backend (Port 8000)
    ↓
User sees: Library application
```

---

## Current Instances

| Instance | Name | IP | Status | Purpose |
|----------|------|------|--------|---------|
| i-075a2261e06d7de67 | gateway-A | 10.0.1.24 | ✅ Running | DDoS Detection |
| i-0395630784864e7ba | gateway-B | 10.0.2.117 | ✅ Running | DDoS Detection |
| i-003e1ad33a0e81b66 | webserver-1 | 10.0.101.216 | ⚠️ Empty | Backend App (NEEDS DEPLOYMENT) |

---

## Next Steps

1. **Immediate**: Deploy backend using one of the options above
2. **Test**: Verify port 9000 responds with health check
3. **Monitor**: Check logs with `sudo journalctl -u library-backend -f`
4. **Optimize**: Set up auto-scaling group with proper user-data

---

## User Data for Future Deployments

When launching new backend instances, use this user-data script:

```bash
#!/bin/bash
set -e

# Update system
apt-get update
apt-get install -y python3 python3-pip python3-venv git nginx curl

# Create app directory
mkdir -p /home/ubuntu/backend_app
cd /home/ubuntu/backend_app

# Clone repository
git clone https://github.com/sanil0/Backend_DDoS.git .

# Setup Python environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Create systemd service
cat > /etc/systemd/system/library-backend.service <<EOF
[Unit]
Description=Library Backend FastAPI
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/backend_app
Environment="PATH=/home/ubuntu/backend_app/venv/bin"
ExecStart=/home/ubuntu/backend_app/venv/bin/uvicorn library_app.main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Configure Nginx
cat > /etc/nginx/sites-available/library <<'EOF'
server {
    listen 9000;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

ln -sf /etc/nginx/sites-available/library /etc/nginx/sites-enabled/library
rm -f /etc/nginx/sites-enabled/default

# Start services
systemctl daemon-reload
systemctl enable library-backend
systemctl start library-backend
systemctl restart nginx

echo "✅ Backend deployment complete"
```

---

**Status**: Backend app needs to be deployed to webserver-1 (10.0.101.216)  
**Priority**: High - This is blocking users from accessing the library
