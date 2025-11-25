# DDoS Detection Dashboard

Real-time monitoring dashboard for the ML-based DDoS detection system.

## Architecture

The dashboard consists of three components:

1. **Gateway Logging** - Modified `ml_gateway/app.py` to send request logs asynchronously
2. **FastAPI Backend** - REST API with SQLite database for storing and retrieving logs
3. **React Frontend** - Web dashboard for visualization and monitoring

## Setup Instructions

### 1. Backend Setup

```bash
cd dashboard
pip install -r requirements.txt
python app.py
```

The backend will start on `http://localhost:8001`

### 2. Frontend Setup

```bash
cd dashboard/frontend
npm install
npm start
```

The frontend will start on `http://localhost:3000`

### 3. Gateway Configuration

The gateway automatically sends logs to the dashboard if `ENABLE_DASHBOARD_LOGGING=true` is set.

Environment variables:
- `DASHBOARD_URL`: Dashboard API URL (default: `http://10.0.3.50:8001`)
- `ENABLE_DASHBOARD_LOGGING`: Enable/disable logging (default: `false`)

## API Endpoints

### POST /api/logs
Receive request logs from gateways.

### GET /api/logs
Retrieve logs with filtering options:
- `limit`: Number of logs to return (default: 100)
- `offset`: Pagination offset (default: 0)
- `start_time`: Filter by start time (ISO format)
- `end_time`: Filter by end time (ISO format)
- `source_ip`: Filter by IP address
- `is_blocked`: Filter by blocked status (0/1)
- `gateway_id`: Filter by gateway ID

### GET /api/stats
Get dashboard statistics for the specified time range:
- `hours`: Hours of data to analyze (default: 24)

### DELETE /api/logs/cleanup
Clean up old logs:
- `days`: Delete logs older than this many days (default: 7)

## Database Schema

```sql
CREATE TABLE request_logs (
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
);
```

## Features

- **Real-time Monitoring**: Auto-refresh every 30 seconds
- **Traffic Overview**: Hourly breakdown of requests and blocks
- **Top Blocked IPs**: Most active malicious IPs
- **Gateway Distribution**: Request distribution across gateways
- **Detailed Logs**: Recent request logs with filtering
- **Response Time Tracking**: Monitor gateway performance
- **Time Range Selection**: View data for different time periods

## Security Considerations

- The dashboard should be deployed in a separate EC2 instance
- Use security groups to restrict access to dashboard ports
- Consider implementing authentication for production use
- Database cleanup prevents unlimited growth

## Deployment

### EC2 Instance Setup

1. Launch new EC2 instance in same VPC as gateways
2. Install Python and Node.js
3. Clone repository and setup dashboard
4. Configure security groups:
   - Allow inbound traffic from gateway instances only
   - Open ports 8001 (API) and 3000 (frontend)
5. Start services with systemd or process manager

### Environment Configuration

```bash
# Backend
export DATABASE_PATH=/var/lib/ddos-dashboard/dashboard.db
export HOST=0.0.0.0
export PORT=8001

# Frontend
export REACT_APP_API_URL=http://your-dashboard-instance:8001
```

## Monitoring

The dashboard provides:
- Request volume trends
- Block rate analysis
- Gateway health monitoring
- IP-based threat intelligence
- Performance metrics

Use this data to:
- Identify attack patterns
- Monitor gateway performance
- Track mitigation effectiveness
- Plan capacity scaling