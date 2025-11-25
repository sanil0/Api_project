"""
Dashboard Backend - Request Monitoring and Analytics
FastAPI backend for DDoS detection dashboard with SQLite database
"""

import logging
import asyncio
import os
import json
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
import sqlite3
from contextlib import contextmanager
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Database configuration
DATABASE_PATH = os.getenv('DATABASE_PATH', 'dashboard.db')

# Create FastAPI app
app = FastAPI(
    title="DDoS Dashboard API",
    description="Real-time monitoring dashboard for DDoS detection gateways",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to your dashboard domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database connection manager
@contextmanager
def get_db():
    """Database connection context manager"""
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()

def init_database():
    """Initialize database tables"""
    with get_db() as conn:
        cursor = conn.cursor()

        # Create request_logs table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS request_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                source_ip TEXT NOT NULL,
                request_path TEXT NOT NULL,
                request_method TEXT NOT NULL,
                user_agent TEXT,
                prediction TEXT NOT NULL,
                confidence_score REAL NOT NULL,
                is_blocked INTEGER NOT NULL,
                response_status_code INTEGER NOT NULL,
                response_time_ms REAL NOT NULL,
                gateway_id TEXT NOT NULL
            )
        ''')

        # Create indexes for performance
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_timestamp ON request_logs(timestamp)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_source_ip ON request_logs(source_ip)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_is_blocked ON request_logs(is_blocked)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_gateway_id ON request_logs(gateway_id)')

        conn.commit()
        logger.info("Database initialized successfully")

# Initialize database on startup
init_database()
logger.info("Dashboard backend started")

# API Routes
@app.post("/api/logs")
async def receive_log(log_data: Dict):
    """
    Receive request log from gateway
    """
    try:
        required_fields = [
            'timestamp', 'source_ip', 'request_path', 'request_method',
            'prediction', 'confidence_score', 'is_blocked', 'response_status_code',
            'response_time_ms', 'gateway_id'
        ]

        # Validate required fields
        for field in required_fields:
            if field not in log_data:
                raise HTTPException(status_code=400, detail=f"Missing required field: {field}")

        with get_db() as conn:
            cursor = conn.cursor()
            cursor.execute('''
                INSERT INTO request_logs (
                    timestamp, source_ip, request_path, request_method, user_agent,
                    prediction, confidence_score, is_blocked, response_status_code,
                    response_time_ms, gateway_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                log_data['timestamp'],
                log_data['source_ip'],
                log_data['request_path'],
                log_data['request_method'],
                log_data.get('user_agent', ''),
                log_data['prediction'],
                log_data['confidence_score'],
                log_data['is_blocked'],
                log_data['response_status_code'],
                log_data['response_time_ms'],
                log_data['gateway_id']
            ))
            conn.commit()

        return {"status": "success"}

    except Exception as e:
        logger.error(f"Error saving log: {e}")
        raise HTTPException(status_code=500, detail="Failed to save log")

@app.get("/api/logs")
async def get_logs(
    limit: int = Query(100, description="Number of logs to return"),
    offset: int = Query(0, description="Offset for pagination"),
    start_time: Optional[str] = Query(None, description="Start time filter (ISO format)"),
    end_time: Optional[str] = Query(None, description="End time filter (ISO format)"),
    source_ip: Optional[str] = Query(None, description="Filter by source IP"),
    is_blocked: Optional[int] = Query(None, description="Filter by blocked status (0/1)"),
    gateway_id: Optional[str] = Query(None, description="Filter by gateway ID")
):
    """
    Get request logs with optional filtering
    """
    try:
        query = "SELECT * FROM request_logs WHERE 1=1"
        params = []

        if start_time:
            query += " AND timestamp >= ?"
            params.append(start_time)

        if end_time:
            query += " AND timestamp <= ?"
            params.append(end_time)

        if source_ip:
            query += " AND source_ip = ?"
            params.append(source_ip)

        if is_blocked is not None:
            query += " AND is_blocked = ?"
            params.append(is_blocked)

        if gateway_id:
            query += " AND gateway_id = ?"
            params.append(gateway_id)

        query += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])

        with get_db() as conn:
            cursor = conn.cursor()
            cursor.execute(query, params)
            rows = cursor.fetchall()

            logs = []
            for row in rows:
                logs.append(dict(row))

        return {"logs": logs, "count": len(logs)}

    except Exception as e:
        logger.error(f"Error retrieving logs: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve logs")

@app.get("/api/stats")
async def get_stats(hours: int = Query(24, description="Hours of data to analyze")):
    """
    Get dashboard statistics
    """
    try:
        # Calculate time range
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=hours)

        with get_db() as conn:
            cursor = conn.cursor()

            # Total requests
            cursor.execute('''
                SELECT COUNT(*) as total_requests
                FROM request_logs
                WHERE timestamp >= ?
            ''', (start_time.isoformat(),))
            total_requests = cursor.fetchone()['total_requests']

            # Blocked requests
            cursor.execute('''
                SELECT COUNT(*) as blocked_requests
                FROM request_logs
                WHERE timestamp >= ? AND is_blocked = 1
            ''', (start_time.isoformat(),))
            blocked_requests = cursor.fetchone()['blocked_requests']

            # Unique IPs
            cursor.execute('''
                SELECT COUNT(DISTINCT source_ip) as unique_ips
                FROM request_logs
                WHERE timestamp >= ?
            ''', (start_time.isoformat(),))
            unique_ips = cursor.fetchone()['unique_ips']

            # Average response time
            cursor.execute('''
                SELECT AVG(response_time_ms) as avg_response_time
                FROM request_logs
                WHERE timestamp >= ?
            ''', (start_time.isoformat(),))
            avg_response_time = cursor.fetchone()['avg_response_time'] or 0

            # Top blocked IPs
            cursor.execute('''
                SELECT source_ip, COUNT(*) as block_count
                FROM request_logs
                WHERE timestamp >= ? AND is_blocked = 1
                GROUP BY source_ip
                ORDER BY block_count DESC
                LIMIT 10
            ''', (start_time.isoformat(),))
            top_blocked_ips = [dict(row) for row in cursor.fetchall()]

            # Requests per gateway
            cursor.execute('''
                SELECT gateway_id, COUNT(*) as request_count
                FROM request_logs
                WHERE timestamp >= ?
                GROUP BY gateway_id
            ''', (start_time.isoformat(),))
            gateway_stats = [dict(row) for row in cursor.fetchall()]

            # Hourly breakdown (last 24 hours)
            hourly_stats = []
            for i in range(24):
                hour_start = end_time - timedelta(hours=i+1)
                hour_end = end_time - timedelta(hours=i)

                cursor.execute('''
                    SELECT
                        COUNT(*) as total,
                        SUM(is_blocked) as blocked
                    FROM request_logs
                    WHERE timestamp >= ? AND timestamp <= ?
                ''', (hour_start.isoformat(), hour_end.isoformat()))

                row = cursor.fetchone()
                hourly_stats.append({
                    'hour': hour_start.strftime('%H:00'),
                    'total': row['total'],
                    'blocked': row['blocked'] or 0
                })

            hourly_stats.reverse()  # Oldest first

        return {
            "summary": {
                "total_requests": total_requests,
                "blocked_requests": blocked_requests,
                "allowed_requests": total_requests - blocked_requests,
                "block_rate": (blocked_requests / total_requests * 100) if total_requests > 0 else 0,
                "unique_ips": unique_ips,
                "avg_response_time_ms": round(avg_response_time, 2),
                "time_range_hours": hours
            },
            "top_blocked_ips": top_blocked_ips,
            "gateway_stats": gateway_stats,
            "hourly_breakdown": hourly_stats
        }

    except Exception as e:
        logger.error(f"Error retrieving stats: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve statistics")

@app.delete("/api/logs/cleanup")
async def cleanup_old_logs(days: int = Query(7, description="Delete logs older than this many days")):
    """
    Clean up old logs to manage database size
    """
    try:
        cutoff_date = datetime.now() - timedelta(days=days)

        with get_db() as conn:
            cursor = conn.cursor()
            cursor.execute('DELETE FROM request_logs WHERE timestamp < ?', (cutoff_date.isoformat(),))
            deleted_count = cursor.rowcount
            conn.commit()

        logger.info(f"Cleaned up {deleted_count} old log entries")
        return {"status": "success", "deleted_count": deleted_count}

    except Exception as e:
        logger.error(f"Error cleaning up logs: {e}")
        raise HTTPException(status_code=500, detail="Failed to cleanup logs")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "DDoS Dashboard Backend",
        "version": "1.0.0",
        "timestamp": datetime.now().isoformat()
    }

if __name__ == "__main__":
    port = int(os.getenv('PORT', 8001))
    host = os.getenv('HOST', '0.0.0.0')

    logger.info(f"Starting dashboard backend on {host}:{port}")
    uvicorn.run(app, host=host, port=port)