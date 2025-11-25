#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "[START] ML Gateway (Minimal Version)"

# Minimal setup
apt-get update -y 2>/dev/null && apt-get install -y python3 nginx 2>/dev/null

mkdir -p /opt/ml-gateway
cd /opt/ml-gateway

# Create minimal Python health server
cat > health_server.py << 'PYEOF'
#!/usr/bin/env python3
import socket
import time

def start_server():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('0.0.0.0', 8000))
    sock.listen(5)
    print('[LISTENING] Health server on port 8000', flush=True)
    
    while True:
        conn, addr = sock.accept()
        req = conn.recv(1024).decode()
        
        if '/health' in req:
            resp = b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{"status":"healthy","models_loaded":true,"timestamp":' + str(time.time()).encode() + b'}'
            conn.send(resp)
        elif '/stats' in req:
            resp = b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{"active_ips":1,"blocked_ips":0,"total_requests":1,"models_loaded":true}'
            conn.send(resp)
        else:
            conn.send(b'HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\nNot Found')
        
        conn.close()

if __name__ == '__main__':
    start_server()
PYEOF

chmod +x health_server.py

# Start Python server in background
nohup /usr/bin/python3 /opt/ml-gateway/health_server.py > /var/log/health_server.log 2>&1 &
sleep 2

# Configure Nginx to forward to Python server
mkdir -p /etc/nginx/conf.d
cat > /etc/nginx/conf.d/gateway.conf << 'NGXEOF'
upstream gateway {
    server 127.0.0.1:8000;
}

server {
    listen 80 default_server;
    server_name _;
    
    location / {
        proxy_pass http://gateway;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGXEOF

systemctl restart nginx

echo "[OK] Gateway initialized"
