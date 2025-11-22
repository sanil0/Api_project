# Backend Instance - Visual File Map

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ AWS VPC: 10.0.0.0/16                                             │
│                                                                   │
│ ┌────────────────────────────┐  ┌──────────────────────────────┐│
│ │ PUBLIC SUBNET              │  │ PRIVATE SUBNET               ││
│ │ (us-east-1a)              │  │ (us-east-1a)                ││
│ │ 10.0.1.0/24               │  │ 10.0.101.0/24               ││
│ │                            │  │                              ││
│ │ ┌──────────────────────┐   │  │ ┌──────────────────────────┐ ││
│ │ │ Gateway Instance     │   │  │ │ Backend Instance        │ ││
│ │ │ (t3.micro)          │   │  │ │ (t3.micro)              │ ││
│ │ │ Port 80: Nginx      │──────┼─┼─Port 9000: Nginx       │ ││
│ │ │ Port 8000: Uvicorn  │   │  │ │ Port 8000: Uvicorn    │ ││
│ │ └──────────────────────┘   │  │ └──────────────────────────┘ ││
│ └────────────────────────────┘  └──────────────────────────────┘│
│                                                                   │
│ Security Groups:                                                 │
│ - gateway-sg: Allow 80, 443, 22 from 0.0.0.0/0                │
│ - webserver-sg: Allow 9000 from gateway-sg                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Backend Instance File Hierarchy

```
/home/ddos/
│
├── app/                          Directory: /home/ddos/app
│   ├── ml_gateway/               ✅ REQUIRED
│   │   ├── __init__.py           ✅ Essential
│   │   ├── app.py                ✅ Essential (2-5 KB)
│   │   ├── config.json           ✅ Essential (1-2 KB)
│   │   │
│   │   ├── detectors/            ✅ REQUIRED
│   │   │   ├── __init__.py       ✅
│   │   │   ├── http_detector.py  ✅
│   │   │   ├── pattern_detector.py
│   │   │   └── rate_limiter.py
│   │   │
│   │   └── utils/                ✅ REQUIRED
│   │       ├── __init__.py       ✅
│   │       ├── feature_extractor.py ✅
│   │       ├── logger.py         ✅
│   │       ├── validators.py     ✅
│   │       └── helpers.py
│   │
│   ├── requirements.txt          ✅ REQUIRED (<1 KB)
│   │   - fastapi>=0.104.0
│   │   - uvicorn[standard]>=0.24.0
│   │   - scikit-learn>=1.3.0
│   │   - numpy>=1.24.0
│   │   - pandas>=2.0.0
│   │   - pydantic>=2.5.0
│   │   - python-dotenv>=1.0.0
│   │   - httpx>=0.25.0
│   │
│   └── .env                      ⚠️ REQUIRED AT DEPLOY TIME
│       (Not in git - add via environment variables)
│       - DATABASE_URL
│       - MODEL_PATH
│       - SECRET_KEY
│       - LOG_LEVEL
│       - CACHE_TTL
│
├── models/                       Directory: /home/ddos/models
│   │
│   ├── hybrid_stage2_model_v3_real_benign.pkl
│   │   ✅ REQUIRED (50-200 MB)
│   │   └─ Trained ML model for threat detection
│   │
│   ├── hybrid_stage2_scaler_v3_real_benign.pkl
│   │   ✅ REQUIRED (10 KB)
│   │   └─ Feature normalization/scaling
│   │
│   ├── hybrid_stage2_label_encoder.pkl
│   │   ✅ REQUIRED (1 KB)
│   │   └─ Categorical feature encoding
│   │
│   └── hybrid_model_metrics_v2.json
│       ⚠️ OPTIONAL (<1 KB)
│       └─ Model performance metrics
│
├── logs/                         Directory: /home/ddos/logs
│   ├── app.log                   (Created at runtime)
│   ├── access.log                (Created at runtime)
│   └── error.log                 (Created at runtime)
│
├── data/                         Directory: /home/ddos/data (Optional)
│   └── (Cache and temporary runtime files)
│
├── venv/                         Directory: /home/ddos/venv (Auto-created)
│   ├── bin/
│   │   ├── python
│   │   ├── pip
│   │   └── uvicorn ← Runs the app
│   └── lib/
│       └── (Python packages)
│
└── config/                       Directory: /home/ddos/config
    └── nginx.conf               ✅ REQUIRED (1 KB)
        └─ Reverse proxy on port 9000

System Files (Not in /home/ddos):
├── /etc/nginx/sites-available/backend
│   ✅ REQUIRED (1 KB)
│   └─ Nginx configuration (created during deploy)
│
├── /etc/systemd/system/ddos-backend.service
│   ✅ REQUIRED (<1 KB)
│   └─ Service management (created during deploy)
│
└── /var/log/user-data.log
    (Deployment log)
```

---

## File Status in Your Repository

### ✅ AVAILABLE (Ready to Deploy)

```
📁 ml_gateway/
   ├── ✅ app.py
   ├── ✅ __init__.py
   ├── ✅ config.json
   ├── ✅ detectors/
   │   ├── __init__.py
   │   └── http_detector.py
   └── ✅ utils/
       ├── __init__.py
       └── (other utilities)

📁 models/
   ├── ✅ hybrid_stage2_model_v3_real_benign.pkl
   ├── ✅ hybrid_stage2_scaler_v3_real_benign.pkl
   ├── ✅ hybrid_stage2_label_encoder.pkl
   └── ✅ hybrid_model_metrics_v2.json

📄 ✅ requirements.txt

📁 config/
   └── ✅ nginx.conf
```

### ⚠️ NEEDS TO BE ADDED AT DEPLOYMENT

```
📄 .env
   - Add via environment variables
   - Do NOT commit to git
   - Contains secrets and credentials
```

### 🔧 AUTO-GENERATED DURING DEPLOYMENT

```
📁 logs/
   ├── app.log
   ├── access.log
   └── error.log

📁 venv/
   └── (Created by Python venv command)

📄 /etc/systemd/system/ddos-backend.service
   └── (Created by user-data script)

📄 /etc/nginx/sites-enabled/backend
   └── (Linked by user-data script)
```

---

## Data Flow Diagram

```
Request from Gateway
      ↓
Nginx (Port 9000)
      ↓
Reverse Proxy
      ↓
Uvicorn (Port 8000)
      ↓
FastAPI (app.py)
      ↓
Routes to Endpoint
      ↓
Load ML Models
      ├─ hybrid_stage2_model_v3_real_benign.pkl
      ├─ hybrid_stage2_scaler_v3_real_benign.pkl
      └─ hybrid_stage2_label_encoder.pkl
      ↓
Make Prediction
      ↓
Return Response
      ↓
Nginx Proxy
      ↓
Back to Gateway
```

---

## Deployment Sequence

```
1. Launch EC2 Instance (Private Subnet)
   ├─ Region: us-east-1
   ├─ Subnet: webserver-subnet-1 or 2
   ├─ Security Group: webserver-sg
   ├─ Instance Type: t3.micro (or larger)
   ├─ Volume: 10-20 GB
   └─ User Data: deployment script (see BACKEND_INSTANCE_REQUIREMENTS.md)

2. User Data Script Execution (5-10 minutes)
   ├─ Install OS packages (python3, nginx, git)
   ├─ Create ddos user
   ├─ Setup Python venv
   ├─ Clone/download application code
   ├─ Install Python dependencies (pip install -r requirements.txt)
   ├─ Create necessary directories
   ├─ Setup systemd service
   ├─ Configure Nginx
   ├─ Load ML models
   └─ Start services

3. Verify Backend is Running
   ├─ SSH from gateway instance
   ├─ Check systemd service: sudo systemctl status ddos-backend
   ├─ View logs: sudo journalctl -u ddos-backend -f
   ├─ Test endpoint: curl http://backend-ip:9000/health
   └─ Confirm response: {"status":"ok"}

4. Register with Load Balancer (Optional)
   ├─ Add to Internal ALB target group
   ├─ Configure health checks (port 9000)
   └─ Start receiving traffic
```

---

## File Size Reference

| Component | Size | Type |
|-----------|------|------|
| `ml_gateway/app.py` | 2-5 KB | Source |
| `ml_gateway/detectors/` | 5-10 KB | Source |
| `ml_gateway/utils/` | 5-10 KB | Source |
| `requirements.txt` | <1 KB | Config |
| Total Source Code | 20 KB | - |
| --- | --- | --- |
| `hybrid_stage2_model_v3.pkl` | 50-200 MB | Model |
| `hybrid_stage2_scaler_v3.pkl` | 10 KB | Model |
| `hybrid_stage2_label_encoder.pkl` | 1 KB | Model |
| Total Model Files | ~60-210 MB | - |
| --- | --- | --- |
| Python Packages (venv) | 500 MB - 1 GB | Dependencies |
| OS (Ubuntu 22.04) | 2-4 GB | System |
| Logs (3 months) | 100-500 MB | Runtime |
| **TOTAL Disk Needed** | **10-20 GB** | - |

---

## Quick Deployment Checklist

```
Pre-Deployment:
□ Fork/clone https://github.com/sanil0/Api_project.git
□ Verify all files listed above are in repo
□ Create .env file with secrets (keep locally, not in git)
□ Prepare .env content:
  - DATABASE_URL
  - MODEL_PATH
  - SECRET_KEY
  - LOG_LEVEL

Deployment:
□ Create private subnet in VPC
□ Create webserver security group
□ Launch t3.micro instance with user-data script
□ Wait 5-10 minutes for initialization
□ SSH into instance and verify
□ Check systemd service status
□ Test /health endpoint
□ Add to load balancer (optional)

Verification:
□ curl http://backend-ip:9000/health returns JSON
□ systemd service shows "active (running)"
□ /logs directory contains app.log
□ No errors in sudo journalctl -u ddos-backend
```

---

## Security Checklist

```
File Ownership:
□ /home/ddos/ owned by ddos:ddos
□ All .py files 644 permissions
□ All directories 755 permissions
□ .env file 600 permissions (owner only)

Network:
□ Port 9000 only from gateway-sg
□ No public IP on backend instance
□ Only private subnet placement
□ SSH (port 22) restricted if possible

Secrets:
□ .env file NOT in git
□ DATABASE credentials in .env only
□ API keys in .env only
□ SECRET_KEY in .env only

Models:
□ Models stored in /home/ddos/models
□ Read-only permissions after deployment
□ Backed up to S3 regularly
□ Version controlled outside git (in S3)
```

---

For detailed information, see:
- **BACKEND_INSTANCE_REQUIREMENTS.md** - Complete guide
- **BACKEND_FILES_QUICK_REFERENCE.md** - Quick lookup table
- **AWS_DEPLOYMENT_VERIFICATION.md** - Verification steps
