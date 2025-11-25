# Start ML Gateway Server

Write-Host "🚀 Starting ML Gateway - DDoS Detection Reverse Proxy..." -ForegroundColor Cyan
Write-Host ""

# Check if virtual environment exists
if (Test-Path ".\venv\Scripts\Activate.ps1") {
    Write-Host "✅ Activating virtual environment..." -ForegroundColor Green
    & ".\venv\Scripts\Activate.ps1"
} else {
    Write-Host "⚠️ Virtual environment not found. Creating one..." -ForegroundColor Yellow
    python -m venv venv
    & ".\venv\Scripts\Activate.ps1"
}

# Install dependencies
Write-Host "📦 Installing dependencies..." -ForegroundColor Yellow
pip install -r requirements.txt

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "🎯 ML GATEWAY STARTING" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "📡 Gateway listening on: http://0.0.0.0:8000" -ForegroundColor White
Write-Host "🎯 Target webapp: http://localhost:9000" -ForegroundColor White
Write-Host "🧠 ML Detection: ENABLED" -ForegroundColor White
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Run the gateway
Set-Location ml_gateway
python -m uvicorn app:app --host 0.0.0.0 --port 8000 --reload
