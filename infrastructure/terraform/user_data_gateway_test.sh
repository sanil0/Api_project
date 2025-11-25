#!/bin/bash

# ML Gateway Initialization - ULTRA-SIMPLE TEST VERSION
# Uses basic HTTP server to verify infrastructure connectivity

set -e
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Gateway (Test Version)"

# Update system
apt-get update -y
apt-get upgrade -y

# Install required packages
apt-get install -y python3 supervisor nginx

# Create application directory
mkdir -p /opt/ml-gateway
cd /opt/ml-gateway

# Create application user
useradd -m -s /bin/bash gateway-user || true

# Download models from S3
echo "Downloading models from S3..."
mkdir -p models
cd models
aws s3 cp s3://hybrid-ddos-detection-models-55442/hybrid_stage1_model_v2.pkl . 2>/dev/null || echo "Model 1 not found"
cd ..

# Download and extract application
echo "Downloading application..."
aws s3 cp s3://hybrid-ddos-detection-models-55442/ml_gateway_app.tar.gz . 2>/dev/null || echo "App not found"
tar xzf ml_gateway_app.tar.gz 2>/dev/null || echo "Tar failed"

# Set permissions
chmod 755 ml_gateway_app/simple_server.py
chown -R gateway-user /opt/ml-gateway

# Configure Supervisor
cat > /etc/supervisor/conf.d/ml-gateway.conf << 'EOF'
[program:ml-gateway]
command=/usr/bin/python3 /opt/ml-gateway/ml_gateway_app/simple_server.py
directory=/opt/ml-gateway
user=gateway-user
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/ml-gateway.log
EOF

systemctl restart supervisor
supervisorctl reread
supervisorctl update
sleep 2
supervisorctl start ml-gateway

# Configure Nginx
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
        proxy_buffering off;
    }
}
EOF

ln -sf /etc/nginx/sites-available/gateway /etc/nginx/sites-enabled/gateway
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

echo "[OK] Gateway test version initialized"
