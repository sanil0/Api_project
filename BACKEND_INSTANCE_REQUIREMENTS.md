# Backend Instance Requirements - Complete File List

## Overview

Backend instances run on port 9000 (private subnets) and serve as the actual application servers behind the gateway layer. They're optional in the basic setup but required for production to provide the gateway something to proxy traffic to.

---

## 🏗️ Backend Instance Architecture

```
Internet
    ↓
Gateway Instance (Port 80) → Nginx (Port 80)
    ↓
Uvicorn (Port 8000)
    ↓
Backend Instance (Port 9000) → Nginx/Uvicorn (Port 9000)
    ↓
Your Application
```

---

## 📋 Required Files & Folders

### Core Application Files

#### 1. **ml_gateway/app.py**
- **Purpose:** FastAPI backend application
- **Location on Instance:** `/home/ddos/app/app.py`
- **Size:** ~2-5 KB
- **Content:** FastAPI endpoints serving actual application logic
- **Ownership:** ddos:ddos
- **Permissions:** 644

**What to include:**
```python
from fastapi import FastAPI, Request
import httpx

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok", "service": "backend"}

@app.get("/api/threat-analysis")
def analyze_threat(ip: str):
    # Your threat analysis logic
    return {"ip": ip, "threat_level": "low"}

@app.post("/api/report-attack")
def report_attack(data: dict):
    # Store attack data
    return {"status": "recorded"}

# ... more endpoints
```

#### 2. **ml_gateway/__init__.py**
- **Purpose:** Python package init file
- **Location on Instance:** `/home/ddos/app/ml_gateway/__init__.py`
- **Size:** <1 KB
- **Content:** Can be empty or contain package initialization

#### 3. **ml_gateway/config.json**
- **Purpose:** Application configuration
- **Location on Instance:** `/home/ddos/app/config.json`
- **Size:** 1-2 KB
- **Content:** Database credentials, API keys, feature flags
- **Note:** Should use environment variables for secrets, not hardcoded

**Example:**
```json
{
    "database": {
        "host": "${DB_HOST}",
        "port": "${DB_PORT}",
        "name": "${DB_NAME}"
    },
    "ml_model": {
        "path": "/home/ddos/models/hybrid_stage2_model_v3.pkl",
        "threshold": 0.7
    },
    "cache": {
        "enabled": true,
        "ttl": 3600
    }
}
```

#### 4. **ml_gateway/detectors/** (Directory)
- **Purpose:** Detection modules/plugins
- **Location on Instance:** `/home/ddos/app/ml_gateway/detectors/`
- **Contains:**
  - `__init__.py` - Package init
  - `http_detector.py` - HTTP traffic analysis
  - `pattern_detector.py` - Pattern recognition
  - `rate_limiter.py` - Rate limiting logic
  - Other detection modules

**Example file:**
```python
# http_detector.py
class HTTPDetector:
    def __init__(self, model):
        self.model = model
    
    def detect(self, request):
        features = self.extract_features(request)
        prediction = self.model.predict(features)
        return prediction > 0.7
```

#### 5. **ml_gateway/utils/** (Directory)
- **Purpose:** Utility functions
- **Location on Instance:** `/home/ddos/app/ml_gateway/utils/`
- **Contains:**
  - `__init__.py` - Package init
  - `feature_extractor.py` - Extract features from traffic
  - `logger.py` - Logging utilities
  - `validators.py` - Input validation
  - `helpers.py` - General helpers

### ML Models & Trained Data

#### 6. **models/hybrid_stage2_model_v3_real_benign.pkl**
- **Purpose:** Trained ML model for threat detection
- **Location on Instance:** `/home/ddos/models/hybrid_stage2_model_v3_real_benign.pkl`
- **Size:** ~50-200 MB
- **Format:** Pickled sklearn model
- **Note:** Required for ML-based detection
- **Ownership:** ddos:ddos
- **Permissions:** 644

#### 7. **models/hybrid_stage2_scaler_v3_real_benign.pkl**
- **Purpose:** Feature scaler (normalize inputs)
- **Location on Instance:** `/home/ddos/models/hybrid_stage2_scaler_v3_real_benign.pkl`
- **Size:** ~10 KB
- **Format:** Pickled sklearn StandardScaler
- **Note:** Used to scale incoming features before prediction
- **Ownership:** ddos:ddos
- **Permissions:** 644

#### 8. **models/hybrid_stage2_label_encoder.pkl**
- **Purpose:** Label encoder for categorical features
- **Location on Instance:** `/home/ddos/models/hybrid_stage2_label_encoder.pkl`
- **Size:** ~1 KB
- **Format:** Pickled sklearn LabelEncoder
- **Ownership:** ddos:ddos
- **Permissions:** 644

#### 9. **models/hybrid_model_metrics_v2.json** (Optional)
- **Purpose:** Model performance metrics
- **Location on Instance:** `/home/ddos/models/hybrid_model_metrics_v2.json`
- **Size:** <1 KB
- **Content:** Accuracy, precision, recall, F1 score
- **Use:** For validation and monitoring

**Example:**
```json
{
    "accuracy": 0.987,
    "precision": 0.992,
    "recall": 0.981,
    "f1_score": 0.986,
    "roc_auc": 0.995,
    "training_samples": 100000,
    "testing_samples": 20000
}
```

### Configuration & Deployment Files

#### 10. **requirements.txt**
- **Purpose:** Python dependencies
- **Location on Instance:** `/home/ddos/requirements.txt`
- **Size:** <1 KB
- **Content:** All pip packages needed

**Minimal contents:**
```
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
httpx>=0.25.0
pydantic>=2.5.0
scikit-learn>=1.3.0
numpy>=1.24.0
pandas>=2.0.0
python-dotenv>=1.0.0
```

#### 11. **.env** (Optional but Recommended)
- **Purpose:** Environment variables
- **Location on Instance:** `/home/ddos/.env`
- **Size:** <1 KB
- **Ownership:** ddos:ddos
- **Permissions:** 600 (read/write owner only)
- **Content:** Secrets and configuration

**Example:**
```
DATABASE_URL=postgresql://user:pass@localhost/dbname
MODEL_PATH=/home/ddos/models/hybrid_stage2_model_v3.pkl
LOG_LEVEL=INFO
CACHE_TTL=3600
SECRET_KEY=your-secret-key-here
```

#### 12. **config/nginx.conf** (For Backend Nginx)
- **Purpose:** Nginx configuration
- **Location on Instance:** `/etc/nginx/sites-available/backend`
- **Size:** ~1 KB
- **Content:** Reverse proxy to Uvicorn on 9000

**Example:**
```nginx
upstream backend {
    server 127.0.0.1:8000;
}

server {
    listen 9000;
    server_name _;

    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

#### 13. **start_backend.sh** or **start_backend.ps1**
- **Purpose:** Startup script
- **Location on Instance:** `/home/ddos/start_backend.sh`
- **Size:** <1 KB
- **Content:** Commands to start application

**Example bash:**
```bash
#!/bin/bash
cd /home/ddos/app
source /home/ddos/venv/bin/activate
uvicorn ml_gateway.app:app --host 0.0.0.0 --port 8000 --workers 4
```

### Logging & Monitoring

#### 14. **logs/** (Directory)
- **Purpose:** Application logs
- **Location on Instance:** `/home/ddos/logs/`
- **Ownership:** ddos:ddos
- **Permissions:** 755
- **Auto-generated:** Should be created by application

**Files created at runtime:**
- `app.log` - Application logs
- `access.log` - HTTP access logs
- `error.log` - Error logs

#### 15. **data/** (Optional - For Caching/Storage)
- **Purpose:** Runtime data storage
- **Location on Instance:** `/home/ddos/data/`
- **Ownership:** ddos:ddos
- **Permissions:** 755
- **Content:** Cache files, temporary data

---

## 📦 Deployment Package Structure

```
/home/ddos/
├── app/
│   ├── main.py (or __main__.py)
│   ├── ml_gateway/
│   │   ├── __init__.py
│   │   ├── app.py
│   │   ├── config.json
│   │   ├── detectors/
│   │   │   ├── __init__.py
│   │   │   ├── http_detector.py
│   │   │   ├── pattern_detector.py
│   │   │   └── rate_limiter.py
│   │   └── utils/
│   │       ├── __init__.py
│   │       ├── feature_extractor.py
│   │       ├── logger.py
│   │       ├── validators.py
│   │       └── helpers.py
│   ├── requirements.txt
│   └── .env (secrets, 600 permissions)
│
├── models/
│   ├── hybrid_stage2_model_v3_real_benign.pkl
│   ├── hybrid_stage2_scaler_v3_real_benign.pkl
│   ├── hybrid_stage2_label_encoder.pkl
│   └── hybrid_model_metrics_v2.json
│
├── logs/
│   ├── app.log
│   ├── access.log
│   └── error.log
│
├── data/
│   └── (runtime cache/data)
│
├── venv/
│   └── (Python virtual environment)
│
└── config/
    └── nginx.conf
```

---

## 🔧 Systemd Service File (For Backend)

**Location on Instance:** `/etc/systemd/system/ddos-backend.service`

**Content:**
```ini
[Unit]
Description=DDoS Backend API Service
After=network.target

[Service]
Type=notify
User=ddos
WorkingDirectory=/home/ddos/app
ExecStart=/home/ddos/venv/bin/uvicorn ml_gateway.app:app --host 0.0.0.0 --port 8000 --workers 4
Restart=always
RestartSec=5
StandardOutput=append:/home/ddos/logs/app.log
StandardError=append:/home/ddos/logs/error.log
Environment="PATH=/home/ddos/venv/bin"
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
```

---

## 📥 Total Size Requirements

| Component | Size | Notes |
|-----------|------|-------|
| ML Models | 50-200 MB | Depends on model size |
| Python Packages (venv) | 500 MB - 1 GB | Scikit-learn, numpy, pandas |
| Source Code | 5-20 MB | ml_gateway/, config, requirements |
| Logs | 100 MB - 1 GB | Grows over time |
| **Total** | **~2-3 GB** | For small instance |

**Recommendation:** Use at least 10 GB root volume for backend instances

---

## 🚀 Backend Deployment User Data Script

```bash
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "[START] Backend initialization"

# Update system
apt-get update -y
apt-get upgrade -y

# Install packages
apt-get install -y python3 python3-pip python3-venv nginx curl wget git

# Create ddos user
useradd -m -s /bin/bash ddos || true

# Setup Python venv
su - ddos -c "python3 -m venv ~/venv"
su - ddos -c "~/venv/bin/pip install --upgrade pip"

# Clone or download application
mkdir -p /home/ddos/app
cd /home/ddos/app

# Copy application files (you would push these to S3 or GitHub)
# For now, assume they're already available or clone from repo
git clone https://github.com/sanil0/Api_project.git . || true

# Install Python dependencies
su - ddos -c "~/venv/bin/pip install -r requirements.txt"

# Create logs directory
mkdir -p /home/ddos/logs
chown ddos:ddos /home/ddos/logs

# Create models directory if not exists
mkdir -p /home/ddos/models
chown ddos:ddos /home/ddos/models

# Setup systemd service
cat > /etc/systemd/system/ddos-backend.service << 'SVCEOF'
[Unit]
Description=DDoS Backend API Service
After=network.target

[Service]
Type=notify
User=ddos
WorkingDirectory=/home/ddos/app
ExecStart=/home/ddos/venv/bin/uvicorn ml_gateway.app:app --host 0.0.0.0 --port 8000 --workers 4
Restart=always
RestartSec=5
StandardOutput=append:/home/ddos/logs/app.log
StandardError=append:/home/ddos/logs/error.log
Environment="PATH=/home/ddos/venv/bin"
Environment="PYTHONUNBUFFERED=1"

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now ddos-backend

# Setup Nginx
cat > /etc/nginx/sites-available/backend << 'NGXEOF'
upstream backend {
    server 127.0.0.1:8000;
}

server {
    listen 9000 default_server;
    server_name _;

    location / {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 15s;
        proxy_connect_timeout 10s;
    }
}
NGXEOF

ln -sf /etc/nginx/sites-available/backend /etc/nginx/sites-enabled/backend
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl restart nginx

echo "[OK] Backend initialized"
```

---

## ✅ Checklist for Backend Instance

Before launching backend instances, ensure you have:

- [ ] `ml_gateway/app.py` with all endpoints
- [ ] `ml_gateway/__init__.py`
- [ ] `ml_gateway/config.json`
- [ ] `ml_gateway/detectors/` directory with detector modules
- [ ] `ml_gateway/utils/` directory with utility modules
- [ ] `requirements.txt` with all dependencies
- [ ] `.env` file with environment variables (not in repo, add at deploy time)
- [ ] ML models in `models/` directory
- [ ] `models/*.pkl` files (model, scaler, label encoder)
- [ ] `models/*.json` files (metrics, optional)
- [ ] Systemd service configuration
- [ ] Nginx configuration for port 9000
- [ ] At least 10 GB disk space
- [ ] Python 3.8+ available

---

## 🔒 Security Considerations

1. **Models should NOT be in public GitHub** → Store in S3 with restricted access
2. **Secrets in .env file** → Add via environment variables at deployment
3. **Restrict port 9000** → Only allow traffic from gateway security group
4. **Use read-only mounts** → Models should be read-only after deployment
5. **Enable logging** → All requests logged for audit trail
6. **Regular backups** → Backup models and logs regularly

---

## 🚀 Deployment Steps

1. **Launch instance in private subnet** with security group allowing port 9000 from gateway SG
2. **Run user data script** above during instance launch
3. **Wait 5-10 minutes** for initialization
4. **SSH from gateway instance** to verify backend is running
5. **Test endpoint:** `curl http://backend-ip:9000/health`

---

## Summary

Backend instances require:
- **Core app code** (ml_gateway/)
- **ML models** (models/)
- **Configuration** (requirements.txt, .env, config.json)
- **Service management** (systemd)
- **Reverse proxy** (Nginx on port 9000)
- **Logging** (logs/ directory)

All files are in your workspace and ready to be packaged for backend deployment.
