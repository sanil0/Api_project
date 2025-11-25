#!/bin/bash
# Start ML Gateway Server

echo "🚀 Starting ML Gateway - DDoS Detection Reverse Proxy..."
echo ""

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Install dependencies
echo "📦 Installing dependencies..."
pip install -r requirements.txt

echo ""
echo "🎯 Starting gateway on port 8000..."
echo "📡 Target webapp: http://localhost:9000"
echo ""

# Run the gateway
cd ml_gateway
python -m uvicorn app:app --host 0.0.0.0 --port 8000 --reload
