#!/bin/bash

# ML Gateway Initialization Script (Pre-LB Architecture) - SIMPLIFIED
# Downloads pre-built application from S3 instead of embedding complex code

set -e

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=========================================================="
echo "Starting ML Gateway Initialization (Simplified)"
echo "Timestamp: $(date)"
echo "=========================================================="

# Update system
apt-get update -y
apt-get upgrade -y

# Install required packages
apt-get install -y python3 python3-pip python3-venv curl wget awscli unzip jq supervisor nginx

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
pip install pandas scikit-learn xgboost numpy boto3

# Create application user
useradd -m -s /bin/bash gateway-user || true

# Download ML models from S3
echo "=========================================================="
echo "Downloading ML Models from S3..."
echo "=========================================================="
mkdir -p models
cd models

aws s3 cp s3://hybrid-ddos-detection-models-55442/hybrid_stage1_model_v2.pkl . || echo "[WARNING] Stage 1 model not found"
aws s3 cp s3://hybrid-ddos-detection-models-55442/hybrid_stage1_scaler_v2.pkl . || echo "[WARNING] Stage 1 scaler not found"
aws s3 cp s3://hybrid-ddos-detection-models-55442/hybrid_stage2_model_v3_real_benign.pkl . || echo "[WARNING] Stage 2 model not found"
aws s3 cp s3://hybrid-ddos-detection-models-55442/hybrid_stage2_scaler_v3_real_benign.pkl . || echo "[WARNING] Stage 2 scaler not found"

cd ..
echo "[OK] Models downloaded"

# Download and extract application code from S3
echo "=========================================================="
echo "Downloading Application Code from S3..."
echo "=========================================================="

aws s3 cp s3://hybrid-ddos-detection-models-55442/ml_gateway_app.tar.gz . || (echo "[ERROR] Failed to download app package"; exit 1)
tar xzf ml_gateway_app.tar.gz

# Set up configuration
echo "=========================================================="
echo "Setting up Configuration"
echo "=========================================================="

mkdir -p /etc/ml-gateway
cat > /etc/ml-gateway/config.json << 'EOF'
{
  "gateway": {
    "port": 8000,
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

# Set proper permissions
chown -R gateway-user:gateway-user /opt/ml-gateway
chmod -R 755 /opt/ml-gateway

# Configure Supervisor for process management
echo "=========================================================="
echo "Configuring Supervisor"
echo "=========================================================="

cat > /etc/supervisor/conf.d/ml-gateway.conf << 'SUPEOF'
[program:ml-gateway]
command=/opt/ml-gateway/venv/bin/python -m uvicorn ml_gateway_app.app:app --host 0.0.0.0 --port 8000 --workers 4
directory=/opt/ml-gateway
user=gateway-user
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/ml-gateway.log
environment=PYTHONUNBUFFERED=1
SUPEOF

# Enable and start supervisor
systemctl enable supervisor
systemctl start supervisor
sleep 2
supervisorctl reread
supervisorctl update
supervisorctl start ml-gateway

# Configure Nginx as reverse proxy on port 80
echo "=========================================================="
echo "Configuring Nginx Reverse Proxy"
echo "=========================================================="

cat > /etc/nginx/sites-available/gateway << 'NGXEOF'
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
NGXEOF

# Enable the site
ln -sf /etc/nginx/sites-available/gateway /etc/nginx/sites-enabled/gateway
rm -f /etc/nginx/sites-enabled/default

# Test and start nginx
nginx -t && systemctl restart nginx || echo "[WARNING] Nginx configuration error"

# Log completion
echo "=========================================================="
echo "ML Gateway Initialization Complete!"
echo "Timestamp: $(date)"
echo "=========================================================="
echo "[OK] Gateway Status:"
echo "   - Port: 80 (Public-facing)"
echo "   - Backend ALB: ${alb_dns_name}:${alb_port}"
echo "   - Models: Downloaded and ready"
echo "   - Process Manager: Supervisor"
echo "=========================================================="
