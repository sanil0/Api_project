# Backend Files Quick Reference

## Essential Files for Backend Instance

### Python Application Files

| File/Directory | Location on Instance | Size | Type | Required |
|---|---|---|---|---|
| `ml_gateway/app.py` | `/home/ddos/app/ml_gateway/app.py` | 2-5 KB | FastAPI endpoints | ✅ YES |
| `ml_gateway/__init__.py` | `/home/ddos/app/ml_gateway/__init__.py` | <1 KB | Package init | ✅ YES |
| `ml_gateway/detectors/` | `/home/ddos/app/ml_gateway/detectors/` | 10 KB | Detection modules | ✅ YES |
| `ml_gateway/utils/` | `/home/ddos/app/ml_gateway/utils/` | 5 KB | Utility functions | ✅ YES |
| `ml_gateway/config.json` | `/home/ddos/app/config.json` | 1-2 KB | Configuration | ✅ YES |
| `requirements.txt` | `/home/ddos/requirements.txt` | <1 KB | Python dependencies | ✅ YES |

### ML Models & Data

| File | Location on Instance | Size | Type | Required |
|---|---|---|---|---|
| `hybrid_stage2_model_v3_real_benign.pkl` | `/home/ddos/models/hybrid_stage2_model_v3_real_benign.pkl` | 50-200 MB | Trained model | ✅ YES |
| `hybrid_stage2_scaler_v3_real_benign.pkl` | `/home/ddos/models/hybrid_stage2_scaler_v3_real_benign.pkl` | 10 KB | Feature scaler | ✅ YES |
| `hybrid_stage2_label_encoder.pkl` | `/home/ddos/models/hybrid_stage2_label_encoder.pkl` | 1 KB | Label encoder | ✅ YES |
| `hybrid_model_metrics_v2.json` | `/home/ddos/models/hybrid_model_metrics_v2.json` | <1 KB | Model metrics | ⚠️ Optional |

### Configuration & Deployment

| File | Location on Instance | Size | Type | Required |
|---|---|---|---|---|
| `.env` | `/home/ddos/.env` | <1 KB | Environment variables | ✅ YES* |
| `nginx.conf` | `/etc/nginx/sites-available/backend` | 1 KB | Nginx config | ✅ YES |
| Systemd service | `/etc/systemd/system/ddos-backend.service` | <1 KB | Service mgmt | ✅ YES |

*Not in repo for security; added at deployment time via environment variables

### Runtime Directories

| Directory | Location | Purpose | Auto-created |
|---|---|---|---|
| `logs/` | `/home/ddos/logs/` | Application logs | No, create manually |
| `data/` | `/home/ddos/data/` | Cache/runtime data | No, optional |
| `venv/` | `/home/ddos/venv/` | Python virtual env | Yes, via user-data |
| `models/` | `/home/ddos/models/` | ML models | No, copy from S3 |

---

## File Dependency Map

```
Backend Instance Startup
    ↓
requirements.txt (Python packages)
    ↓
    ├─→ ml_gateway/app.py
    ├─→ ml_gateway/detectors/ 
    ├─→ ml_gateway/utils/
    └─→ .env (secrets)
    ↓
Uvicorn Server (port 8000)
    ↓
Nginx Reverse Proxy (port 9000)
    ↓
Load Model Files
    ├─→ hybrid_stage2_model_v3_real_benign.pkl
    ├─→ hybrid_stage2_scaler_v3_real_benign.pkl
    └─→ hybrid_stage2_label_encoder.pkl
    ↓
Ready to Accept Requests from Gateway
```

---

## Total Disk Space Required

```
ML Models:           50-200 MB
Python Packages:     500 MB - 1 GB
Source Code:         5-20 MB
OS & System:         2-4 GB
Logs (3 months):     100-500 MB
---
Recommended Total:   10-20 GB
```

---

## Files Currently in Your Repo

### Available in `/ml_gateway/`:
```
✅ app.py
✅ __init__.py
✅ config.json
✅ detectors/
   ✅ __init__.py
   ✅ http_detector.py
✅ utils/
   ✅ (check contents)
```

### Available in `/models/`:
```
✅ hybrid_stage2_model_v3_real_benign.pkl
✅ hybrid_stage2_scaler_v3_real_benign.pkl
✅ hybrid_stage2_label_encoder.pkl
✅ hybrid_model_metrics_v2.json
✅ (and other model files)
```

### Available in root:
```
✅ requirements.txt
✅ config/ (with nginx.conf)
⚠️ .env (NOT in repo - add at deploy time)
```

---

## Quick Setup Command

```bash
# Package everything for backend deployment
tar -czf backend-app.tar.gz \
  ml_gateway/ \
  models/ \
  requirements.txt \
  config/ \
  --exclude=__pycache__ \
  --exclude=*.pyc

# Upload to S3
aws s3 cp backend-app.tar.gz s3://your-bucket/backend-app.tar.gz

# Then in user-data script:
# aws s3 cp s3://your-bucket/backend-app.tar.gz /tmp/
# tar -xzf /tmp/backend-app.tar.gz -C /home/ddos/app/
```

---

## File Ownership After Deployment

```
/home/ddos/
├── app/                    (ddos:ddos, 755)
│   ├── ml_gateway/         (ddos:ddos, 755)
│   │   ├── *.py            (ddos:ddos, 644)
│   │   ├── detectors/      (ddos:ddos, 755)
│   │   └── utils/          (ddos:ddos, 755)
│   ├── requirements.txt    (ddos:ddos, 644)
│   ├── .env                (ddos:ddos, 600) ← SECURE
│   └── main.py             (ddos:ddos, 644)
│
├── models/                 (ddos:ddos, 755)
│   ├── *.pkl               (ddos:ddos, 644)
│   └── *.json              (ddos:ddos, 644)
│
├── logs/                   (ddos:ddos, 755)
│   ├── app.log             (ddos:ddos, 644)
│   ├── access.log          (ddos:ddos, 644)
│   └── error.log           (ddos:ddos, 644)
│
└── venv/                   (ddos:ddos, 755)
    └── (Python packages)
```

---

## Security Notes

1. **Models should be read-only** after deployment
2. **.env file should have 600 permissions** (only owner read/write)
3. **Secrets NOT in version control** → Use AWS Secrets Manager or environment variables
4. **Logs should be rotatable** → Set up logrotate for long-term storage
5. **Backups needed for** → Models and metrics files
6. **Port 9000 restricted** → Only from gateway security group

---

See `BACKEND_INSTANCE_REQUIREMENTS.md` for complete details.
