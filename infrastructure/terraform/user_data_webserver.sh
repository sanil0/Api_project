#!/bin/bash

# Webserver Initialization Script (Pre-LB Architecture)
# Runs on Backend webserver instances (private network)
# No DDoS detection - only serves application traffic

set -e

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=========================================================="
echo "Starting Webserver Initialization"
echo "Timestamp: $(date)"
echo "=========================================================="

# Update system
apt-get update -y
apt-get upgrade -y

# Install required packages
apt-get install -y python3 python3-pip python3-venv nginx supervisor awscli unzip curl

# Create application directory
mkdir -p /opt/webapp
cd /opt/webapp

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

# Install Python dependencies for webapp
pip install fastapi uvicorn pydantic python-multipart
pip install numpy pandas

# Create application user
useradd -m -s /bin/bash webapp-user || true

# Create simple demo web application
echo "=========================================================="
echo "Setting up Web Application"
echo "=========================================================="

cat > app.py << 'EOF'
from fastapi import FastAPI, Request
from datetime import datetime
import os

app = FastAPI(title="Protected Webapp", version="1.0.0")

@app.get("/")
async def root():
    return {
        "status": "healthy",
        "service": "Protected Web Application",
        "timestamp": datetime.now().isoformat(),
        "hostname": os.getenv("HOSTNAME", "unknown"),
        "note": "Protected by ML Gateway (Pre-LB Architecture)"
    }

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "webapp"}

@app.get("/api/info")
async def info(request: Request):
    return {
        "service": "webapp",
        "client_ip": request.client.host,
        "timestamp": datetime.now().isoformat(),
        "headers": dict(request.headers)
    }

@app.post("/api/echo")
async def echo(request: Request):
    body = await request.json()
    return {
        "echo": body,
        "received_at": datetime.now().isoformat()
    }
EOF

# Set permissions
chown webapp-user:webapp-user /opt/webapp
chmod -R 755 /opt/webapp

# Configure Supervisor for webapp process management
echo "=========================================================="
echo "Configuring Supervisor"
echo "=========================================================="

mkdir -p /etc/supervisor/conf.d

cat > /etc/supervisor/conf.d/webapp.conf << 'EOF'
[program:webapp]
command=/opt/webapp/venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port 9000
directory=/opt/webapp
user=webapp-user
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/webapp.log
stderr_logfile=/var/log/webapp-error.log
environment=PYTHONUNBUFFERED=1
EOF

# Enable and start supervisor
systemctl enable supervisor
systemctl restart supervisor
supervisorctl reread
supervisorctl update
supervisorctl start webapp

# Wait for webapp to start
echo "Waiting for webapp to start..."
for i in {1..30}; do
    if curl -f http://localhost:9000/health > /dev/null 2>&1; then
        echo "✅ Webapp is healthy"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 1
done

# Configure nginx as reverse proxy (optional)
echo "=========================================================="
echo "Configuring Nginx"
echo "=========================================================="

cat > /etc/nginx/sites-available/webapp << 'EOF'
upstream app_server {
    server localhost:9000;
}

server {
    listen 9000 default_server;
    server_name _;

    location / {
        proxy_pass http://app_server;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_redirect off;
    }
}
EOF

# Enable nginx configuration
ln -sf /etc/nginx/sites-available/webapp /etc/nginx/sites-enabled/webapp
rm -f /etc/nginx/sites-enabled/default

# Test and start nginx (optional - if using nginx)
# nginx -t && systemctl restart nginx

# Log completion
echo "=========================================================="
echo "Webserver Initialization Complete!"
echo "Timestamp: $(date)"
echo "=========================================================="
echo "✅ Webserver Status:"
echo "   - Application Port: 9000 (Private, Internal only)"
echo "   - Accessible From: Gateway only"
echo "   - Process Manager: Supervisor"
echo "   - Security: No direct internet access"
echo "   - Network: Private subnet only"
echo "=========================================================="
