#!/bin/bash
# Deploy ML Gateway to AWS EC2
# Run this script on EC2 instance

set -e

echo "================================================"
echo "🚀 ML GATEWAY EC2 DEPLOYMENT"
echo "================================================"
echo ""

# Configuration
REPO_URL="https://github.com/your-username/iddmsca-copy.git"
DEPLOY_DIR="/home/ec2-user/IDDMSCA"
VENV_DIR="$DEPLOY_DIR/venv"

echo "📦 Installing dependencies..."
sudo yum update -y
sudo yum install -y python3.11 python3.11-devel git supervisor nginx

echo "📁 Creating deployment directory..."
mkdir -p $DEPLOY_DIR
cd $DEPLOY_DIR

echo "📥 Cloning repository..."
git clone $REPO_URL .

echo "🐍 Creating virtual environment..."
python3.11 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

echo "📦 Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "🔧 Configuring Supervisor..."
sudo cp config/supervisor.conf /etc/supervisor/conf.d/ml_gateway.conf
sudo mkdir -p /var/log/ml_gateway

echo "🚀 Starting ML Gateway with Supervisor..."
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start ml_gateway

echo "📡 Configuring Nginx reverse proxy..."
sudo cp config/nginx.conf /etc/nginx/conf.d/ml_gateway.conf
sudo nginx -s reload

echo ""
echo "================================================"
echo "✅ DEPLOYMENT COMPLETE!"
echo "================================================"
echo ""
echo "🎯 ML Gateway is running on:"
echo "   Nginx: http://your-ec2-ip"
echo "   Direct: http://your-ec2-ip:8000"
echo ""
echo "📊 Check status:"
echo "   sudo supervisorctl status"
echo ""
echo "📈 View logs:"
echo "   tail -f /var/log/ml_gateway.log"
echo ""
