import React, { useState, useEffect } from 'react';
import './App.css';

// Function to convert UTC timestamp to Indian Standard Time (IST)
const formatIST = (timestamp) => {
  const date = new Date(timestamp);
  
  // Add 5 hours and 30 minutes to UTC to get IST
  const istDate = new Date(date.getTime() + (5.5 * 60 * 60 * 1000));
  
  const day = String(istDate.getUTCDate()).padStart(2, '0');
  const month = String(istDate.getUTCMonth() + 1).padStart(2, '0');
  const year = istDate.getUTCFullYear();
  let hours = istDate.getUTCHours();
  const minutes = String(istDate.getUTCMinutes()).padStart(2, '0');
  const seconds = String(istDate.getUTCSeconds()).padStart(2, '0');
  
  const ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12 || 12; // Convert to 12-hour format
  hours = String(hours).padStart(2, '0');
  
  return `${day}/${month}/${year}, ${hours}:${minutes}:${seconds} ${ampm}`;
};

function App() {
  const [stats, setStats] = useState(null);
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        console.log('Fetching dashboard data...');
        const statsRes = await fetch('/api/stats?hours=24');
        console.log('Stats response:', statsRes.status);
        
        if (!statsRes.ok) {
          console.error('Stats API error:', statsRes.status);
          setError('Failed to fetch statistics');
          setLoading(false);
          return;
        }
        
        const statsData = await statsRes.json();
        console.log('Stats data received:', statsData);
        setStats(statsData);
        
        const logsRes = await fetch('/api/logs?limit=50&hours=24');
        console.log('Logs response:', logsRes.status);
        
        if (logsRes.ok) {
          const logsData = await logsRes.json();
          console.log('Logs data received:', logsData);
          setLogs(logsData.logs || []);
        }
        
        setLoading(false);
      } catch (err) {
        console.error('Error fetching data:', err);
        setError(err.message);
        setLoading(false);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 30000);
    return () => clearInterval(interval);
  }, []);

  if (loading) {
    return (
      <div className="dashboard">
        <div className="container">
          <div className="spinner"></div>
          <p>Loading dashboard...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="dashboard">
        <div className="container error">
          <p>Error: {error}</p>
        </div>
      </div>
    );
  }

  if (!stats) {
    return (
      <div className="dashboard">
        <div className="container">
          <p>No data available</p>
        </div>
      </div>
    );
  }

  return (
    <div className="dashboard">
      <header className="dashboard-header">
        <div className="header-content">
          <h1>DDoS Detection Dashboard</h1>
          <p style={{color: 'var(--text-secondary)', margin: 0}}>Real-time monitoring and threat analysis</p>
        </div>
      </header>

      <div className="dashboard-content">
        <div className="stats-grid">
          <div className="stat-card">
            <div className="stat-value">{stats.summary.total_requests}</div>
            <div className="stat-label">Total Requests</div>
            <div className="stat-subtext">Last 24 hours</div>
          </div>

          <div className="stat-card alert">
            <div className="stat-value">{stats.summary.blocked_requests}</div>
            <div className="stat-label">Blocked Requests</div>
            <div className="stat-subtext">{Math.round(stats.summary.block_rate)}% block rate</div>
          </div>

          <div className="stat-card">
            <div className="stat-value">{stats.summary.unique_ips}</div>
            <div className="stat-label">Unique IPs</div>
            <div className="stat-subtext">Source addresses</div>
          </div>

          <div className="stat-card">
            <div className="stat-value">{Math.round(stats.summary.avg_response_time_ms)}ms</div>
            <div className="stat-label">Avg Response</div>
            <div className="stat-subtext">Latency</div>
          </div>
        </div>

        {stats.gateway_stats && stats.gateway_stats.length > 0 && (
          <div className="section">
            <h2>Gateway Statistics</h2>
            <table className="table">
              <thead>
                <tr>
                  <th>Gateway ID</th>
                  <th>Request Count</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {stats.gateway_stats.map((gw, idx) => (
                  <tr key={idx}>
                    <td><code>{gw.gateway_id}</code></td>
                    <td>{gw.request_count}</td>
                    <td><span className="badge badge-success">Active</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {stats.top_blocked_ips && stats.top_blocked_ips.length > 0 && (
          <div className="section">
            <h2>Top Blocked IPs</h2>
            <table className="table">
              <thead>
                <tr>
                  <th>IP Address</th>
                  <th>Block Count</th>
                  <th>Threat Level</th>
                </tr>
              </thead>
              <tbody>
                {stats.top_blocked_ips.map((ip, idx) => (
                  <tr key={idx} className="blocked">
                    <td><code>{ip.source_ip}</code></td>
                    <td><strong>{ip.count}</strong></td>
                    <td>
                      <span className={`badge ${ip.count > 100 ? 'badge-danger' : 'badge-warning'}`}>
                        {ip.count > 100 ? 'High' : 'Medium'}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <div className="section">
          <h2>Recent Requests</h2>
          {logs.length === 0 ? (
            <p className="no-data">No requests logged yet</p>
          ) : (
            <table className="table">
              <thead>
                <tr>
                  <th>Timestamp</th>
                  <th>Source IP</th>
                  <th>Path</th>
                  <th>Status</th>
                  <th>Response Time</th>
                </tr>
              </thead>
              <tbody>
                {logs.map((log, idx) => (
                  <tr key={idx} className={log.is_blocked ? 'blocked' : ''}>
                    <td>{formatIST(log.timestamp)}</td>
                    <td><code>{log.source_ip}</code></td>
                    <td>{log.request_path}</td>
                    <td>
                      <span className={log.is_blocked ? 'badge badge-danger' : 'badge badge-success'}>
                        {log.response_status_code}
                      </span>
                    </td>
                    <td>{Math.round(log.response_time_ms)}ms</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </div>
  );
}

export default App;
