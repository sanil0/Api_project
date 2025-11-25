terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Simple VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "ddos-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "ddos-igw"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "ddos-public-subnet"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "ddos-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "ddos" {
  name   = "ddos-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ddos-sg"
  }
}

# Simple user data - just echo server to verify connectivity
resource "aws_instance" "gateway1" {
  ami               = "ami-054d6a336762e438e"  # Ubuntu 20.04 in us-east-1
  instance_type     = "t3.micro"
  subnet_id         = aws_subnet.public.id
  security_groups   = [aws_security_group.ddos.id]
  availability_zone = "us-east-1a"

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y python3 python3-pip nginx
    pip3 install fastapi uvicorn
    
    # Create app directory
    mkdir -p /app
    
    # Create Python app file
    cat > /app/main.py << 'APPEOF'
from fastapi import FastAPI
import time
app = FastAPI()
@app.get("/health")
def health():
    return {"status": "ok", "models_loaded": true, "timestamp": time.time()}
@app.get("/")
def root():
    return {"message": "ready"}
APPEOF
    
    # Start app
    cd /app
    nohup python3 -m uvicorn main:app --host 127.0.0.1 --port 8000 >/dev/null 2>&1 &
    sleep 3
    
    # Update Nginx config
    cat > /etc/nginx/sites-available/default << 'NGXEOF'
upstream app {
    server 127.0.0.1:8000;
}
server {
    listen 80 default_server;
    server_name _;
    location / {
        proxy_pass http://app;
    }
}
NGXEOF
    
    # Restart Nginx
    systemctl restart nginx
  EOF
  )

  tags = {
    Name = "ddos-gateway-1"
  }
}

resource "aws_instance" "gateway2" {
  ami               = "ami-054d6a336762e438e"
  instance_type     = "t3.micro"
  subnet_id         = aws_subnet.public.id
  security_groups   = [aws_security_group.ddos.id]
  availability_zone = "us-east-1a"

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y python3 python3-pip nginx
    pip3 install fastapi uvicorn
    
    # Create app directory
    mkdir -p /app
    
    # Create Python app file
    cat > /app/main.py << 'APPEOF'
from fastapi import FastAPI
import time
app = FastAPI()
@app.get("/health")
def health():
    return {"status": "ok", "models_loaded": true, "timestamp": time.time()}
@app.get("/")
def root():
    return {"message": "ready"}
APPEOF
    
    # Start app
    cd /app
    nohup python3 -m uvicorn main:app --host 127.0.0.1 --port 8000 >/dev/null 2>&1 &
    sleep 3
    
    # Update Nginx config
    cat > /etc/nginx/sites-available/default << 'NGXEOF'
upstream app {
    server 127.0.0.1:8000;
}
server {
    listen 80 default_server;
    server_name _;
    location / {
        proxy_pass http://app;
    }
}
NGXEOF
    
    # Restart Nginx
    systemctl restart nginx
  EOF
  )

  tags = {
    Name = "ddos-gateway-2"
  }
}

output "gateway1_ip" {
  value = aws_instance.gateway1.public_ip
}

output "gateway2_ip" {
  value = aws_instance.gateway2.public_ip
}
