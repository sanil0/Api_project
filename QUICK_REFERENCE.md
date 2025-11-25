# Pre-LB Architecture - Quick Reference Card

## What Changed

**Old**: ALB → 3 instances (each with gateway + webapp)  
**New**: Gateway (port 80) → Internal ALB → 3 webservers (port 9000)

## Key Benefits

| Aspect | Old | New | Gain |
|--------|-----|-----|------|
| ML Models | 3 copies | 1 copy | 66% memory savings |
| DDoS Filtering | Per-instance | Centralized | Early blocking |
| Security | All exposed | Gateway+Private | Better isolation |
| Scaling | Monolithic | Independent | Flexible sizing |
| Management | 3 gateways | 1 gateway tier | Easier ops |

## Deploy in 3 Steps

```bash
cd infrastructure
aws configure    # Setup AWS credentials
bash deploy.sh   # Automated deployment
```

## Check Deployment

```bash
# Get gateway IP
GATEWAY_IP=$(aws ec2 describe-instances \
  --filters Name=tag:Role,Values=Gateway Name=instance-state-name,Values=running \
  --query Reservations[0].Instances[0].PublicIpAddress --output text)

# Test health
curl http://$GATEWAY_IP/health

# Check stats
curl http://$GATEWAY_IP/stats | jq
```

## Architecture Diagram

```
Internet (Public)
    ↓ Port 80
[ML Gateway ASG]  ← Detects DDoS
    ↓ Port 9000
[Internal ALB]
    ↓
[Webserver ASG]   ← Protected backend
```

## Network Tiers

**Gateway Tier (Public)**
- Subnets: 10.0.1.0/24, 10.0.2.0/24
- Instances: 2-4 × t2.medium
- Port: 80
- Role: DDoS detection & filtering

**Backend Tier (Private)**
- Subnets: 10.0.101.0/24, 10.0.102.0/24
- Instances: 2-10 × t2.micro
- Port: 9000
- Role: Web application

## Key Files

| File | Purpose |
|------|---------|
| `ml_gateway/app.py` | Gateway application (multi-target LB) |
| `infrastructure/terraform/main.tf` | Infrastructure as Code |
| `infrastructure/deploy.sh` | One-click deployment |
| `PRE_LB_IMPLEMENTATION_GUIDE.md` | Detailed guide |
| `ml_gateway/config.json` | Gateway configuration |

## API Endpoints

```bash
/health      → Gateway health
/stats       → Detection statistics
/metrics     → Monitoring metrics
/backends    → Backend target status
/block/{ip}  → Block IP address
```

## Common Commands

```bash
# View gateway instances
aws ec2 describe-instances --filters "Name=tag:Role,Values=Gateway" --output table

# View webserver instances
aws ec2 describe-instances --filters "Name=tag:Role,Values=Webserver" --output table

# Scale gateway up
aws autoscaling set-desired-capacity --auto-scaling-group-name hybrid-ddos-detection-gateway-asg --desired-capacity 4

# SSH into gateway
ssh -i infrastructure/hybrid-ddos-detection-key.pem ubuntu@$GATEWAY_IP

# View gateway logs
tail -f /var/log/ml-gateway.log
```

## Rollback (if needed)

```bash
cd infrastructure/terraform
terraform destroy  # Removes all resources
```

## Cost Estimate

- Gateway (2×t2.medium): ~$30/month
- Webserver (3×t2.micro): ~$7.50/month
- Data: ~$10/month
- **Total**: ~$47.50/month

## Files Changed

✅ `ml_gateway/app.py` - Added BackendManager, multi-target load balancing  
✅ `infrastructure/terraform/main.tf` - Complete rewrite for 2-tier architecture  
✅ `infrastructure/terraform/user_data_gateway.sh` - Gateway initialization  
✅ `infrastructure/terraform/user_data_webserver.sh` - Webserver initialization  
✅ `infrastructure/deploy.sh` - Enhanced deployment script  
✅ `ml_gateway/config.json` - Created gateway configuration  
✅ `PRE_LB_IMPLEMENTATION_GUIDE.md` - Comprehensive documentation  

## Troubleshooting

| Issue | Check |
|-------|-------|
| Gateway not responding | `aws autoscaling describe-auto-scaling-groups` |
| Can't reach backend | Security groups (allow port 9000 from gateway) |
| Models not loaded | `ls /opt/ml-gateway/models/` on gateway |
| High latency | Check gateway CPU, scale up if >70% |

## Next: Run Tests

```bash
# Test detection
python test_gateway.py

# Test model
python test_hybrid_model.py

# Run with Apache Bench
ab -n 100 -c 10 http://$GATEWAY_IP/
```

---

**Full Guide**: See `PRE_LB_IMPLEMENTATION_GUIDE.md`  
**Summary**: See `PRE_LB_IMPLEMENTATION_SUMMARY.md`
