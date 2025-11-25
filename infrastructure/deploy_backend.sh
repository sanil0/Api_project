#!/bin/bash
# Deploy Backend Application to webserver-1

set -e

echo "🚀 Deploying Backend Application..."

# Variables
BACKEND_REPO="https://github.com/sanil0/Backend_DDoS.git"
APP_DIR="/home/ubuntu/backend_app"
USER="ubuntu"

echo "1️⃣ Creating application directory..."
sudo mkdir -p "$APP_DIR"
sudo chown "$USER:$USER" "$APP_DIR"

echo "2️⃣ Cloning Backend_DDoS repository..."
cd "$APP_DIR"
git clone "$BACKEND_REPO" . || git pull

echo "3️⃣ Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

echo "4️⃣ Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "5️⃣ Creating systemd service..."
sudo tee /etc/systemd/system/library-backend.service > /dev/null <<EOF
[Unit]
Description=Library Backend FastAPI Application
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
ExecStart=$APP_DIR/venv/bin/uvicorn library_app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "6️⃣ Configuring Nginx as reverse proxy on port 9000..."
sudo tee /etc/nginx/sites-available/library > /dev/null <<'EOF'
server {
    listen 9000 default_server;
    server_name _;

    client_max_body_size 100M;
    client_body_timeout 30s;
    client_header_timeout 30s;
    keepalive_timeout 30s;
    send_timeout 30s;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
        proxy_connect_timeout 30s;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:8000/health;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/library /etc/nginx/sites-enabled/library
sudo rm -f /etc/nginx/sites-enabled/default

echo "7️⃣ Testing Nginx configuration..."
sudo nginx -t

echo "8️⃣ Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable library-backend
sudo systemctl restart library-backend
sudo systemctl restart nginx

echo "9️⃣ Verifying deployment..."
sleep 3

echo "Checking application status:"
sudo systemctl status library-backend --no-pager

echo "Checking Nginx status:"
sudo systemctl status nginx --no-pager

echo ""
echo "✅ Deployment Complete!"
echo ""
echo "Service Information:"
echo "  Systemd service: library-backend"
echo "  Application port: 8000 (internal)"
echo "  Nginx port: 9000 (external)"
echo "  User: $USER"
echo "  Directory: $APP_DIR"
echo ""
echo "Useful Commands:"
echo "  View logs: sudo journalctl -u library-backend -f"
echo "  Restart service: sudo systemctl restart library-backend"
echo "  Check status: sudo systemctl status library-backend"
echo "  Test endpoint: curl http://localhost:9000/health"
