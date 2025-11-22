# Backend Instance Files - Complete Summary

## Overview

Backend instances run on **port 9000** in **private subnets** and serve as the actual application servers. The gateway instances (port 80) proxy requests to backend instances (port 9000).

---

## 📋 Complete File List

### Core Application Files (REQUIRED)

**Location:** `/home/ddos/app/ml_gateway/`

1. **app.py** (2-5 KB)
   - Main FastAPI application
   - Defines all API endpoints
   - Imports and uses ML models for predictions
   - Status: ✅ Available in your repo

2. **__init__.py** (<1 KB)
   - Python package initialization file
   - Can be empty or contain package-level imports
   - Status: ✅ Available in your repo

3. **detectors/** (10 KB, directory)
   - HTTP traffic analysis
   - Pattern detection for DDoS
   - Rate limiting logic
   - Status: ✅ Available in your repo
   
   Contains:
   - `__init__.py`
   - `http_detector.py`
   - Other detector modules

4. **utils/** (5 KB, directory)
   - Feature extraction from traffic
   - Input validation
   - Logging utilities
   - Helper functions
   - Status: ✅ Available in your repo
   
   Contains:
   - `__init__.py`
   - `feature_extractor.py`
   - `validators.py`
   - `logger.py`
   - `helpers.py`

5. **config.json** (1-2 KB)
   - Application configuration
   - Database settings
   - Model paths and thresholds
   - Status: ✅ Available in your repo

### Python Dependencies (REQUIRED)

**Location:** Root or `/home/ddos/requirements.txt`

6. **requirements.txt** (<1 KB)
   - All Python package dependencies
   - Status: ✅ Available in your repo
   
   **Must include:**
   ```
   fastapi>=0.104.0
   uvicorn[standard]>=0.24.0
   scikit-learn>=1.3.0
   numpy>=1.24.0
   pandas>=2.0.0
   pydantic>=2.5.0
   python-dotenv>=1.0.0
   httpx>=0.25.0
   ```

### ML Models & Feature Processing (REQUIRED)

**Location:** `/home/ddos/models/`

7. **hybrid_stage2_model_v3_real_benign.pkl** (50-200 MB)
   - Trained ML model for threat detection
   - Used for final predictions
   - Status: ✅ Available in your repo

8. **hybrid_stage2_scaler_v3_real_benign.pkl** (10 KB)
   - Feature scaler (StandardScaler)
   - Normalizes incoming features before prediction
   - Status: ✅ Available in your repo

9. **hybrid_stage2_label_encoder.pkl** (1 KB)
   - Label encoder for categorical variables
   - Converts string labels to numeric values
   - Status: ✅ Available in your repo

10. **hybrid_model_metrics_v2.json** (<1 KB)
    - Model performance metrics
    - Accuracy, precision, recall, F1 score
    - Status: ✅ Available in your repo (OPTIONAL but recommended)

### Environment & Configuration (REQUIRED AT DEPLOY TIME)

**Location:** `/home/ddos/.env`

11. **.env** (<1 KB, NOT in git for security)
    - Environment variables
    - Database credentials
    - API keys
    - Secret keys
    - Status: ⚠️ Create during deployment, not in repo
    
    **Example:**
    ```
    DATABASE_URL=postgresql://user:pass@localhost/db
    MODEL_PATH=/home/ddos/models/hybrid_stage2_model_v3.pkl
    LOG_LEVEL=INFO
    SECRET_KEY=your-secret-key
    CACHE_TTL=3600
    ```

### Web Server Configuration (REQUIRED)

**Location:** `/etc/nginx/sites-available/backend`

12. **nginx.conf** (1 KB)
    - Nginx reverse proxy configuration
    - Listens on port 9000
    - Proxies to Uvicorn (port 8000)
    - Status: ✅ Included in AWS deployment guide
    
    **Content:**
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
        }
    }
    ```

### Service Management (REQUIRED)

**Location:** `/etc/systemd/system/ddos-backend.service`

13. **Systemd Service File** (<1 KB)
    - Manages backend application startup
    - Auto-restart on failure
    - Logging configuration
    - Status: ✅ Included in AWS deployment guide

---

## 🗂️ File Organization on Instance

```
/home/ddos/
│
├── app/                          ← Application directory
│   ├── ml_gateway/               ← Package directory
│   │   ├── __init__.py
│   │   ├── app.py               ← Main FastAPI app
│   │   ├── config.json
│   │   ├── detectors/           ← Detection modules
│   │   │   ├── __init__.py
│   │   │   ├── http_detector.py
│   │   │   └── ...
│   │   └── utils/               ← Utility functions
│   │       ├── __init__.py
│   │       ├── feature_extractor.py
│   │       ├── validators.py
│   │       ├── logger.py
│   │       └── helpers.py
│   ├── main.py                  ← Entry point (optional)
│   ├── requirements.txt
│   └── .env                     ← Secrets (600 perms)
│
├── models/                       ← ML Models directory
│   ├── hybrid_stage2_model_v3_real_benign.pkl
│   ├── hybrid_stage2_scaler_v3_real_benign.pkl
│   ├── hybrid_stage2_label_encoder.pkl
│   └── hybrid_model_metrics_v2.json
│
├── logs/                         ← Logs directory
│   ├── app.log
│   ├── access.log
│   └── error.log
│
├── data/                         ← Runtime data (optional)
│   └── (cache, temporary files)
│
├── venv/                         ← Python virtual environment
│   ├── bin/
│   │   ├── python
│   │   ├── pip
│   │   └── uvicorn
│   └── lib/
│
└── config/                       ← Configuration files
    └── nginx.conf
```

---

## 📊 Space Requirements

| Component | Size | Notes |
|-----------|------|-------|
| OS (Ubuntu 22.04) | 2-4 GB | Base system |
| Python packages | 500 MB - 1 GB | scikit-learn, numpy, pandas |
| ML Models | 50-200 MB | Depends on model complexity |
| Source code | 5-20 MB | Application code |
| Logs (3 months) | 100-500 MB | Depends on traffic volume |
| Data/Cache | 100 MB - 1 GB | Runtime storage |
| **Recommended Total** | **10-20 GB** | Root volume size |

---

## 🚀 Deployment Steps

### Step 1: Create Backend Instance in Private Subnet

```powershell
# During EC2 launch:
# - VPC: ddos-vpc
# - Subnet: webserver-subnet-1 or webserver-subnet-2 (private)
# - Security Group: Allow port 9000 from gateway-sg
# - Instance Type: t3.micro (or larger for production)
```

### Step 2: User-Data Script

```bash
#!/bin/bash
set -euo pipefail

# Install dependencies
apt-get update -y
apt-get install -y python3 python3-pip python3-venv nginx curl git

# Create ddos user
useradd -m -s /bin/bash ddos || true

# Setup Python venv
su - ddos -c "python3 -m venv ~/venv"
su - ddos -c "~/venv/bin/pip install --upgrade pip"

# Download application from S3 or GitHub
cd /home/ddos/app
# Option 1: Clone from GitHub
git clone https://github.com/sanil0/Api_project.git . || true

# Install Python dependencies
su - ddos -c "~/venv/bin/pip install -r requirements.txt"

# Create necessary directories
mkdir -p /home/ddos/logs
chown ddos:ddos /home/ddos/logs

# Setup systemd service (see BACKEND_INSTANCE_REQUIREMENTS.md)
# Setup Nginx (see BACKEND_INSTANCE_REQUIREMENTS.md)

# Start services
systemctl enable --now ddos-backend
systemctl restart nginx
```

### Step 3: Verify Backend is Running

```bash
# From gateway instance
curl http://backend-private-ip:9000/health

# Should return
{"status":"ok","service":"backend"}
```

---

## ✅ Pre-Deployment Checklist

Before launching backend instance, verify you have:

**Application Files:**
- [ ] `ml_gateway/app.py` - Main application
- [ ] `ml_gateway/__init__.py` - Package init
- [ ] `ml_gateway/config.json` - Configuration
- [ ] `ml_gateway/detectors/` - Detection modules
- [ ] `ml_gateway/utils/` - Utility functions

**Dependencies:**
- [ ] `requirements.txt` - All pip packages listed

**ML Models:**
- [ ] `models/hybrid_stage2_model_v3_real_benign.pkl` - Trained model
- [ ] `models/hybrid_stage2_scaler_v3_real_benign.pkl` - Feature scaler
- [ ] `models/hybrid_stage2_label_encoder.pkl` - Label encoder
- [ ] `models/hybrid_model_metrics_v2.json` - Performance metrics

**Configuration:**
- [ ] `.env` file created (NOT in repo) with:
  - [ ] DATABASE_URL
  - [ ] MODEL_PATH
  - [ ] SECRET_KEY
  - [ ] Other environment variables

**Infrastructure:**
- [ ] Backend instance launched in private subnet
- [ ] Port 9000 allowed from gateway security group
- [ ] SSH key available for debugging
- [ ] At least 10 GB disk space allocated

---

## 🔒 Security Considerations

1. **Models Stored Securely**
   - Don't commit large models to git (use .gitignore)
   - Store in S3 with restricted IAM policies
   - Download during instance initialization

2. **.env File Security**
   - Never commit to git
   - Use 600 permissions (owner only)
   - Load via environment variables
   - Consider AWS Secrets Manager for production

3. **Network Security**
   - Port 9000 only accessible from gateway security group
   - No public IP on backend instance
   - All communication through private subnet

4. **File Ownership**
   - All app files owned by ddos:ddos user
   - Non-executable (644 for files, 755 for dirs)
   - Config files read-only

---

## 📈 Scaling Backend

### Add More Backend Instances

1. Launch additional instances in private subnets
2. Run same user-data script
3. Add to internal ALB target group (port 9000)
4. Increase Nginx worker connections

### High-Availability Setup

```
Gateway-1 (Public) ──┐
                     ├─→ Internal ALB (port 9000) ──┬─→ Backend-1 (Private)
Gateway-2 (Public) ──┘                              ├─→ Backend-2 (Private)
                                                    └─→ Backend-3 (Private)
```

---

## 📚 Documentation Files

- **BACKEND_INSTANCE_REQUIREMENTS.md** - Complete details
- **BACKEND_FILES_QUICK_REFERENCE.md** - Quick lookup table
- **AWS_DEPLOYMENT_VERIFICATION.md** - Verification steps
- **AWS_QUICK_REFERENCE.md** - SSH/management commands

---

## 🎯 Summary

**Total files needed:** 13 categories (mostly already in repo)  
**Total size:** 50-200 MB (plus ML models)  
**Deployment time:** 5-10 minutes per instance  
**Port:** 9000 (private subnet only)  
**Monitoring:** /logs directory + systemd logs

All files are available in your GitHub repo. Backend instances will pull code from there during initialization.

For complete details, see: `BACKEND_INSTANCE_REQUIREMENTS.md`
