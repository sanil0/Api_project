#!/usr/bin/env python
"""
Simulate real DDoS attack patterns and test detection
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

from ml_gateway.detectors.http_detector import HTTPDDoSDetector
import time
import random

print("=" * 90)
print("DDoS ATTACK SIMULATION - DETECTION TEST")
print("=" * 90)

# Initialize detector
detector = HTTPDDoSDetector(window_size=300, threshold=0.35)
print("\n✅ Detector initialized with threshold=0.35")
print("   Lower confidence scores = more normal traffic")
print("   Higher confidence scores (>0.35) = DDoS detected")

# Test 1: Extreme DDoS - 100 requests in rapid fire
print("\n" + "=" * 90)
print("TEST 1: EXTREME DDoS ATTACK (100 rapid requests)")
print("=" * 90)

attacker_ip = '203.0.113.50'
attack_detected = 0
max_confidence = 0
start_time = time.time()

print(f"\nSending 100 requests from {attacker_ip} in rapid succession...")
for i in range(100):
    request_data = {
        'method': 'GET',
        'path': f'/api/data/{random.randint(1, 1000)}',
        'user_agent': 'bot-attack/2.0',
        'referer': None,
        'headers': {}
    }
    prediction, confidence = detector.analyze_request(attacker_ip, request_data)
    max_confidence = max(max_confidence, confidence)
    
    if i % 20 == 0:  # Print every 20 requests
        status = "🔴 BLOCKED" if prediction == "DDoS" else "✅ ALLOWED"
        print(f"  Request {i:3d}: {status} | Confidence: {confidence:.2f}")
    
    if prediction == "DDoS" and confidence > detector.threshold:
        attack_detected += 1

elapsed = time.time() - start_time
print(f"\nResults: {attack_detected}/100 requests flagged as DDoS")
print(f"Max confidence score reached: {max_confidence:.2f} (threshold: {detector.threshold})")
if elapsed > 0:
    print(f"Time: {elapsed:.2f}s | Avg: {100/elapsed:.1f} req/s")
else:
    print(f"Time: < 0.01s (too fast to measure)")

# Test 2: Multi-source attack (distributed from different IPs)
print("\n" + "=" * 90)
print("TEST 2: DISTRIBUTED ATTACK (20 IPs, 5 requests each)")
print("=" * 90)

print(f"\nSimulating 20 different attacker IPs sending 5 requests each...")
distributed_detected = 0
base_ip = "203.0.113"

for ip_num in range(1, 21):
    attacker_ip = f"{base_ip}.{ip_num}"
    
    for req_num in range(5):
        request_data = {
            'method': 'GET',
            'path': f'/api/attack/{req_num}',
            'user_agent': 'bot-distributed/1.0',
            'referer': None,
            'headers': {}
        }
        prediction, confidence = detector.analyze_request(attacker_ip, request_data)
        
        if prediction == "DDoS" and confidence > detector.threshold:
            distributed_detected += 1
            print(f"  🔴 BLOCKED: {attacker_ip} - Confidence: {confidence:.2f}")

print(f"\nDistributed attack detection: {distributed_detected}/100 requests flagged")

# Test 3: Sustained attack over time (simulated)
print("\n" + "=" * 90)
print("TEST 3: SUSTAINED ATTACK (50 requests over 5 seconds)")
print("=" * 90)

attacker_ip = '203.0.113.100'
sustained_detected = 0
interval = 0.1  # 100ms between requests

print(f"\nSending 50 requests from {attacker_ip} with {interval*1000:.0f}ms intervals...")
start_time = time.time()

for i in range(50):
    request_data = {
        'method': 'POST',
        'path': '/api/attack',
        'user_agent': 'bot-sustained/1.0',
        'referer': None,
        'headers': {'X-Forwarded-For': f'203.0.113.100, 203.0.113.{random.randint(1,255)}'}
    }
    
    prediction, confidence = detector.analyze_request(attacker_ip, request_data)
    
    if i % 10 == 0:
        status = "🔴 BLOCKED" if prediction == "DDoS" else "✅ ALLOWED"
        print(f"  Request {i:2d}: {status} | Confidence: {confidence:.2f}")
    
    if prediction == "DDoS" and confidence > detector.threshold:
        sustained_detected += 1
    
    time.sleep(interval)

elapsed = time.time() - start_time
print(f"\nSustained attack detection: {sustained_detected}/50 requests flagged")
print(f"Time: {elapsed:.2f}s")

# Test 4: Low-and-slow attack (tries to stay under radar)
print("\n" + "=" * 90)
print("TEST 4: LOW-AND-SLOW ATTACK (20 requests, 0.5s apart)")
print("=" * 90)

attacker_ip = '203.0.113.200'
slow_detected = 0

print(f"\nSending 20 requests from {attacker_ip} with 0.5s intervals (tries to avoid detection)...")
start_time = time.time()

for i in range(20):
    request_data = {
        'method': 'GET',
        'path': f'/download/large-file-{i}.zip',
        'user_agent': 'Mozilla/5.0 (but really a bot)',
        'referer': None,
        'headers': {}
    }
    
    prediction, confidence = detector.analyze_request(attacker_ip, request_data)
    
    status = "🔴 BLOCKED" if prediction == "DDoS" else "✅ ALLOWED"
    print(f"  Request {i+1:2d}: {status} | Confidence: {confidence:.2f}")
    
    if prediction == "DDoS" and confidence > detector.threshold:
        slow_detected += 1
    
    time.sleep(0.5)

elapsed = time.time() - start_time
print(f"\nLow-and-slow attack detection: {slow_detected}/20 requests flagged")
print(f"Time: {elapsed:.2f}s")

# Summary
print("\n" + "=" * 90)
print("ATTACK SIMULATION SUMMARY")
print("=" * 90)

print(f"\n📊 Detection Results:")
print(f"   1. Extreme DDoS (100 rapid):    {attack_detected:2d}/100 detected ({100*attack_detected/100:.0f}%)")
print(f"   2. Distributed (20 IPs):        {distributed_detected:2d}/100 detected ({100*distributed_detected/100:.0f}%)")
print(f"   3. Sustained (50 requests):     {sustained_detected:2d}/50 detected ({100*sustained_detected/50:.0f}%)")
print(f"   4. Low-and-slow (20 requests):  {slow_detected:2d}/20 detected ({100*slow_detected/20:.0f}%)")

total_detected = attack_detected + distributed_detected + sustained_detected + slow_detected
total_requests = 100 + 100 + 50 + 20
detection_rate = 100 * total_detected / total_requests

print(f"\n🎯 Overall Detection Rate: {total_detected}/{total_requests} ({detection_rate:.1f}%)")

if detection_rate >= 80:
    print("✅ EXCELLENT: DDoS detection is working effectively!")
elif detection_rate >= 60:
    print("⚠️  GOOD: Detection working but could be tuned")
else:
    print("❌ WEAK: Detection threshold may be too high, consider lowering from 0.80")

print("\n" + "=" * 90)
