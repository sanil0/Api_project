#!/usr/bin/env python3
"""
Test script for Hybrid DDoS Detection System
Phase 3: End-to-end testing of deployed AWS infrastructure
"""

import requests
import time
import json
import random
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
import argparse

class DDoSDetectionTester:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip('/')
        self.session = requests.Session()
        self.session.timeout = 30
        
    def test_health(self) -> dict:
        """Test health endpoint"""
        try:
            response = self.session.get(f"{self.base_url}/health")
            response.raise_for_status()
            return {"success": True, "data": response.json(), "latency_ms": response.elapsed.total_seconds() * 1000}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def test_stats(self) -> dict:
        """Test stats endpoint"""
        try:
            response = self.session.get(f"{self.base_url}/stats")
            response.raise_for_status()
            return {"success": True, "data": response.json(), "latency_ms": response.elapsed.total_seconds() * 1000}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def generate_test_request(self, attack_type: str = "benign") -> dict:
        """Generate test request data"""
        base_request = {
            "source_ip": f"192.168.{random.randint(1, 255)}.{random.randint(1, 255)}",
            "destination_ip": "10.0.1.100",
            "source_port": random.randint(1024, 65535),
            "destination_port": random.choice([80, 443, 8080]),
            "protocol": "TCP",
            "method": "GET",
            "uri": "/",
            "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "headers": {"Content-Type": "application/json"}
        }
        
        if attack_type == "ddos_high_rate":
            base_request.update({
                "request_rate": random.uniform(100, 1000),
                "packet_size": random.randint(1000, 10000),
                "uri": f"/attack?param={random.randint(1, 1000)}"
            })
        elif attack_type == "ddos_large_payload":
            base_request.update({
                "request_rate": random.uniform(50, 200),
                "packet_size": random.randint(50000, 100000),
                "uri": "/large_payload"
            })
        elif attack_type == "ddos_syn_flood":
            base_request.update({
                "request_rate": random.uniform(500, 2000),
                "packet_size": random.randint(64, 128),
                "protocol": "TCP"
            })
        else:  # benign
            base_request.update({
                "request_rate": random.uniform(1, 10),
                "packet_size": random.randint(100, 1500),
                "uri": f"/page{random.randint(1, 10)}.html"
            })
        
        return base_request
    
    def test_detection(self, request_data: dict) -> dict:
        """Test detection endpoint"""
        try:
            start_time = time.time()
            response = self.session.post(f"{self.base_url}/detect", json=request_data)
            response.raise_for_status()
            total_latency = (time.time() - start_time) * 1000
            
            data = response.json()
            return {
                "success": True,
                "data": data,
                "total_latency_ms": total_latency,
                "api_latency_ms": data.get("inference_time_ms", 0)
            }
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def run_performance_test(self, num_requests: int = 100, concurrent_users: int = 10) -> dict:
        """Run performance test with concurrent requests"""
        print(f"\n🚀 Running performance test: {num_requests} requests, {concurrent_users} concurrent users")
        
        results = []
        attack_types = ["benign"] * 70 + ["ddos_high_rate"] * 10 + ["ddos_large_payload"] * 10 + ["ddos_syn_flood"] * 10
        random.shuffle(attack_types)
        
        start_time = time.time()
        
        def single_request(attack_type):
            request_data = self.generate_test_request(attack_type)
            return self.test_detection(request_data)
        
        with ThreadPoolExecutor(max_workers=concurrent_users) as executor:
            futures = [executor.submit(single_request, attack_types[i % len(attack_types)]) 
                      for i in range(num_requests)]
            
            for i, future in enumerate(as_completed(futures)):
                result = future.result()
                results.append(result)
                
                if (i + 1) % 10 == 0:
                    print(f"  Progress: {i + 1}/{num_requests}")
        
        total_time = time.time() - start_time
        
        # Calculate statistics
        successful_requests = [r for r in results if r["success"]]
        failed_requests = [r for r in results if not r["success"]]
        
        if successful_requests:
            latencies = [r["total_latency_ms"] for r in successful_requests]
            api_latencies = [r["api_latency_ms"] for r in successful_requests]
            
            ddos_detections = [r for r in successful_requests if r["data"]["is_ddos"]]
            benign_detections = [r for r in successful_requests if not r["data"]["is_ddos"]]
            
            stats = {
                "total_requests": num_requests,
                "successful_requests": len(successful_requests),
                "failed_requests": len(failed_requests),
                "success_rate": len(successful_requests) / num_requests * 100,
                "total_time_seconds": total_time,
                "requests_per_second": num_requests / total_time,
                "latency_stats": {
                    "min_ms": min(latencies),
                    "max_ms": max(latencies),
                    "avg_ms": sum(latencies) / len(latencies),
                    "p95_ms": sorted(latencies)[int(len(latencies) * 0.95)]
                },
                "api_latency_stats": {
                    "min_ms": min(api_latencies),
                    "max_ms": max(api_latencies),
                    "avg_ms": sum(api_latencies) / len(api_latencies),
                    "p95_ms": sorted(api_latencies)[int(len(api_latencies) * 0.95)]
                },
                "detection_stats": {
                    "ddos_detected": len(ddos_detections),
                    "benign_detected": len(benign_detections),
                    "ddos_rate": len(ddos_detections) / len(successful_requests) * 100
                }
            }
        else:
            stats = {"error": "No successful requests"}
        
        return stats

def main():
    parser = argparse.ArgumentParser(description="Test Hybrid DDoS Detection System")
    parser.add_argument("--url", required=True, help="Base URL of the deployed system")
    parser.add_argument("--requests", type=int, default=100, help="Number of requests for performance test")
    parser.add_argument("--concurrent", type=int, default=10, help="Number of concurrent users")
    parser.add_argument("--quick", action="store_true", help="Run quick test only")
    
    args = parser.parse_args()
    
    tester = DDoSDetectionTester(args.url)
    
    print("=" * 100)
    print("🔍 HYBRID DDOS DETECTION SYSTEM - TESTING")
    print("=" * 100)
    print(f"Target URL: {args.url}")
    print(f"Timestamp: {datetime.now().isoformat()}")
    print("=" * 100)
    
    # Test health endpoint
    print("\n1️⃣ Testing health endpoint...")
    health_result = tester.test_health()
    if health_result["success"]:
        print("   ✅ Health check passed")
        print(f"   📊 Response time: {health_result['latency_ms']:.2f}ms")
        if health_result["data"]["models_loaded"]:
            print("   🤖 Models loaded successfully")
        else:
            print("   ⚠️ Models not loaded!")
    else:
        print(f"   ❌ Health check failed: {health_result['error']}")
        return
    
    # Test stats endpoint
    print("\n2️⃣ Testing stats endpoint...")
    stats_result = tester.test_stats()
    if stats_result["success"]:
        print("   ✅ Stats endpoint accessible")
        print(f"   💾 Memory usage: {stats_result['data']['memory_usage']['percent']:.1f}%")
        print(f"   🖥️ CPU usage: {stats_result['data']['cpu_usage']:.1f}%")
    else:
        print(f"   ⚠️ Stats endpoint failed: {stats_result['error']}")
    
    # Test single detection
    print("\n3️⃣ Testing detection endpoint...")
    test_request = tester.generate_test_request("benign")
    detection_result = tester.test_detection(test_request)
    if detection_result["success"]:
        data = detection_result["data"]
        print("   ✅ Detection endpoint working")
        print(f"   🎯 DDoS detected: {data['is_ddos']}")
        print(f"   🎲 Confidence: {data['confidence']:.3f}")
        print(f"   ⚡ Inference time: {data['inference_time_ms']:.3f}ms")
        print(f"   📈 Total latency: {detection_result['total_latency_ms']:.2f}ms")
        print(f"   🧠 Features extracted: {data['features_extracted']}")
    else:
        print(f"   ❌ Detection failed: {detection_result['error']}")
        return
    
    if args.quick:
        print("\n✅ Quick test completed successfully!")
        return
    
    # Performance test
    print("\n4️⃣ Running performance test...")
    perf_stats = tester.run_performance_test(args.requests, args.concurrent)
    
    if "error" not in perf_stats:
        print("\n📊 PERFORMANCE TEST RESULTS:")
        print("=" * 50)
        print(f"Total Requests: {perf_stats['total_requests']}")
        print(f"Successful: {perf_stats['successful_requests']} ({perf_stats['success_rate']:.1f}%)")
        print(f"Failed: {perf_stats['failed_requests']}")
        print(f"Total Time: {perf_stats['total_time_seconds']:.2f}s")
        print(f"Throughput: {perf_stats['requests_per_second']:.2f} req/s")
        
        print(f"\nLatency Stats (End-to-End):")
        print(f"  Min: {perf_stats['latency_stats']['min_ms']:.2f}ms")
        print(f"  Max: {perf_stats['latency_stats']['max_ms']:.2f}ms")
        print(f"  Avg: {perf_stats['latency_stats']['avg_ms']:.2f}ms")
        print(f"  P95: {perf_stats['latency_stats']['p95_ms']:.2f}ms")
        
        print(f"\nAPI Latency Stats (Inference Only):")
        print(f"  Min: {perf_stats['api_latency_stats']['min_ms']:.3f}ms")
        print(f"  Max: {perf_stats['api_latency_stats']['max_ms']:.3f}ms")
        print(f"  Avg: {perf_stats['api_latency_stats']['avg_ms']:.3f}ms")
        print(f"  P95: {perf_stats['api_latency_stats']['p95_ms']:.3f}ms")
        
        print(f"\nDetection Stats:")
        print(f"  DDoS Detected: {perf_stats['detection_stats']['ddos_detected']}")
        print(f"  Benign Detected: {perf_stats['detection_stats']['benign_detected']}")
        print(f"  DDoS Rate: {perf_stats['detection_stats']['ddos_rate']:.1f}%")
        
        # SLA Validation
        print(f"\n🎯 SLA VALIDATION:")
        avg_latency = perf_stats['api_latency_stats']['avg_ms']
        throughput = perf_stats['requests_per_second']
        
        if avg_latency < 50:
            print(f"  ✅ Latency SLA: {avg_latency:.3f}ms < 50ms target")
        else:
            print(f"  ❌ Latency SLA: {avg_latency:.3f}ms > 50ms target")
        
        if throughput > 1000:
            print(f"  ✅ Throughput SLA: {throughput:.1f} req/s > 1000 req/s target")
        else:
            print(f"  ⚠️ Throughput SLA: {throughput:.1f} req/s < 1000 req/s target")
        
        # Save results
        results_file = f"test_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(results_file, 'w') as f:
            json.dump({
                "timestamp": datetime.now().isoformat(),
                "target_url": args.url,
                "test_config": {
                    "requests": args.requests,
                    "concurrent": args.concurrent
                },
                "performance_stats": perf_stats
            }, f, indent=2)
        
        print(f"\n💾 Results saved to: {results_file}")
    else:
        print(f"❌ Performance test failed: {perf_stats['error']}")
    
    print("\n✅ Testing completed!")

if __name__ == "__main__":
    main()