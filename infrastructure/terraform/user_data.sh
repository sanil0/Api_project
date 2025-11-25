#!/bin/bash

# Simplified user data script without IAM dependencies
set -e

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting EC2 instance initialization..."
echo "Timestamp: $(date)"

# Update system
apt-get update -y
apt-get upgrade -y

# Install required packages
apt-get install -y python3 python3-pip python3-venv nginx supervisor awscli unzip

# Create application directory
mkdir -p /opt/ddos-detection
cd /opt/ddos-detection

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install fastapi uvicorn pandas scikit-learn numpy pydantic boto3 python-multipart

# Create application user
useradd -m -s /bin/bash ddos-user || true

# Download models from S3 (public access)
echo "Downloading models from S3..."
mkdir -p models
aws s3 cp s3://${s3_bucket_name}/hybrid_stage1_model_v2.pkl models/ || echo "Failed to download Stage 1 model"
aws s3 cp s3://${s3_bucket_name}/hybrid_stage1_scaler_v2.pkl models/ || echo "Failed to download Stage 1 scaler"
aws s3 cp s3://${s3_bucket_name}/hybrid_stage2_model_v3_real_benign.pkl models/ || echo "Failed to download Stage 2 model"
aws s3 cp s3://${s3_bucket_name}/hybrid_stage2_scaler_v3_real_benign.pkl models/ || echo "Failed to download Stage 2 scaler"

# Create simplified FastAPI application
cat > app.py << 'EOF'
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import pandas as pd
import numpy as np
import pickle
import time
import logging
from typing import List, Dict, Any
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Hybrid DDoS Detection API", version="3.0")

# Global variables for models
stage1_model = None
stage1_scaler = None
stage2_model = None
stage2_scaler = None

def load_models():
    """Load ML models with error handling"""
    global stage1_model, stage1_scaler, stage2_model, stage2_scaler
    
    try:
        logger.info("Loading models...")
        
        # Try to load Stage 1 models
        try:
            with open('/opt/ddos-detection/models/hybrid_stage1_model_v2.pkl', 'rb') as f:
                stage1_model = pickle.load(f)
            with open('/opt/ddos-detection/models/hybrid_stage1_scaler_v2.pkl', 'rb') as f:
                stage1_scaler = pickle.load(f)
            logger.info("Stage 1 models loaded successfully")
        except Exception as e:
            logger.warning(f"Failed to load Stage 1 models: {e}")
            
        # Try to load Stage 2 models
        try:
            with open('/opt/ddos-detection/models/hybrid_stage2_model_v3_real_benign.pkl', 'rb') as f:
                stage2_model = pickle.load(f)
            with open('/opt/ddos-detection/models/hybrid_stage2_scaler_v3_real_benign.pkl', 'rb') as f:
                stage2_scaler = pickle.load(f)
            logger.info("Stage 2 models loaded successfully")
        except Exception as e:
            logger.warning(f"Failed to load Stage 2 models: {e}")
            
        if not any([stage1_model, stage2_model]):
            raise Exception("No models could be loaded")
            
    except Exception as e:
        logger.error(f"Critical error loading models: {e}")
        # Continue with degraded functionality

class PredictionRequest(BaseModel):
    features: List[List[float]]
    
class PredictionResponse(BaseModel):
    predictions: List[Dict[str, Any]]
    processing_time: float
    model_info: Dict[str, str]

@app.on_event("startup")
async def startup_event():
    """Initialize models on startup"""
    load_models()

@app.get("/health")
async def health_check():
    """Health check endpoint for ALB"""
    return {
        "status": "healthy",
        "timestamp": time.time(),
        "models_loaded": {
            "stage1": stage1_model is not None,
            "stage2": stage2_model is not None
        }
    }

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "Hybrid DDoS Detection API",
        "version": "3.0",
        "endpoints": ["/predict", "/health", "/info"]
    }

@app.get("/info")
async def model_info():
    """Get model information"""
    return {
        "stage1_loaded": stage1_model is not None,
        "stage2_loaded": stage2_model is not None,
        "features": {
            "stage1": 27 if stage1_model else 0,
            "stage2": 82 if stage2_model else 0
        }
    }

@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest):
    """Make predictions using hybrid ensemble"""
    start_time = time.time()
    
    try:
        features_array = np.array(request.features)
        predictions = []
        
        for feature_vector in features_array:
            prediction_result = {
                "stage1_prediction": None,
                "stage2_prediction": None,
                "final_prediction": "benign",
                "confidence": 0.5
            }
            
            # Stage 1 prediction (KDD21+)
            if stage1_model and stage1_scaler and len(feature_vector) >= 27:
                try:
                    stage1_features = feature_vector[:27].reshape(1, -1)
                    stage1_scaled = stage1_scaler.transform(stage1_features)
                    stage1_pred = stage1_model.predict(stage1_scaled)[0]
                    stage1_proba = stage1_model.predict_proba(stage1_scaled)[0]
                    
                    prediction_result["stage1_prediction"] = int(stage1_pred)
                    prediction_result["stage1_confidence"] = float(max(stage1_proba))
                except Exception as e:
                    logger.warning(f"Stage 1 prediction failed: {e}")
                    
            # Stage 2 prediction (CICDDOS with real benign)
            if stage2_model and stage2_scaler and len(feature_vector) >= 82:
                try:
                    stage2_features = feature_vector[:82].reshape(1, -1)
                    stage2_scaled = stage2_scaler.transform(stage2_features)
                    stage2_pred = stage2_model.predict(stage2_scaled)[0]
                    stage2_proba = stage2_model.predict_proba(stage2_scaled)[0]
                    
                    prediction_result["stage2_prediction"] = int(stage2_pred)
                    prediction_result["stage2_confidence"] = float(max(stage2_proba))
                except Exception as e:
                    logger.warning(f"Stage 2 prediction failed: {e}")
            
            # Ensemble decision
            stage1_pred = prediction_result.get("stage1_prediction")
            stage2_pred = prediction_result.get("stage2_prediction")
            
            if stage1_pred is not None and stage2_pred is not None:
                # Both models available - ensemble voting
                if stage1_pred == 1 or stage2_pred == 1:
                    prediction_result["final_prediction"] = "attack"
                    prediction_result["confidence"] = 0.75
                else:
                    prediction_result["final_prediction"] = "benign"
                    prediction_result["confidence"] = 0.70
            elif stage1_pred is not None:
                # Only Stage 1 available
                prediction_result["final_prediction"] = "attack" if stage1_pred == 1 else "benign"
                prediction_result["confidence"] = prediction_result.get("stage1_confidence", 0.6)
            elif stage2_pred is not None:
                # Only Stage 2 available
                prediction_result["final_prediction"] = "attack" if stage2_pred == 1 else "benign"
                prediction_result["confidence"] = prediction_result.get("stage2_confidence", 0.6)
            
            predictions.append(prediction_result)
        
        processing_time = time.time() - start_time
        
        return PredictionResponse(
            predictions=predictions,
            processing_time=processing_time,
            model_info={
                "stage1_status": "loaded" if stage1_model else "not_loaded",
                "stage2_status": "loaded" if stage2_model else "not_loaded",
                "ensemble_mode": "hybrid"
            }
        )
        
    except Exception as e:
        logger.error(f"Prediction error: {e}")
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

# Set permissions
chown -R ddos-user:ddos-user /opt/ddos-detection
chmod +x app.py

# Configure Nginx
cat > /etc/nginx/sites-available/ddos-detection << 'EOF'
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_timeout 60s;
        proxy_connect_timeout 10s;
        proxy_read_timeout 60s;
    }
}
EOF

# Enable Nginx site
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/ddos-detection /etc/nginx/sites-enabled/

# Configure Supervisor for the application
cat > /etc/supervisor/conf.d/ddos-detection.conf << 'EOF'
[program:ddos-detection]
command=/opt/ddos-detection/venv/bin/python app.py
directory=/opt/ddos-detection
user=ddos-user
autostart=true
autorestart=true
stdout_logfile=/var/log/ddos-detection.log
stderr_logfile=/var/log/ddos-detection-error.log
environment=PYTHONPATH="/opt/ddos-detection"
EOF

# Start services
systemctl enable nginx
systemctl start nginx
systemctl enable supervisor
systemctl start supervisor

# Reload supervisor configuration
supervisorctl reread
supervisorctl update
supervisorctl start ddos-detection

# Wait for application to start
sleep 30

# Test the application
curl -f http://localhost:8000/health || echo "Warning: Health check failed"

echo "EC2 instance initialization completed successfully!"
echo "Application should be running on port 8000"
echo "Nginx proxy running on port 80"