"""
HTTP-based DDoS Detection Module
Analyzes HTTP requests in real-time for DDoS attack patterns
"""

import logging
import time
from collections import defaultdict, deque
from typing import Dict, Tuple
from datetime import datetime, timedelta
import json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class HTTPDDoSDetector:
    """Real-time HTTP DDoS detection using ML-based feature analysis"""
    
    def __init__(self, window_size: int = 300, threshold: float = 0.35):
        """
        Initialize HTTP DDoS Detector
        
        Args:
            window_size: Time window in seconds for analysis (default 5 min)
            threshold: Confidence threshold for blocking (0-1)
        """
        self.window_size = window_size
        self.threshold = threshold
        
        # Track requests per IP in time window
        self.ip_requests = defaultdict(deque)  # IP -> deque of (timestamp, request_data)
        self.ip_stats = defaultdict(dict)      # IP -> statistics
        self.blocked_ips = {}                  # IP -> block_time
        self.alert_buffer = deque(maxlen=1000)
        
        # Attack pattern signatures
        self.attack_signatures = {
            'high_frequency': 50,       # Requests per minute (more sensitive)
            'burst_threshold': 20,       # Requests in 10 seconds (more sensitive)
            'user_agent_diversity': 0.15, # Low UA diversity = bot
            'path_entropy': 0.25,         # Low path entropy = scanning
        }
        
        logger.info(f"✅ HTTPDDoSDetector initialized (window={window_size}s, threshold={threshold})")
    
    def extract_http_features(self, request_data: Dict) -> Dict[str, float]:
        """
        Extract 19 HTTP-based features from request
        
        Returns:
            Dictionary with feature names and values
        """
        features = {}
        
        # 1. Request rate (requests per second)
        features['request_rate'] = self._calculate_request_rate(request_data.get('client_ip', ''))
        
        # 2. Inter-arrival time variance
        features['iat_variance'] = self._calculate_iat_variance(request_data.get('client_ip', ''))
        
        # 3. User-Agent diversity
        features['ua_diversity'] = self._calculate_ua_diversity(request_data.get('client_ip', ''))
        
        # 4. Referer header presence
        features['referer_presence'] = 1.0 if request_data.get('referer') else 0.0
        
        # 5. Connection type (Keep-Alive vs Close)
        features['keep_alive'] = 1.0 if request_data.get('connection', '').lower() == 'keep-alive' else 0.0
        
        # 6. HTTP method distribution
        method = request_data.get('method', 'GET').upper()
        features['method_get'] = 1.0 if method == 'GET' else 0.0
        features['method_post'] = 1.0 if method == 'POST' else 0.0
        features['method_other'] = 1.0 if method not in ['GET', 'POST'] else 0.0
        
        # 7. URL path complexity
        features['path_length'] = min(len(request_data.get('path', '')), 100) / 100.0
        
        # 8. Query parameter count
        query_params = request_data.get('query_params', 0)
        features['query_param_count'] = min(query_params, 10) / 10.0
        
        # 9. Header count
        header_count = len(request_data.get('headers', {}))
        features['header_count'] = min(header_count, 30) / 30.0
        
        # 10. Content-Length presence
        features['content_length'] = 1.0 if request_data.get('content_length') else 0.0
        
        # 11. Accept-Encoding presence
        features['accept_encoding'] = 1.0 if request_data.get('accept_encoding') else 0.0
        
        # 12. Host header mismatch
        features['host_mismatch'] = 1.0 if request_data.get('host_mismatch') else 0.0
        
        # 13. Payload size
        payload_size = request_data.get('content_length', 0)
        features['payload_size'] = min(payload_size, 10000) / 10000.0
        
        # 14. Request burst detection
        features['burst_detected'] = 1.0 if self._detect_burst(request_data.get('client_ip', '')) else 0.0
        
        # 15. Timing variance
        features['timing_variance'] = self._calculate_timing_variance(request_data.get('client_ip', ''))
        
        # 16. Cookie presence
        features['cookie_presence'] = 1.0 if request_data.get('cookies') else 0.0
        
        # 17. Session persistence
        features['session_persistent'] = self._check_session_persistence(request_data.get('client_ip', ''))
        
        # 18. Protocol version
        protocol = request_data.get('protocol', 'HTTP/1.1')
        features['http2_usage'] = 1.0 if '2' in protocol else 0.0
        
        # 19. Geographic anomaly (if available)
        features['geo_anomaly'] = request_data.get('geo_anomaly', 0.0)
        
        return features
    
    def analyze_request(self, client_ip: str, request_data: Dict) -> Tuple[str, float]:
        """
        Analyze incoming request for DDoS patterns
        
        Returns:
            Tuple of (prediction: 'NORMAL' or 'DDoS', confidence: 0-1)
        """
        try:
            # Check if IP is already blocked
            if self._is_blocked(client_ip):
                return 'BLOCKED', 1.0
            
            # Extract features
            features = self.extract_http_features({'client_ip': client_ip, **request_data})
            
            # Calculate anomaly score (0-1, higher = more suspicious)
            anomaly_score = self._calculate_anomaly_score(client_ip, features)
            
            # Simple ML-like prediction based on feature analysis
            prediction = 'DDoS' if anomaly_score > self.threshold else 'NORMAL'
            
            # Store request for statistics
            self._store_request(client_ip, request_data, anomaly_score)
            
            # Log if DDoS detected
            if prediction == 'DDoS':
                logger.warning(f"🚨 DDoS DETECTED from {client_ip} (score: {anomaly_score:.2f})")
                self.alert_buffer.append({
                    'timestamp': datetime.now().isoformat(),
                    'client_ip': client_ip,
                    'score': anomaly_score,
                    'features': features
                })
            
            return prediction, anomaly_score
            
        except Exception as e:
            logger.error(f"Error analyzing request from {client_ip}: {e}")
            return 'NORMAL', 0.0
    
    def _calculate_request_rate(self, client_ip: str) -> float:
        """Calculate request rate (requests per second)"""
        if not client_ip or client_ip not in self.ip_requests:
            return 0.0
        
        now = time.time()
        recent = [t for _, t in self.ip_requests[client_ip] if t > now - 60]
        
        rate = len(recent) / 60.0  # Requests per second
        # Very aggressive: 3 req/s = 1.0 score
        return min(rate / 3.0, 1.0)
    
    def _calculate_iat_variance(self, client_ip: str) -> float:
        """Calculate inter-arrival time variance"""
        if not client_ip or len(self.ip_requests[client_ip]) < 2:
            return 0.0
        
        times = [t for _, t in list(self.ip_requests[client_ip])[-20:]]
        if len(times) < 2:
            return 0.0
        
        deltas = [times[i+1] - times[i] for i in range(len(times)-1)]
        if not deltas:
            return 0.0
        
        avg_delta = sum(deltas) / len(deltas)
        variance = sum((d - avg_delta) ** 2 for d in deltas) / len(deltas)
        
        # High variance = legitimate (human-like), low variance = bot
        return max(0.0, 1.0 - min(variance, 1.0))
    
    def _calculate_ua_diversity(self, client_ip: str) -> float:
        """Calculate User-Agent diversity (0 = all same, 1 = all different)"""
        if client_ip not in self.ip_stats or 'user_agents' not in self.ip_stats[client_ip]:
            return 0.5
        
        user_agents = self.ip_stats[client_ip]['user_agents']
        if not user_agents:
            return 0.5
        
        unique_uas = len(set(user_agents))
        total_requests = len(user_agents)
        
        # Low diversity = suspicious (bots use same UA)
        diversity = unique_uas / max(total_requests, 1)
        return 1.0 - diversity  # Invert: high value = low diversity = suspicious
    
    def _detect_burst(self, client_ip: str) -> bool:
        """Detect if IP is sending burst of requests"""
        if not client_ip or client_ip not in self.ip_requests:
            return False
        
        now = time.time()
        recent = [t for _, t in self.ip_requests[client_ip] if t > now - 10]
        
        return len(recent) > self.attack_signatures['burst_threshold']
    
    def _calculate_timing_variance(self, client_ip: str) -> float:
        """Calculate timing variance across requests"""
        if not client_ip or len(self.ip_requests[client_ip]) < 3:
            return 0.0
        
        times = [t for _, t in list(self.ip_requests[client_ip])[-30:]]
        if len(times) < 3:
            return 0.0
        
        deltas = [times[i+1] - times[i] for i in range(len(times)-1)]
        
        if not deltas or sum(deltas) == 0:
            return 0.0
        
        cv = (sum((d - sum(deltas)/len(deltas))**2 for d in deltas) / len(deltas)) ** 0.5
        return min(cv, 1.0)
    
    def _check_session_persistence(self, client_ip: str) -> float:
        """Check if session shows persistence (legitimate user pattern)"""
        if client_ip not in self.ip_stats:
            return 0.0
        
        first_seen = self.ip_stats[client_ip].get('first_seen', time.time())
        duration = time.time() - first_seen
        
        # Sessions longer than 5 minutes are more legitimate
        if duration > 300:
            return 0.8
        elif duration > 60:
            return 0.5
        else:
            return 0.0
    
    def _calculate_anomaly_score(self, client_ip: str, features: Dict) -> float:
        """Calculate overall anomaly score using simple ML-like approach"""
        score = 0.0
        weights = {
            'request_rate': 0.40,        # Increased from 0.25 - most important signal
            'iat_variance': 0.20,
            'ua_diversity': 0.15,
            'burst_detected': 0.20,
            'timing_variance': 0.03,    # Reduced from 0.10
            'geo_anomaly': 0.02,        # Reduced from 0.10
        }
        
        # Weighted sum of suspicious features
        for feature, weight in weights.items():
            if feature in features:
                score += features[feature] * weight
        
        return min(score, 1.0)
    
    def _store_request(self, client_ip: str, request_data: Dict, score: float):
        """Store request for statistics"""
        now = time.time()
        
        # Clean old requests outside window (defaultdict will auto-create empty deque if needed)
        if client_ip in self.ip_requests:
            self.ip_requests[client_ip] = deque(
                [(r, t) for r, t in self.ip_requests[client_ip] if t > now - self.window_size]
            )
        
        # Store new request
        self.ip_requests[client_ip].append((request_data, now))
        
        # Update statistics
        if client_ip not in self.ip_stats:
            self.ip_stats[client_ip] = {
                'first_seen': now,
                'user_agents': [],
                'paths': [],
                'methods': [],
            }
        
        self.ip_stats[client_ip]['last_seen'] = now
        self.ip_stats[client_ip]['request_count'] = len(self.ip_requests[client_ip])
        
        if 'user_agent' in request_data:
            self.ip_stats[client_ip]['user_agents'].append(request_data['user_agent'])
        
        if 'path' in request_data:
            self.ip_stats[client_ip]['paths'].append(request_data['path'])
    
    def _is_blocked(self, client_ip: str) -> bool:
        """Check if IP is in blocklist"""
        if client_ip not in self.blocked_ips:
            return False
        
        block_time = self.blocked_ips[client_ip]
        if time.time() - block_time > 600:  # Block for 10 minutes
            del self.blocked_ips[client_ip]
            return False
        
        return True
    
    def block_ip(self, client_ip: str, duration: int = 600, ttl: int = None):
        """Block an IP address"""
        block_duration = ttl if ttl is not None else duration
        self.blocked_ips[client_ip] = time.time()
        logger.info(f"🚫 Blocked IP: {client_ip} for {block_duration}s")
    
    def unblock_ip(self, client_ip: str):
        """Unblock an IP address"""
        if client_ip in self.blocked_ips:
            del self.blocked_ips[client_ip]
            logger.info(f"✅ Unblocked IP: {client_ip}")
    
    def get_stats(self) -> Dict:
        """Get current detection statistics"""
        return {
            'total_ips': len(self.ip_stats),
            'blocked_ips': len(self.blocked_ips),
            'recent_alerts': list(self.alert_buffer),
            'window_size': self.window_size,
            'threshold': self.threshold,
        }
