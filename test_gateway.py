"""
Comprehensive testing suite for ML Gateway
Tests detection accuracy, performance, and resilience
"""

import asyncio
import time
import json
import subprocess
import sys
import httpx
from typing import Dict, List
import random
import string

BASE_URL = "http://localhost:8000"
TARGET_URL = "http://localhost:9000"


class GatewayTester:
    """Test ML Gateway detection and performance"""
    
    def __init__(self, base_url: str = BASE_URL):
        self.base_url = base_url
        self.results = {
            'normal_requests': 0,
            'ddos_requests': 0,
            'blocked_requests': 0,
            'allowed_requests': 0,
            'detection_times': [],
            'test_results': []
        }
    
    async def check_gateway_health(self) -> bool:
        """Check if gateway is running"""
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                response = await client.get(f"{self.base_url}/health")
                return response.status_code == 200
        except Exception as e:
            print(f"❌ Gateway not running: {e}")
            return False
    
    async def test_normal_traffic(self, num_requests: int = 10) -> Dict:
        """Test normal traffic patterns"""
        print(f"\n🧪 Testing normal traffic ({num_requests} requests)...")
        
        self.results['normal_requests'] = num_requests
        blocked = 0
        
        start_time = time.time()
        
        async with httpx.AsyncClient(timeout=10) as client:
            for i in range(num_requests):
                try:
                    # Normal request pattern
                    response = await client.get(
                        f"{self.base_url}/",
                        headers={
                            "User-Agent": "Mozilla/5.0 (Normal User)",
                            "Referer": "https://example.com",
                        }
                    )
                    
                    if response.status_code == 429 or response.status_code == 403:
                        blocked += 1
                    
                    self.results['allowed_requests'] += 1
                    print(f"  [{i+1}/{num_requests}] Status: {response.status_code}")
                    
                except Exception as e:
                    print(f"  Error: {e}")
        
        elapsed = time.time() - start_time
        
        result = {
            'test': 'normal_traffic',
            'total_requests': num_requests,
            'allowed': num_requests - blocked,
            'blocked': blocked,
            'false_positive_rate': f"{(blocked/num_requests*100):.2f}%",
            'time_elapsed': f"{elapsed:.2f}s",
            'avg_response_time': f"{(elapsed/num_requests*1000):.2f}ms"
        }
        
        self.results['test_results'].append(result)
        print(f"  ✅ Normal traffic test complete")
        print(f"     Blocked: {blocked}/{num_requests}")
        print(f"     Time: {elapsed:.2f}s")
        
        return result
    
    async def test_ddos_simulation(self, num_sources: int = 5, requests_per_source: int = 20) -> Dict:
        """Simulate DDoS attack"""
        print(f"\n🚨 Simulating DDoS attack ({num_sources} sources, {requests_per_source} req/source)...")
        
        total_requests = num_sources * requests_per_source
        self.results['ddos_requests'] = total_requests
        blocked = 0
        
        start_time = time.time()
        
        async with httpx.AsyncClient(timeout=10) as client:
            tasks = []
            for source in range(num_sources):
                # Simulate attack patterns
                spoofed_ip = f"192.168.{random.randint(0,255)}.{random.randint(1,254)}"
                
                for req in range(requests_per_source):
                    task = self._send_attack_request(client, spoofed_ip)
                    tasks.append(task)
            
            responses = await asyncio.gather(*tasks, return_exceptions=True)
            
            for response in responses:
                if isinstance(response, Exception):
                    continue
                elif response.status_code == 429 or response.status_code == 403:
                    blocked += 1
        
        elapsed = time.time() - start_time
        
        result = {
            'test': 'ddos_simulation',
            'total_requests': total_requests,
            'blocked': blocked,
            'allowed': total_requests - blocked,
            'detection_rate': f"{(blocked/total_requests*100):.2f}%",
            'time_elapsed': f"{elapsed:.2f}s",
            'avg_response_time': f"{(elapsed/total_requests*1000):.2f}ms"
        }
        
        self.results['blocked_requests'] += blocked
        self.results['test_results'].append(result)
        
        print(f"  ✅ DDoS simulation test complete")
        print(f"     Blocked: {blocked}/{total_requests}")
        print(f"     Detection Rate: {(blocked/total_requests*100):.2f}%")
        print(f"     Time: {elapsed:.2f}s")
        
        return result
    
    async def _send_attack_request(self, client, spoofed_ip: str) -> httpx.Response:
        """Send individual attack request"""
        try:
            response = await client.get(
                f"{self.base_url}/api/metrics",
                headers={
                    "X-Forwarded-For": spoofed_ip,
                    "User-Agent": "bot-agent",
                },
                timeout=5
            )
            return response
        except Exception as e:
            return e
    
    async def test_burst_attack(self, burst_size: int = 100) -> Dict:
        """Test sudden burst of requests"""
        print(f"\n💥 Testing burst attack ({burst_size} rapid requests)...")
        
        self.results['ddos_requests'] += burst_size
        blocked = 0
        
        start_time = time.time()
        
        async with httpx.AsyncClient(timeout=10) as client:
            tasks = []
            for i in range(burst_size):
                task = client.get(
                    f"{self.base_url}/",
                    headers={"X-Forwarded-For": "10.0.0.1"},
                    timeout=5
                )
                tasks.append(task)
            
            responses = await asyncio.gather(*tasks, return_exceptions=True)
            
            for response in responses:
                if isinstance(response, Exception):
                    continue
                elif response.status_code == 429 or response.status_code == 403:
                    blocked += 1
        
        elapsed = time.time() - start_time
        
        result = {
            'test': 'burst_attack',
            'total_requests': burst_size,
            'blocked': blocked,
            'allowed': burst_size - blocked,
            'detection_rate': f"{(blocked/burst_size*100):.2f}%",
            'time_elapsed': f"{elapsed:.2f}s",
            'rps': f"{(burst_size/elapsed):.0f}"
        }
        
        self.results['blocked_requests'] += blocked
        self.results['test_results'].append(result)
        
        print(f"  ✅ Burst test complete")
        print(f"     Blocked: {blocked}/{burst_size}")
        print(f"     RPS: {(burst_size/elapsed):.0f}")
        
        return result
    
    async def get_gateway_stats(self) -> Dict:
        """Get gateway statistics"""
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                response = await client.get(f"{self.base_url}/stats")
                return response.json()
        except Exception as e:
            print(f"❌ Failed to get stats: {e}")
            return {}
    
    def print_summary(self):
        """Print test summary"""
        print("\n" + "=" * 70)
        print("📊 ML GATEWAY TEST SUMMARY")
        print("=" * 70)
        
        for result in self.results['test_results']:
            print(f"\n🔹 {result['test'].upper()}")
            for key, value in result.items():
                if key != 'test':
                    print(f"   {key}: {value}")
        
        print("\n" + "=" * 70)
        print("✅ TESTING COMPLETE")
        print("=" * 70)


async def main():
    """Run all tests"""
    tester = GatewayTester()
    
    print("\n" + "=" * 70)
    print("🧪 ML GATEWAY COMPREHENSIVE TEST SUITE")
    print("=" * 70)
    
    # Check health
    print("\n🔍 Checking gateway health...")
    if not await tester.check_gateway_health():
        print("❌ Gateway is not running!")
        print("Start it with: python -m uvicorn ml_gateway.app:app --host 0.0.0.0 --port 8000")
        return
    
    print("✅ Gateway is running")
    
    # Run tests
    try:
        await tester.test_normal_traffic(num_requests=15)
        await asyncio.sleep(1)
        
        await tester.test_ddos_simulation(num_sources=5, requests_per_source=15)
        await asyncio.sleep(1)
        
        await tester.test_burst_attack(burst_size=50)
        
    except Exception as e:
        print(f"❌ Test error: {e}")
    
    # Get final stats
    print("\n📈 Fetching gateway statistics...")
    stats = await tester.get_gateway_stats()
    if stats:
        print(json.dumps(stats, indent=2))
    
    # Print summary
    tester.print_summary()


if __name__ == "__main__":
    asyncio.run(main())
