#!/bin/bash

# DDoS Dashboard Deployment Script
# Run this on the dashboard EC2 instance

set -e

echo "🚀 Starting DDoS Dashboard Deployment"

# Update system
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install Python and pip
echo "🐍 Installing Python and pip..."
sudo apt install -y python3 python3-pip python3-venv

# Install Node.js and npm
echo "📦 Installing Node.js and npm..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Create dashboard directory
echo "📁 Creating dashboard directory..."
sudo mkdir -p /opt/ddos-dashboard
sudo chown ubuntu:ubuntu /opt/ddos-dashboard
cd /opt/ddos-dashboard

# Clone or copy dashboard code (assuming it's available)
# For now, we'll assume the code is copied to this directory
echo "📋 Setting up dashboard code..."
# cp -r /path/to/dashboard/code/* .

# Setup Python virtual environment
echo "🔧 Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
echo "📦 Installing Python dependencies..."
pip install -r requirements.txt

# Setup frontend
echo "⚛️ Setting up React frontend..."
cd frontend
npm install
npm run build
cd ..

# Create systemd service for backend
echo "🔧 Creating systemd service..."
sudo tee /etc/systemd/system/ddos-dashboard.service > /dev/null <<EOF
[Unit]
Description=DDoS Dashboard Backend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/ddos-dashboard
Environment="PATH=/opt/ddos-dashboard/venv/bin"
ExecStart=/opt/ddos-dashboard/venv/bin/python app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for frontend
echo "🔧 Creating frontend systemd service..."
sudo tee /etc/systemd/system/ddos-dashboard-frontend.service > /dev/null <<EOF
[Unit]
Description=DDoS Dashboard Frontend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/ddos-dashboard/frontend
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=5
Environment="PORT=3000"
Environment="REACT_APP_API_URL=http://localhost:8001"

[Install]
WantedBy=multi-user.target
EOF

# Start and enable services
echo "▶️ Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable ddos-dashboard
sudo systemctl enable ddos-dashboard-frontend
sudo systemctl start ddos-dashboard
sudo systemctl start ddos-dashboard-frontend

# Setup nginx (optional, for production)
echo "🌐 Setting up nginx reverse proxy..."
sudo apt install -y nginx

sudo tee /etc/nginx/sites-available/ddos-dashboard > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    # Backend API
    location /api/ {
        proxy_pass http://localhost:8001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Frontend
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/ddos-dashboard /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Setup firewall
echo "🔥 Configuring firewall..."
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw --force enable

echo "✅ Dashboard deployment completed!"
echo ""
echo "📊 Dashboard URLs:"
echo "  Frontend: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "  API: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/api/"
echo ""
echo "🔧 Management commands:"
echo "  Backend logs: sudo journalctl -u ddos-dashboard -f"
echo "  Frontend logs: sudo journalctl -u ddos-dashboard-frontend -f"
echo "  Restart backend: sudo systemctl restart ddos-dashboard"
echo "  Restart frontend: sudo systemctl restart ddos-dashboard-frontend"