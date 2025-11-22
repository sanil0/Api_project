# AWS Deployment Verification Checklist

Use this checklist to verify your deployment is working correctly.

## Pre-Deployment Checklist

- [ ] AWS CLI installed and configured: `aws sts get-caller-identity`
- [ ] PowerShell 5.1+: `$PSVersionTable.PSVersion`
- [ ] AWS region set to us-east-1
- [ ] Sufficient EC2 quota for instances
- [ ] Security group with rules allows SSH (port 22) from your IP

---

## Step-by-Step Verification

### After VPC Creation (Step 1)
```powershell
# List VPCs to verify creation
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=ddos-vpc" --query 'Vpcs[0]'

# Expected output: VpcId, CidrBlock=10.0.0.0/16, State=available
```

**Checklist:**
- [ ] VPC created with CIDR 10.0.0.0/16
- [ ] Internet Gateway attached
- [ ] 4 subnets created (2 public, 2 private)
- [ ] Route table configured with IGW route
- [ ] Public IPs enabled on gateway subnets

---

### After Security Groups (Step 2)
```powershell
# List security groups
aws ec2 describe-security-groups --filters "Name=group-name,Values=ddos-gateway-sg" --query 'SecurityGroups[0]'

# Verify ingress rules exist for:
# - Port 80 (HTTP)
# - Port 443 (HTTPS, optional)
# - Port 22 (SSH)
```

**Checklist:**
- [ ] Gateway SG has port 80 from 0.0.0.0/0
- [ ] Gateway SG has port 22 from 0.0.0.0/0
- [ ] Webserver SG has port 9000 from Gateway SG
- [ ] Webserver SG has port 22 for SSH

---

### After Key Pair Creation (Step 3)
```powershell
# Verify key file exists and has correct permissions
Test-Path ddos-key.pem
(Get-Item ddos-key.pem).Length  # Should be ~1700 bytes

# List key pairs in AWS
aws ec2 describe-key-pairs --key-names ddos-key
```

**Checklist:**
- [ ] ddos-key.pem file created locally
- [ ] Key file is readable (not corrupted)
- [ ] Key pair registered in AWS

---

### After Instance Launch (Step 5)

#### Check Instance Status
```powershell
# Get instance details
aws ec2 describe-instances `
  --filters "Name=tag:Name,Values=gateway-1" `
  --query 'Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress}'

# Expected output:
# InstanceId: i-xxxxxxxxxxxxx
# State: running
# PublicIp: 54.xxx.xxx.xxx (should exist)
# PrivateIp: 10.0.1.x
```

**Checklist:**
- [ ] Both instances show "running" state
- [ ] Both instances have public IPs assigned
- [ ] Both instances in correct subnets (10.0.1.x, 10.0.2.x)
- [ ] Security group correctly applied

#### Test SSH Access
```powershell
# SSH into instance (use actual IP)
ssh -i ddos-key.pem ubuntu@<PUBLIC_IP>

# Once connected, verify system is ready
cat /var/log/user-data.log  # Should show initialization completed

# Check Python is installed
python3 --version  # Should be 3.10+

# Check ddos user exists
id ddos  # Should return user info

# Check venv exists
ls -la /home/ddos/venv/bin/uvicorn  # Should exist and be executable
```

**Checklist:**
- [ ] SSH connection successful
- [ ] User-data.log shows successful initialization
- [ ] Python 3.10+ installed
- [ ] ddos user created
- [ ] Python venv created at `/home/ddos/venv`
- [ ] FastAPI and uvicorn installed in venv
- [ ] App file exists: `/home/ddos/app/main.py`

---

### After Service Startup (Wait 3-5 minutes)

#### Check Systemd Service
```powershell
# SSH into instance first
ssh -i ddos-key.pem ubuntu@<PUBLIC_IP>

# Inside instance:
# Check if service is enabled and running
sudo systemctl status ddos-gateway

# Expected output: active (running) - green ● symbol

# View recent logs
sudo journalctl -u ddos-gateway -n 20

# Expected: No error messages, clean startup

# Check if service auto-starts
sudo systemctl is-enabled ddos-gateway
# Expected: enabled
```

**Checklist:**
- [ ] Service status shows "active (running)"
- [ ] No error messages in journalctl
- [ ] Service auto-start enabled
- [ ] Service started in less than 1 minute

#### Check Application Process
```powershell
# Inside instance via SSH

# Check if uvicorn process is running
ps aux | grep uvicorn

# Expected output shows line like:
# ddos ... /home/ddos/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000

# Check if port 8000 is listening
sudo netstat -tlnp | grep 8000
# or
sudo ss -tlnp | grep 8000

# Expected output:
# tcp 0 0 0.0.0.0:8000 0.0.0.0:* LISTEN 1234/python3
```

**Checklist:**
- [ ] Uvicorn process running under ddos user
- [ ] Port 8000 listening on all interfaces
- [ ] Process shows "uvicorn main:app" in command
- [ ] No zombie processes

#### Check Nginx Reverse Proxy
```powershell
# Inside instance via SSH

# Check Nginx status
sudo systemctl status nginx

# Expected: active (running)

# Verify Nginx configuration
sudo nginx -t

# Expected: "syntax is ok" and "test is successful"

# Check if port 80 is listening
sudo netstat -tlnp | grep 80
# or
sudo ss -tlnp | grep 80

# Expected: tcp listening on 0.0.0.0:80

# View Nginx access logs
sudo tail -f /var/log/nginx/access.log

# View Nginx error logs (if any)
sudo tail -f /var/log/nginx/error.log
```

**Checklist:**
- [ ] Nginx process running and active
- [ ] Config test passes without errors
- [ ] Port 80 listening globally
- [ ] Nginx logs show requests being proxied

---

### Test Application Endpoints

#### Local Test (From Instance)
```powershell
# Inside instance via SSH

# Test local FastAPI endpoint
curl http://localhost:8000/health

# Expected response:
# {"status":"ok","uptime_sec":XXX.XX,"blocked_ips":0,"total_requests":X,"blocked_requests":0}

# Test through Nginx proxy
curl http://localhost:80/health

# Expected: Same response as above

# Test stats endpoint
curl http://localhost:8000/stats

# Expected response:
# {"total_requests":X,"blocked_requests":0,"unique_blocked_ips":0,"uptime_minutes":X.XX}
```

**Checklist:**
- [ ] FastAPI `/health` endpoint responds with JSON
- [ ] FastAPI `/stats` endpoint responds with JSON
- [ ] Response includes correct keys and values
- [ ] HTTP status code is 200
- [ ] Nginx proxy works locally

#### Remote Test (From Your Computer)
```powershell
# From your local PowerShell (not SSH'd into instance)

# Test from external internet
curl http://<PUBLIC_IP>/health

# Expected: Same JSON response as local test

# Test stats endpoint
curl http://<PUBLIC_IP>/stats

# Test response time (should be <1 second)
Measure-Command { curl http://<PUBLIC_IP>/health } | Select-Object TotalMilliseconds
```

**Checklist:**
- [ ] Health endpoint responds from public IP
- [ ] Stats endpoint responds from public IP
- [ ] Response times reasonable (<1 second)
- [ ] Can test both gateway instances
- [ ] No errors in Nginx error log

---

### Verify App Behavior

#### Test Request Counting
```powershell
# Make multiple requests and check stats
curl http://<PUBLIC_IP>/health
curl http://<PUBLIC_IP>/health
curl http://<PUBLIC_IP>/health

# Check stats - total_requests should increase
curl http://<PUBLIC_IP>/stats

# Expected: {"total_requests":3, ...}
```

**Checklist:**
- [ ] Request counter increments with each request
- [ ] Stats show cumulative request count
- [ ] Blocked requests counter starts at 0

#### Test Proxy Path Handler
```powershell
# Test arbitrary path routing (proxies to backend)
curl http://<PUBLIC_IP>/test/path

# Expected (if no backend):
# {"detail":"Not Found"} or 502 "backend unavailable"

# This shows request was accepted and routing attempted
```

**Checklist:**
- [ ] Arbitrary paths are accepted by proxy
- [ ] Returns meaningful error if backend unavailable
- [ ] Doesn't crash on unknown paths

---

### Load Test (Optional)

```powershell
# Simple load test with ApacheBench (install if needed)
ab -n 100 -c 10 http://<PUBLIC_IP>/health

# Expected output:
# Requests per second: >100
# Failed requests: 0
# Time taken: <1 second
```

**Checklist:**
- [ ] Handles concurrent requests
- [ ] No failed requests under light load
- [ ] Reasonable throughput

---

## Full Success Criteria

**Infrastructure:**
- [x] VPC with proper CIDR and subnets created
- [x] Internet Gateway configured
- [x] Security groups with correct rules
- [x] Key pair created and accessible
- [x] 2 Gateway instances launched and running
- [x] Public IPs assigned to gateway instances
- [x] SSH access working

**Application:**
- [x] User-data script executed successfully
- [x] Python venv created with dependencies
- [x] Systemd service installed and enabled
- [x] FastAPI application file exists
- [x] Uvicorn process running on port 8000
- [x] Nginx configured as reverse proxy on port 80
- [x] Both gateway instances operational

**Functionality:**
- [x] `/health` endpoint responds with valid JSON
- [x] `/stats` endpoint responds with valid JSON
- [x] Request counting works
- [x] Can be accessed from public internet
- [x] Response times acceptable
- [x] Handles concurrent requests

**If All Boxes Checked:** ✅ **DEPLOYMENT SUCCESSFUL**

---

## Rollback Procedure

If deployment fails, you can clean up:

```powershell
# Terminate instances
aws ec2 terminate-instances --instance-ids $INSTANCE1_ID $INSTANCE2_ID

# Delete security groups (wait for instances to terminate first)
aws ec2 delete-security-group --group-id $GW_SG_ID
aws ec2 delete-security-group --group-id $WEB_SG_ID

# Delete subnets
aws ec2 delete-subnet --subnet-id $SUBNET1_ID
aws ec2 delete-subnet --subnet-id $SUBNET2_ID
aws ec2 delete-subnet --subnet-id $SUBNET3_ID
aws ec2 delete-subnet --subnet-id $SUBNET4_ID

# Detach and delete Internet Gateway
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID

# Delete VPC
aws ec2 delete-vpc --vpc-id $VPC_ID

# Delete key pair
aws ec2 delete-key-pair --key-name ddos-key
```

---

## Common Issues and Solutions

### Issue: Health endpoint returns 502 Bad Gateway

**Cause:** Uvicorn not running or still starting up

**Solution:**
```bash
# SSH into instance
ssh -i ddos-key.pem ubuntu@<IP>

# Check service status
sudo systemctl status ddos-gateway

# View logs
sudo journalctl -u ddos-gateway -n 50

# If service is failed, restart it
sudo systemctl restart ddos-gateway

# Wait 10-20 seconds for startup
sleep 20

# Test again
curl http://localhost:8000/health
```

### Issue: Can't SSH into instance

**Cause:** Security group or key permissions issue

**Solution:**
```powershell
# Check security group allows port 22
aws ec2 describe-security-groups --group-ids $GW_SG_ID

# Check key permissions
icacls ddos-key.pem

# Try SSH with verbose output
ssh -v -i ddos-key.pem ubuntu@<IP>
```

### Issue: Port 80 not responding but FastAPI works

**Cause:** Nginx not running or misconfigured

**Solution:**
```bash
# SSH into instance
ssh -i ddos-key.pem ubuntu@<IP>

# Check Nginx status
sudo systemctl status nginx

# Test Nginx config
sudo nginx -t

# View Nginx errors
sudo tail -f /var/log/nginx/error.log

# Restart Nginx
sudo systemctl restart nginx
```

### Issue: Health endpoint returns different response

**Cause:** App may have issues or modified code

**Solution:**
```bash
# Check app file exists and is readable
cat /home/ddos/app/main.py

# Verify it's owned by ddos user
ls -la /home/ddos/app/main.py

# Check app logs for errors
sudo journalctl -u ddos-gateway -n 100 | grep -i error
```

---

## Performance Expectations

| Metric | Expected Value |
|--------|---|
| Response time (p50) | <50ms |
| Response time (p99) | <200ms |
| Requests/second capacity | 1000+ |
| CPU usage (idle) | <5% |
| Memory usage (idle) | <100MB |
| Service startup time | 30-60 seconds |

---

Your deployment is verified when you can run:
```bash
curl http://GATEWAY_IP/health
# Returns {"status":"ok",...}
```

And see the same on both gateway instances.
