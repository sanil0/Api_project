# Pre-LB ML Gateway Architecture - Implementation Guide

**Document Status**: Implementation Guide v2.0  
**Date**: November 2025  
**Architecture**: Gateway-First DDoS Detection (Pre-LB)

---

## Executive Summary

This guide documents the implementation of a **Pre-LB (Pre-Load Balancer) ML Gateway Architecture** for the Hybrid DDoS Detection System. Instead of running the ML detection model on every backend instance, we now deploy it on dedicated gateway instances positioned before the load balancer.

### Key Improvements

| Aspect | Old Architecture (Post-LB) | New Architecture (Pre-LB) | Benefit |
|--------|---------------------------|--------------------------|---------|
| **ML Model Instances** | 3 (one per webserver) | 1 (single gateway) | 66% reduction in model memory |
| **DDoS Filtering** | On each instance | Before reaching backend | Early traffic filtering |
| **Security** | All instances exposed | Webservers isolated | Cleaner security model |
| **Resource Efficiency** | Redundant models | Shared infrastructure | Lower costs, better scaling |
| **Traffic Flow** | Direct to webservers | Through gateway first | Centralized control |

---

## Architecture Overview

### Pre-LB Architecture Diagram

```
                          Internet (Public)
                                 |
                                 | Port 80
                                 ↓
                         ┌───────────────┐
                         │ ML Gateway    │ (Public Subnet)
                         │ ASG (2+ AZs)  │ Port 80 - accepts all traffic
                         │               │ • Stage 1: Binary detection
                         │ • 2-4 instances│ • Stage 2: Attack classification
                         │ • t2.medium   │ • Health checks enabled
                         └───────┬───────┘
                                 |
                    X-Forwarded-For headers
                           Port 9000
                                 ↓
                         ┌───────────────┐
                         │ Internal ALB  │ (Private Subnet)
                         │               │
                         └───────┬───────┘
                                 |
                 ┌────────────────┼────────────────┐
                 ↓                ↓                ↓
          ┌───────────┐    ┌───────────┐   ┌───────────┐
          │ Webserver │    │ Webserver │   │ Webserver │
          │ Instance  │    │ Instance  │   │ Instance  │
          │ Port 9000 │    │ Port 9000 │   │ Port 9000 │
          │(Private)  │    │(Private)  │   │(Private)  │
          └───────────┘    └───────────┘   └───────────┘
```

### Network Topology

**Public Tier (Gateway)**
- Subnets: `10.0.1.0/24`, `10.0.2.0/24` (across 2 AZs)
- Security Group: Allow ingress on port 80, 443 from `0.0.0.0/0`
- Instances: t2.medium (configurable)
- ASG: 2-4 instances with health checks
- Role: DDoS detection and filtering

**Private Tier (Backend)**
- Subnets: `10.0.101.0/24`, `10.0.102.0/24` (across 2 AZs)
- Security Group: Allow ingress on port 9000 from Gateway SG only
- Instances: t2.micro (configurable)
- ASG: 2-10 instances with ALB health checks
- Role: Application serving

---

## Deployment Guide

### Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** v2.x configured with credentials
3. **Terraform** v1.0+
4. **SSH Key Pair** (can be created automatically)
5. **ML Models** in `/models` directory (optional - can be downloaded)

### Step 1: Verify Environment

```bash
# Check AWS CLI
aws --version

# Check Terraform
terraform --version

# Verify AWS credentials
aws sts get-caller-identity
```

### Step 2: Prepare Models

```bash
# Ensure models are trained and saved
cd models
ls -la *.pkl

# Required models:
# - hybrid_stage1_model_v2.pkl
# - hybrid_stage1_scaler_v2.pkl
# - hybrid_stage2_model_v3_real_benign.pkl
# - hybrid_stage2_scaler_v3_real_benign.pkl
```

### Step 3: Deploy Infrastructure

```bash
# Navigate to infrastructure directory
cd infrastructure

# Run deployment script
bash deploy.sh

# Script will:
# 1. Check prerequisites
# 2. Create/verify S3 bucket for models
# 3. Upload models to S3
# 4. Create EC2 key pair
# 5. Initialize Terraform
# 6. Plan infrastructure
# 7. Apply Terraform configuration
# 8. Output deployment details
```

### Step 4: Monitor Initialization

```bash
# Wait 5-10 minutes for instances to boot and initialize

# Check Gateway ASG status
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names hybrid-ddos-detection-gateway-asg \
  --region us-east-1

# Get Gateway instance IP
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=Gateway" \
                "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --region us-east-1
```

### Step 5: Verify Deployment

```bash
# SSH into gateway instance
ssh -i infrastructure/hybrid-ddos-detection-key.pem ubuntu@<gateway-public-ip>

# Check initialization logs
tail -f /var/log/user-data.log

# Verify gateway is running
curl http://localhost:80/health

# Check backend connectivity
curl http://localhost:80/stats

# Exit SSH
exit
```

---

## Configuration

### Gateway Configuration (`ml_gateway/config.json`)

The gateway reads configuration from:

```json
{
  "backend_targets": [
    {
      "host": "internal-alb.amazonaws.com",
      "port": 9000,
      "priority": 1
    }
  ],
  "ml_detection": {
    "threshold": 0.8,
    "window_size": 300
  }
}
```

### Environment Variables

```bash
# Gateway
BACKEND_TARGETS='[{"host":"alb.internal","port":9000}]'
GATEWAY_PORT=80
GATEWAY_HOST=0.0.0.0
GATEWAY_CONFIG=/etc/ml-gateway/config.json

# Webserver
# (None required - uses defaults)
```

### Terraform Variables (`terraform.tfvars`)

```hcl
aws_region              = "us-east-1"
project_name            = "hybrid-ddos-detection"
environment             = "production"
key_pair_name           = "hybrid-ddos-detection-key"

# Gateway tier
gateway_instance_type   = "t2.medium"
gateway_min_instances   = 2
gateway_max_instances   = 4
gateway_desired_instances = 2

# Webserver tier
webserver_instance_type = "t2.micro"
webserver_min_instances = 2
webserver_max_instances = 10
webserver_desired_instances = 3

# Network
vpc_cidr               = "10.0.0.0/16"
public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]
```

---

## Testing the Deployment

### Test 1: Health Checks

```bash
# Get gateway public IP
GATEWAY_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=Gateway" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# Health check
curl http://$GATEWAY_IP/health
```

Expected response:
```json
{
  "status": "healthy",
  "gateway": "ML-based DDoS Detection (Pre-LB)",
  "backend_targets": {
    "http://internal-alb.amazonaws.com:9000": true
  },
  "uptime_seconds": 123.45
}
```

### Test 2: Load Balancing

```bash
# Make requests to gateway
for i in {1..10}; do
  curl http://$GATEWAY_IP/ | jq '.hostname'
done

# Should see round-robin across webservers
```

### Test 3: DDoS Detection

```bash
# Generate traffic to trigger detection
ab -n 100 -c 50 http://$GATEWAY_IP/

# Check stats
curl http://$GATEWAY_IP/stats | jq '.statistics'
```

Expected:
```json
{
  "total_requests": 100,
  "allowed_requests": 95,
  "blocked_requests": 5,
  "block_rate": "5.00%"
}
```

### Test 4: Backend Health

```bash
# Check backend target health
curl http://$GATEWAY_IP/backends

# Should show both targets and health status
```

---

## Scaling Configuration

### Scale Gateway (DDoS Detection Tier)

```bash
# Increase to 4 instances for higher capacity
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name hybrid-ddos-detection-gateway-asg \
  --desired-capacity 4 \
  --region us-east-1

# Monitor scaling
watch 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names hybrid-ddos-detection-gateway-asg \
  --region us-east-1 \
  --query "AutoScalingGroups[0].[DesiredCapacity,Instances[].InstanceId]"'
```

### Scale Webservers (Backend Tier)

```bash
# Increase webserver capacity
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name hybrid-ddos-detection-webserver-asg \
  --desired-capacity 5 \
  --region us-east-1
```

---

## Monitoring & Troubleshooting

### View Logs

```bash
# SSH into gateway
ssh -i infrastructure/hybrid-ddos-detection-key.pem ubuntu@$GATEWAY_IP

# Gateway logs
tail -100f /var/log/ml-gateway.log

# Supervisor logs
supervisorctl tail ml-gateway -f

# System initialization
tail -f /var/log/user-data.log

# Exit
exit
```

### Common Issues

#### Issue: Gateway instances not healthy
```bash
# Check instance status
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=Gateway" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceStateName,StateTransitionReason]'

# Check system logs
aws ec2 get-console-output --instance-id i-xxxxxxxxxxxx
```

#### Issue: Backend connectivity failed
```bash
# Check webserver instances
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=Webserver" \
  --query 'Reservations[].Instances[].[PrivateIpAddress,InstanceStateName]'

# Test from gateway
ssh -i infrastructure/hybrid-ddos-detection-key.pem ubuntu@$GATEWAY_IP
curl http://<webserver-private-ip>:9000/health
exit
```

#### Issue: DDoS detection not working
```bash
# SSH into gateway
ssh -i infrastructure/hybrid-ddos-detection-key.pem ubuntu@$GATEWAY_IP

# Check if models are loaded
ls -la /opt/ml-gateway/models/*.pkl

# Check Python imports
python3 -c "import pickle; print(pickle.load(open('models/hybrid_stage1_model_v2.pkl', 'rb')))"

exit
```

---

## Rollback Procedure

If you need to revert to the old post-LB architecture:

### Step 1: Backup Current Configuration

```bash
cd infrastructure/terraform
terraform state pull > terraform.state.backup
```

### Step 2: Destroy Pre-LB Infrastructure

```bash
terraform destroy \
  -var="gateway_desired_instances=0" \
  -var="webserver_desired_instances=0"

# Confirm: yes
```

### Step 3: Revert to Old Configuration

```bash
# Switch back to old main.tf
git checkout main.tf

# Or restore from backup
cp main.tf.backup main.tf

# Re-initialize and apply
terraform init
terraform plan
terraform apply
```

---

## Migration from Post-LB to Pre-LB

If migrating from the old architecture:

### Step 1: Prepare

```bash
# Document old deployment
cd infrastructure/terraform
terraform show > old_state.txt
terraform output > old_outputs.txt

# Backup Terraform state
cp terraform.tfstate terraform.tfstate.old
```

### Step 2: Deploy New Pre-LB Infrastructure

```bash
# Update main.tf with new configuration (already done)

# Re-initialize
terraform init

# Deploy new infrastructure alongside old
terraform apply -var="project_name=hybrid-ddos-detection-v2"

# This creates new resources without affecting old ones
```

### Step 3: Verify New Infrastructure

```bash
# Run full test suite
python test_gateway.py
python test_hybrid_model.py

# Check all endpoints
./verify_deployment.sh
```

### Step 4: Cutover Traffic

```bash
# Update DNS/load balancer to point to new gateway
# Or update client configurations to use new gateway IP

# Monitor metrics during cutover
watch 'curl http://$NEW_GATEWAY_IP/stats'
```

### Step 5: Decommission Old Infrastructure

```bash
# After 24-48 hours of successful operation

# Destroy old infrastructure
terraform destroy -var="project_name=hybrid-ddos-detection"

# Confirm: yes
```

---

## Performance Tuning

### Gateway Tuning

```bash
# SSH into gateway
ssh -i infrastructure/hybrid-ddos-detection-key.pem ubuntu@$GATEWAY_IP

# Increase uvicorn workers for better throughput
# Edit: /etc/supervisor/conf.d/ml-gateway.conf
sudo nano /etc/supervisor/conf.d/ml-gateway.conf

# Change workers parameter (4 is default):
# command=/opt/ml-gateway/venv/bin/python -m uvicorn ml_gateway.app:app --workers 8 ...

# Restart supervisor
sudo supervisorctl restart ml-gateway

exit
```

### Model Optimization

```bash
# If detection latency is high:
# 1. Reduce window_size in config.json (default 300s)
# 2. Reduce threshold if needed (default 0.8)
# 3. Upgrade to faster instance type (t2.large)

# Check latency
curl -w "Time: %{time_total}s\n" http://$GATEWAY_IP/stats
```

---

## Cost Analysis

### Infrastructure Costs (US-East-1)

| Component | Quantity | Type | Cost/Month |
|-----------|----------|------|-----------|
| Gateway Instances | 2 | t2.medium | ~$30 |
| Webserver Instances | 3 | t2.micro | ~$7.50 |
| Data Transfer | - | Out of VPC | ~$5-15 |
| **Total** | | | **~$42.50** |

**Savings vs Post-LB**: ~30-40% (fewer instances needed)

---

## Operational Guidelines

### Daily Operations

1. Monitor CloudWatch metrics for:
   - Gateway CPU/memory usage
   - Webserver response times
   - DDoS detection rate

2. Check logs for:
   - Error patterns
   - Unusual traffic
   - Model inference issues

3. Scale as needed:
   - Gateway: If >70% CPU
   - Webserver: If >75% CPU

### Weekly

- Review DDoS metrics
- Check model performance
- Update models if needed (reupload to S3)

### Monthly

- Review cost trends
- Optimize instance types
- Update security group rules if needed

---

## Appendix A: API Endpoints

### Gateway Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/` | GET | Gateway info |
| `/health` | GET | Health check |
| `/stats` | GET | Statistics |
| `/metrics` | GET | Monitoring metrics |
| `/backends` | GET | Backend status |
| `/block/{ip}` | POST | Block IP |
| `/unblock/{ip}` | POST | Unblock IP |
| `/*` | ALL | Proxy to backend |

### Example Calls

```bash
# Gateway info
curl http://$GATEWAY_IP/

# Statistics
curl http://$GATEWAY_IP/stats | jq

# Metrics
curl http://$GATEWAY_IP/metrics | jq

# Backend status
curl http://$GATEWAY_IP/backends | jq

# Block an IP for 10 minutes (600 seconds)
curl -X POST http://$GATEWAY_IP/block/192.0.2.1?duration=600

# Unblock an IP
curl -X POST http://$GATEWAY_IP/unblock/192.0.2.1
```

---

## Appendix B: Useful AWS CLI Commands

```bash
# List gateway instances
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=Gateway" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress,PrivateIpAddress]' \
  --output table

# List webserver instances
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=Webserver" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,InstanceStateName]' \
  --output table

# Get ALB details
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?Tags[?Key==`Name` && Value==`hybrid-ddos-detection-backend-alb`]]'

# Check ASG status
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[?Tags[?Key==`Project` && Value==`hybrid-ddos-detection`]]' \
  --output table

# Stream CloudWatch logs
aws logs tail /aws/ec2/hybrid-ddos-detection --follow
```

---

## Support & Troubleshooting

For additional help:

1. Check `/var/log/user-data.log` on instances
2. Review AWS CloudWatch metrics
3. Check Terraform state for resource issues
4. Verify security group rules allow required traffic
5. Ensure S3 bucket has correct models uploaded

---

**End of Document**
