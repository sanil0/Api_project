"""
ML Gateway - Reverse Proxy with Real-time DDoS Detection
Pre-LB Architecture: Sits before ALB/load balancer, performs ML-based threat analysis
Supports multiple backend targets with load balancing and health checks
"""

import logging
import asyncio
import sys
import os
import json
from pathlib import Path
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
import httpx
from typing import Optional, List, Dict
import time
from datetime import datetime
from collections import defaultdict

# Add current directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from detectors.http_detector import HTTPDDoSDetector

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="ML Gateway - DDoS Detection Reverse Proxy (Pre-LB)",
    version="2.0.0",
    description="Real-time ML-based DDoS detection with multi-target load balancing"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize ML Detector
# ==================== DASHBOARD LOGGING CONFIGURATION ====================

# Dashboard configuration (optional - if not set, logging is disabled)
DASHBOARD_URL = os.getenv('DASHBOARD_URL', 'http://10.0.1.230:8001')  # Default dashboard URL
ENABLE_DASHBOARD_LOGGING = os.getenv('ENABLE_DASHBOARD_LOGGING', 'true').lower() == 'true'

# Async function to send request logs to dashboard (non-blocking)
async def send_log_to_dashboard(request_data: Dict, prediction: str, confidence: float, is_blocked: bool, response_status: int, response_time_ms: float):
    """
    Send request log to dashboard asynchronously.
    Non-blocking - if dashboard is down, we don't wait or fail.
    """
    if not ENABLE_DASHBOARD_LOGGING:
        return  # Dashboard logging disabled

    try:
        log_data = {
            "timestamp": datetime.now().isoformat(),
            "source_ip": request_data.get('client_ip', ''),
            "request_path": request_data.get('path', ''),
            "request_method": request_data.get('method', 'GET'),
            "user_agent": request_data.get('user_agent', ''),
            "prediction": prediction,
            "confidence_score": confidence,
            "is_blocked": 1 if is_blocked else 0,
            "response_status_code": response_status,
            "response_time_ms": response_time_ms,
            "gateway_id": f"gateway-{GATEWAY_HOST}:{GATEWAY_PORT}"
        }

        # Fire-and-forget async call with timeout
        async with httpx.AsyncClient(timeout=1.0) as client:
            await client.post(
                f"{DASHBOARD_URL}/api/logs",
                json=log_data,
                timeout=1.0  # Don't wait more than 1 second
            )

    except Exception as e:
        # Log locally but don't fail the request
        logger.debug(f"Failed to send log to dashboard: {e}")
        pass  # Continue normally if dashboard is unreachable


detector = HTTPDDoSDetector(window_size=300, threshold=0.35)

# ==================== MULTI-TARGET CONFIGURATION ====================

# Configuration - can be overridden via environment variables or config file
def load_backend_config():
    """Load backend target configuration from environment or file"""
    
    # Check for config file
    config_file = os.getenv('GATEWAY_CONFIG', '/etc/ml-gateway/config.json')
    if os.path.exists(config_file):
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
                return config.get('backend_targets', [])
        except Exception as e:
            logger.error(f"Failed to load config file {config_file}: {e}")
    
    # Check environment variable
    env_targets = os.getenv('BACKEND_TARGETS')
    if env_targets:
        try:
            return json.loads(env_targets)
        except Exception as e:
            logger.error(f"Failed to parse BACKEND_TARGETS env var: {e}")
    
    # Fallback: single localhost target (backward compatibility)
    return [
        {"host": "httpbin.org", "port": 80, "priority": 1}
    ]


class BackendManager:
    """Manages multiple backend targets with load balancing and health checks"""
    
    def __init__(self, targets: List[dict]):
        """
        Initialize backend manager
        
        Args:
            targets: List of dicts with 'host', 'port', 'priority' keys
        """
        self.targets = targets
        self.target_index = 0
        self.target_health = {self._make_url(t): True for t in targets}
        self.target_failures = defaultdict(int)
        self.last_health_check = {}
        logger.info(f"🔗 Initialized with {len(targets)} backend target(s): {[self._make_url(t) for t in targets]}")
    
    def _make_url(self, target: dict) -> str:
        """Create URL from target dict"""
        protocol = "https" if target.get('port') == 443 else "http"
        return f"{protocol}://{target['host']}:{target['port']}"
    
    def get_next_target(self) -> Optional[str]:
        """Get next healthy backend target (round-robin)"""
        if not self.targets:
            return None
        
        # Find next healthy target
        attempts = 0
        while attempts < len(self.targets):
            target_url = self._make_url(self.targets[self.target_index])
            self.target_index = (self.target_index + 1) % len(self.targets)
            
            if self.target_health.get(target_url, True):  # Default to True if unknown
                return target_url
            
            attempts += 1
        
        # All unhealthy, return first anyway (failure recovery)
        return self._make_url(self.targets[0])
    
    async def health_check(self, target_url: str):
        """Check if backend target is healthy"""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"{target_url}/health", follow_redirects=True)
                is_healthy = response.status_code == 200
                
                old_status = self.target_health.get(target_url, None)
                self.target_health[target_url] = is_healthy
                
                if old_status != is_healthy:
                    status_str = "✅ UP" if is_healthy else "❌ DOWN"
                    logger.warning(f"Health check: {target_url} → {status_str}")
                
                if is_healthy:
                    self.target_failures[target_url] = 0
                else:
                    self.target_failures[target_url] += 1
                    
        except Exception as e:
            self.target_health[target_url] = False
            self.target_failures[target_url] += 1
            logger.error(f"Health check failed for {target_url}: {e}")
    
    async def start_health_checks(self, interval: int = 30):
        """Periodically check backend health"""
        while True:
            try:
                tasks = [self.health_check(self._make_url(t)) for t in self.targets]
                await asyncio.gather(*tasks)
                await asyncio.sleep(interval)
            except Exception as e:
                logger.error(f"Error in health check loop: {e}")
                await asyncio.sleep(interval)


# Load configuration and initialize backend manager
BACKEND_TARGETS = load_backend_config()
# For local testing, use a dummy backend if the real one is not available
if not BACKEND_TARGETS:
    BACKEND_TARGETS = [{"host": "httpbin.org", "port": 443, "priority": 1}]
backend_manager = BackendManager(BACKEND_TARGETS)

# Configuration
GATEWAY_PORT = int(os.getenv('GATEWAY_PORT', 8000))
GATEWAY_HOST = os.getenv('GATEWAY_HOST', '0.0.0.0')

# Statistics tracking
gateway_stats = {
    'total_requests': 0,
    'blocked_requests': 0,
    'allowed_requests': 0,
    'total_ddos_detected': 0,
    'start_time': datetime.now(),
    'backend_requests': defaultdict(int),  # Track requests per backend
}


def get_client_ip(request: Request) -> str:
    """Extract real client IP from request headers (ALB-aware)"""
    # Check X-Forwarded-For first (set by ALB)
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        # X-Forwarded-For can have multiple IPs, get the first (original client)
        return forwarded.split(",")[0].strip()
    
    # Check X-Real-IP (alternative proxy header)
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip
    
    # Fallback to client address
    return request.client.host if request.client else "unknown"


def extract_request_data(request: Request) -> dict:
    """Extract request data for feature analysis"""
    return {
        'client_ip': get_client_ip(request),
        'method': request.method,
        'path': request.url.path,
        'protocol': request.headers.get('http-version', 'HTTP/1.1'),
        'user_agent': request.headers.get('User-Agent', ''),
        'referer': request.headers.get('Referer', ''),
        'connection': request.headers.get('Connection', ''),
        'headers': dict(request.headers),
        'content_length': int(request.headers.get('Content-Length', 0)),
        'accept_encoding': request.headers.get('Accept-Encoding', ''),
        'query_params': len(request.query_params),
        'cookies': bool(request.headers.get('Cookie')),
    }


@app.middleware("http")
async def ddos_detection_middleware(request: Request, call_next):
    """
    Middleware for real-time DDoS detection and request forwarding
    Analyzes every request before forwarding to backend
    """
    # Skip detection and proxying for health check endpoint
    if request.url.path == "/health":
        return await call_next(request)
    
    start_time = time.time()  # Record start time for response time calculation
    
    try:
        # Extract request information
        request_data = extract_request_data(request)
        client_ip = request_data['client_ip']
        
        gateway_stats['total_requests'] += 1
        
        # Run ML analysis
        prediction, confidence = detector.analyze_request(client_ip, request_data)
        
        # Log analysis
        logger.info(f"📊 [{gateway_stats['total_requests']}] {client_ip} → {request.url.path} | Prediction: {prediction} ({confidence:.2f})")
        
        # Block if DDoS detected with high confidence
        if prediction == 'DDoS' and confidence > detector.threshold:
            gateway_stats['blocked_requests'] += 1
            gateway_stats['total_ddos_detected'] += 1
            
            logger.warning(f"🚫 BLOCKED DDoS from {client_ip} (confidence: {confidence:.2f})")
            
            response_time_ms = (time.time() - start_time) * 1000
            
            # Log to dashboard (async, non-blocking)
            asyncio.create_task(send_log_to_dashboard(
                request_data, prediction, confidence, True, 429, response_time_ms
            ))
            
            return Response(
                content=f"Access Denied - DDoS Detected (Score: {confidence:.2f})",
                status_code=429,
                media_type="text/plain"
            )
        
        # Block if already in blocklist
        if prediction == 'BLOCKED':
            gateway_stats['blocked_requests'] += 1
            logger.warning(f"🚫 BLOCKED (Blacklist) from {client_ip}")
            
            response_time_ms = (time.time() - start_time) * 1000
            
            # Log to dashboard (async, non-blocking)
            asyncio.create_task(send_log_to_dashboard(
                request_data, prediction, confidence, True, 403, response_time_ms
            ))
            
            return Response(
                content="Access Denied - IP Blacklisted",
                status_code=403,
                media_type="text/plain"
            )
        
        gateway_stats['allowed_requests'] += 1
        
    except Exception as e:
        logger.error(f"Error in DDoS detection middleware: {e}")
        # On error, allow request to proceed
        pass
    
    # Forward to backend with load balancing
    try:
        target_backend = backend_manager.get_next_target()
        
        if not target_backend:
            response_time_ms = (time.time() - start_time) * 1000
            
            # Log to dashboard (async, non-blocking)
            asyncio.create_task(send_log_to_dashboard(
                request_data, prediction, confidence, False, 503, response_time_ms
            ))
            
            return Response(
                content="Gateway Error - No backend targets available",
                status_code=503,
                media_type="text/plain"
            )
        
        # Track backend usage
        gateway_stats['backend_requests'][target_backend] += 1
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Prepare URL for forwarding
            url = f"{target_backend}{request.url.path}"
            if request.url.query:
                url = f"{url}?{request.url.query}"
            
            logger.debug(f"Forwarding to backend: {target_backend}")
            
            # Forward request with headers
            response = await client.request(
                method=request.method,
                url=url,
                headers={k: v for k, v in request.headers.items() 
                        if k.lower() not in ['host', 'connection']},
                content=await request.body(),
                follow_redirects=True,
            )
            
            response_time_ms = (time.time() - start_time) * 1000
            
            # Log to dashboard (async, non-blocking)
            asyncio.create_task(send_log_to_dashboard(
                request_data, prediction, confidence, False, response.status_code, response_time_ms
            ))
            
            # Return response from backend (remove gzip encoding header to prevent client decompression issues)
            response_headers = {k: v for k, v in dict(response.headers).items() 
                               if k.lower() != 'content-encoding'}
            return Response(
                content=response.content,
                status_code=response.status_code,
                headers=response_headers,
                media_type=response.headers.get('content-type'),
            )
            
    except httpx.ConnectError:
        logger.error(f"Failed to connect to backend at {target_backend}")
        
        response_time_ms = (time.time() - start_time) * 1000
        
        # Log to dashboard (async, non-blocking)
        asyncio.create_task(send_log_to_dashboard(
            request_data, prediction, confidence, False, 502, response_time_ms
        ))
        
        return Response(
            content="Gateway Error - Cannot reach target server",
            status_code=502,
            media_type="text/plain"
        )
    except Exception as e:
        logger.error(f"Error forwarding request: {e}")
        
        response_time_ms = (time.time() - start_time) * 1000
        
        # Log to dashboard (async, non-blocking)
        asyncio.create_task(send_log_to_dashboard(
            request_data, prediction, confidence, False, 500, response_time_ms
        ))
        
        return Response(
            content=f"Gateway Error - {str(e)}",
            status_code=500,
            media_type="text/plain"
        )


@app.get("/health")
async def health_check():
    """Health check endpoint for load balancer"""
    backend_health = {
        backend: status 
        for backend, status in backend_manager.target_health.items()
    }
    
    return {
        "status": "healthy",
        "gateway": "ML-based DDoS Detection (Pre-LB)",
        "version": "2.0.0",
        "backend_targets": backend_health,
        "uptime_seconds": (datetime.now() - gateway_stats['start_time']).total_seconds(),
    }


@app.get("/stats")
async def get_stats():
    """Get gateway statistics and backend distribution"""
    return {
        "statistics": {
            "total_requests": gateway_stats['total_requests'],
            "blocked_requests": gateway_stats['blocked_requests'],
            "allowed_requests": gateway_stats['allowed_requests'],
            "total_ddos_detected": gateway_stats['total_ddos_detected'],
            "start_time": gateway_stats['start_time'].isoformat(),
        },
        "backend_distribution": dict(gateway_stats['backend_requests']),
        "backend_health": dict(backend_manager.target_health),
        "backend_failures": dict(backend_manager.target_failures),
        "detection": detector.get_stats(),
        "blocked_ips": list(detector.blocked_ips.keys()),
    }


@app.get("/metrics")
async def get_metrics():
    """Get metrics for monitoring"""
    uptime = (datetime.now() - gateway_stats['start_time']).total_seconds()
    total_requests = max(gateway_stats['total_requests'], 1)
    
    return {
        "total_requests": gateway_stats['total_requests'],
        "allowed_requests": gateway_stats['allowed_requests'],
        "blocked_requests": gateway_stats['blocked_requests'],
        "ddos_detected": gateway_stats['total_ddos_detected'],
        "block_rate": f"{(gateway_stats['blocked_requests'] / total_requests * 100):.2f}%",
        "uptime_seconds": uptime,
        "requests_per_minute": (gateway_stats['total_requests'] / max(uptime / 60, 1)),
        "blocked_ips_count": len(detector.blocked_ips),
        "backend_targets_healthy": sum(1 for v in backend_manager.target_health.values() if v),
        "backend_targets_total": len(backend_manager.targets),
    }


@app.post("/block/{client_ip}")
async def block_ip(client_ip: str, duration: int = 600):
    """Manually block an IP address"""
    detector.block_ip(client_ip, duration)
    return {"status": "blocked", "ip": client_ip, "duration": duration}


@app.post("/unblock/{client_ip}")
async def unblock_ip(client_ip: str):
    """Manually unblock an IP address"""
    detector.unblock_ip(client_ip)
    return {"status": "unblocked", "ip": client_ip}


@app.get("/")
async def root():
    """Root endpoint with gateway information"""
    return {
        "gateway": "ML-based DDoS Detection Reverse Proxy (Pre-LB Architecture)",
        "version": "2.0.0",
        "backend_targets": [backend_manager._make_url(t) for t in backend_manager.targets],
        "status": "running",
        "endpoints": {
            "health": "/health",
            "stats": "/stats",
            "metrics": "/metrics",
            "block": "/block/{client_ip}",
            "unblock": "/unblock/{client_ip}",
            "backends": "/backends",
        },
    }


@app.get("/backends")
async def get_backends():
    """Get backend target information and health status"""
    return {
        "total_targets": len(backend_manager.targets),
        "targets": [
            {
                "url": backend_manager._make_url(t),
                "health": backend_manager.target_health.get(backend_manager._make_url(t), None),
                "failures": backend_manager.target_failures.get(backend_manager._make_url(t), 0),
                "requests_handled": gateway_stats['backend_requests'].get(backend_manager._make_url(t), 0),
            }
            for t in backend_manager.targets
        ],
    }


if __name__ == "__main__":
    import uvicorn
    
    logger.info("=" * 80)
    logger.info("🚀 ML GATEWAY - DDoS DETECTION REVERSE PROXY (PRE-LB ARCHITECTURE)")
    logger.info("=" * 80)
    logger.info(f"📡 Gateway listening on: http://{GATEWAY_HOST}:{GATEWAY_PORT}")
    logger.info(f"🔗 Backend targets:")
    for target in backend_manager.targets:
        url = backend_manager._make_url(target)
        logger.info(f"   • {url}")
    logger.info(f"🧠 ML Detection: Enabled (threshold: {detector.threshold})")
    logger.info("=" * 80)
    
    uvicorn.run(
        app,
        host=GATEWAY_HOST,
        port=GATEWAY_PORT,
        log_level="info"
    )
