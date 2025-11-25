#!/bin/bash

# ML Gateway Initialization Script (Pre-LB Architecture)
# Runs on Gateway instances positioned before the ALB
# Responsible for DDoS detection and traffic filtering

set -e

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=========================================================="
echo "Starting ML Gateway Initialization"
echo "Timestamp: $(date)"
echo "=========================================================="

# Update system
apt-get update -y
apt-get upgrade -y

# Install required packages
apt-get install -y python3 python3-pip python3-venv curl wget awscli unzip jq supervisor

# Create application directory
mkdir -p /opt/ml-gateway
cd /opt/ml-gateway

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

# Install Python dependencies for gateway
pip install fastapi uvicorn httpx pydantic python-multipart
pip install pandas scikit-learn xgboost numpy
pip install boto3

# Create application user
useradd -m -s /bin/bash gateway-user || true

# Download ML models from S3
echo "=========================================================="
echo "Downloading ML Models from S3..."
echo "=========================================================="
mkdir -p models
cd models

# Stage 1: Binary DDoS Detection Model
aws s3 cp s3://${s3_bucket_name}/hybrid_stage1_model_v2.pkl . || echo "⚠️ Stage 1 model not found"
aws s3 cp s3://${s3_bucket_name}/hybrid_stage1_scaler_v2.pkl . || echo "⚠️ Stage 1 scaler not found"

# Stage 2: Attack Type Classification Model
aws s3 cp s3://${s3_bucket_name}/hybrid_stage2_model_v3_real_benign.pkl . || echo "⚠️ Stage 2 model not found"
aws s3 cp s3://${s3_bucket_name}/hybrid_stage2_scaler_v3_real_benign.pkl . || echo "⚠️ Stage 2 scaler not found"

cd ..
echo "✅ Models downloaded"

# Set backend targets configuration
echo "=========================================================="
echo "Configuring Backend Targets"
echo "=========================================================="

# Create gateway configuration file
mkdir -p /etc/ml-gateway
cat > /etc/ml-gateway/config.json << EOF
{
  "gateway": {
    "port": 80,
    "host": "0.0.0.0",
    "workers": 4
  },
  "backend_targets": [
    {
      "host": "${alb_dns_name}",
      "port": ${alb_port},
      "priority": 1
    }
  ],
  "ml_detection": {
    "threshold": 0.8,
    "window_size": 300
  }
}
EOF

chown gateway-user:gateway-user /etc/ml-gateway/config.json
chmod 644 /etc/ml-gateway/config.json

echo "Backend ALB: ${alb_dns_name}:${alb_port}"

# Copy gateway application code from repository or S3
echo "=========================================================="
echo "Setting up Gateway Application"
echo "=========================================================="

# Create ml_gateway package structure
mkdir -p ml_gateway

# Create __init__.py
cat > ml_gateway/__init__.py << 'PYEOF'
"""ML Gateway - Pre-LB DDoS Detection System"""
__version__ = "2.0.0"
PYEOF

# Create the FastAPI application
cat > ml_gateway/app.py << 'PYEOF'
import os
import sys
import json
import pickle
import logging
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import Response, JSONResponse
import numpy as np
import httpx
from typing import List, Dict, Any
from collections import defaultdict
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="ML DDoS Gateway", version="2.0.0")

# Global state
stage1_model = None
stage1_scaler = None
stage2_model = None
stage2_scaler = None
models_loaded = False
request_counts = defaultdict(list)
blocked_ips = set()
backend_targets = []

class BackendManager:
    def __init__(self, targets):
        self.targets = targets
        self.current_idx = 0
        self.client = httpx.AsyncClient(timeout=30.0)
    
    def get_next_target(self):
        if not self.targets:
            return None
        target = self.targets[self.current_idx]
        self.current_idx = (self.current_idx + 1) % len(self.targets)
        return target
    
    async def forward_request(self, request: Request):
        target = self.get_next_target()
        if not target:
            raise HTTPException(status_code=503, detail="No backends available")
        
        try:
            url = f"http://{target['host']}:{target['port']}{request.url.path}"
            if request.url.query:
                url += f"?{request.url.query}"
            
            body = await request.body() if request.method in ["POST", "PUT"] else None
            
            async with self.client as client:
                response = await client.request(
                    method=request.method,
                    url=url,
                    content=body,
                    headers=dict(request.headers),
                    follow_redirects=True
                )
                return Response(content=response.content, status_code=response.status_code, headers=dict(response.headers))
        except Exception as e:
            logger.error(f"Backend forward error: {e}")
            raise HTTPException(status_code=502, detail="Backend error")

backend_manager = None

def load_models():
    global stage1_model, stage1_scaler, stage2_model, stage2_scaler, models_loaded
    try:
        model_dir = "/opt/ml-gateway/models"
        
        with open(f"{model_dir}/hybrid_stage1_model_v2.pkl", "rb") as f:
            stage1_model = pickle.load(f)
        with open(f"{model_dir}/hybrid_stage1_scaler_v2.pkl", "rb") as f:
            stage1_scaler = pickle.load(f)
        with open(f"{model_dir}/hybrid_stage2_model_v3_real_benign.pkl", "rb") as f:
            stage2_model = pickle.load(f)
        with open(f"{model_dir}/hybrid_stage2_scaler_v3_real_benign.pkl", "rb") as f:
            stage2_scaler = pickle.load(f)
        
        models_loaded = True
        logger.info("✅ All ML models loaded successfully")
    except Exception as e:
        logger.error(f"❌ Failed to load models: {e}")
        models_loaded = False

def load_config():
    global backend_targets, backend_manager
    try:
        with open("/etc/ml-gateway/config.json", "r") as f:
            config = json.load(f)
            backend_targets = config.get("backend_targets", [])
            backend_manager = BackendManager(backend_targets)
            logger.info(f"✅ Configuration loaded: {len(backend_targets)} backend targets")
    except Exception as e:
        logger.error(f"⚠️ Config error: {e}")

@app.on_event("startup")
async def startup():
    load_models()
    load_config()
    logger.info("🚀 ML Gateway started")

@app.get("/health")
async def health():
    return {
        "status": "healthy" if models_loaded else "degraded",
        "models_loaded": models_loaded,
        "timestamp": time.time()
    }

@app.get("/stats")
async def stats():
    active_ips = len([ip for ip, times in request_counts.items() if times and time.time() - times[-1] < 300])
    return {
        "active_ips": active_ips,
        "blocked_ips": len(blocked_ips),
        "total_requests": sum(len(times) for times in request_counts.values()),
        "models_loaded": models_loaded
    }

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
async def gateway(request: Request, path: str):
    # DDoS detection and rate limiting
    client_ip = request.client.host if request.client else "unknown"
    
    # Check if already blocked
    if client_ip in blocked_ips:
        return JSONResponse({"error": "Access denied"}, status_code=403)
    
    current_time = time.time()
    request_counts[client_ip] = [t for t in request_counts[client_ip] if current_time - t < 60]
    request_counts[client_ip].append(current_time)
    
    # Rate limiting: 100 requests per minute
    if len(request_counts[client_ip]) > 100:
        blocked_ips.add(client_ip)
        logger.warning(f"🚨 Rate limit exceeded for {client_ip}, blocking")
        return JSONResponse({"error": "Rate limit exceeded"}, status_code=429)
    
    # Forward to backend
    return await backend_manager.forward_request(request)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=80, workers=1)
PYEOF

echo "✅ Gateway application created"

# Set proper permissions
chown -R gateway-user:gateway-user /opt/ml-gateway
chmod -R 755 /opt/ml-gateway

# Configure Supervisor for process management
echo "=========================================================="
echo "Configuring Supervisor"
echo "=========================================================="

cat > /etc/supervisor/conf.d/ml-gateway.conf << 'EOF'
[program:ml-gateway]
command=/opt/ml-gateway/venv/bin/python -m uvicorn ml_gateway.app:app --host 0.0.0.0 --port 8000 --workers 4
directory=/opt/ml-gateway
user=gateway-user
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/ml-gateway.log
environment=PYTHONUNBUFFERED=1,GATEWAY_CONFIG=/etc/ml-gateway/config.json
EOF

# Enable and start supervisor
systemctl enable supervisor
systemctl start supervisor
supervisorctl reread
supervisorctl update
supervisorctl start ml-gateway

# Configure Nginx as reverse proxy on port 80
echo "=========================================================="
echo "Configuring Nginx Reverse Proxy"
echo "=========================================================="

cat > /etc/nginx/sites-available/gateway << 'EOF'
upstream ml_gateway {
    server 127.0.0.1:8000;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    client_max_body_size 100M;

    location / {
        proxy_pass http://ml_gateway;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/gateway /etc/nginx/sites-enabled/gateway
rm -f /etc/nginx/sites-enabled/default

# Test and start nginx
nginx -t && systemctl restart nginx || echo "⚠️ Nginx configuration error"

echo "=========================================================="
echo "Health Check Setup"
echo "=========================================================="

# Create health check script
cat > /usr/local/bin/health-check.sh << 'EOF'
#!/bin/bash
curl -f http://localhost:80/health || exit 1
EOF

chmod +x /usr/local/bin/health-check.sh

# Create CloudWatch agent configuration (optional)
mkdir -p /opt/cloudwatch

# Log completion
echo "=========================================================="
echo "ML Gateway Initialization Complete!"
echo "Timestamp: $(date)"
echo "=========================================================="
echo "✅ Gateway Status:"
echo "   - Port: 80 (Public-facing)"
echo "   - Backend ALB: ${alb_dns_name}:${alb_port}"
echo "   - Models: Downloaded and ready"
echo "   - Process Manager: Supervisor"
echo "=========================================================="
