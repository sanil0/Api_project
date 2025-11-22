# AWS Quick Reference Commands

Copy-paste ready commands for common tasks.

## Store IDs in Variables (Do This First)

```powershell
# After running deployment, save these IDs for later use:
$VPC_ID = "vpc-xxxxx"
$SUBNET1_ID = "subnet-xxxxx"
$SUBNET2_ID = "subnet-xxxxx"
$SUBNET3_ID = "subnet-xxxxx"
$SUBNET4_ID = "subnet-xxxxx"
$GW_SG_ID = "sg-xxxxx"
$WEB_SG_ID = "sg-xxxxx"
$INSTANCE1_ID = "i-xxxxx"
$INSTANCE2_ID = "i-xxxxx"
$IP1 = "54.xxx.xxx.xxx"
$IP2 = "54.xxx.xxx.xxx"
```

---

## Quick Test Commands

```powershell
# Test both instances
curl http://$IP1/health
curl http://$IP2/health

# Test stats
curl http://$IP1/stats
curl http://$IP2/stats

# Batch test
foreach ($ip in @($IP1, $IP2)) {
    Write-Host "Testing $ip..."
    curl http://$ip/health
}
```

---

## SSH Quick Commands

```powershell
# SSH into instance 1
ssh -i ddos-key.pem ubuntu@$IP1

# Once inside, check status
sudo systemctl status ddos-gateway
sudo journalctl -u ddos-gateway -f     # Follow logs
sudo systemctl restart ddos-gateway    # Restart service
ps aux | grep uvicorn                  # Check process
curl http://localhost:8000/health      # Test locally
curl http://localhost/health           # Test through Nginx

# View startup logs
sudo cat /var/log/user-data.log

# Tail Nginx errors
sudo tail -f /var/log/nginx/error.log

# Check listening ports
sudo netstat -tlnp | grep -E '80|8000'
```

---

## List AWS Resources

```powershell
# List VPCs
aws ec2 describe-vpcs --query 'Vpcs[].{VpcId:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' --output table

# List Instances
aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query 'Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name,IP:PublicIpAddress,PrivateIP:PrivateIpAddress}' --output table

# List Security Groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[].{GroupId:GroupId,Name:GroupName,IngressRules:IpPermissions|length(@)}' --output table

# List Subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].{SubnetId:SubnetId,CIDR:CidrBlock,Name:Tags[?Key==`Name`].Value|[0],AZ:AvailabilityZone}' --output table

# List Key Pairs
aws ec2 describe-key-pairs --query 'KeyPairs[].{KeyName:KeyName,Fingerprint:KeyFingerprint}' --output table
```

---

## Get Specific Information

```powershell
# Get instance status
aws ec2 describe-instance-status --instance-ids $INSTANCE1_ID --query 'InstanceStatuses[0]'

# Get public IPs
aws ec2 describe-instances --instance-ids $INSTANCE1_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text

# Get private IPs
aws ec2 describe-instances --instance-ids $INSTANCE1_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text

# Get security group details
aws ec2 describe-security-groups --group-ids $GW_SG_ID --query 'SecurityGroups[0]'

# Get VPC details
aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0]'
```

---

## Stop/Start Instances

```powershell
# Stop instances (preserves data, cheaper)
aws ec2 stop-instances --instance-ids $INSTANCE1_ID $INSTANCE2_ID

# Start instances
aws ec2 start-instances --instance-ids $INSTANCE1_ID $INSTANCE2_ID

# Check status
aws ec2 describe-instances --instance-ids $INSTANCE1_ID --query 'Reservations[0].Instances[0].State.Name' --output text

# Reboot instances
aws ec2 reboot-instances --instance-ids $INSTANCE1_ID $INSTANCE2_ID
```

---

## Modify Security Groups

```powershell
# Add rule to allow traffic from specific IP
aws ec2 authorize-security-group-ingress `
  --group-id $GW_SG_ID `
  --protocol tcp `
  --port 80 `
  --cidr 192.0.2.0/24

# Remove rule
aws ec2 revoke-security-group-ingress `
  --group-id $GW_SG_ID `
  --protocol tcp `
  --port 80 `
  --cidr 192.0.2.0/24

# Allow SSH from specific IP only
aws ec2 authorize-security-group-ingress `
  --group-id $GW_SG_ID `
  --protocol tcp `
  --port 22 `
  --cidr YOUR_IP/32
```

---

## Manage Services (From SSH)

```bash
# Start/stop/restart systemd service
sudo systemctl start ddos-gateway
sudo systemctl stop ddos-gateway
sudo systemctl restart ddos-gateway

# Check service status
sudo systemctl status ddos-gateway

# Enable/disable auto-start
sudo systemctl enable ddos-gateway
sudo systemctl disable ddos-gateway

# View service logs
sudo journalctl -u ddos-gateway              # All logs
sudo journalctl -u ddos-gateway -n 50        # Last 50 lines
sudo journalctl -u ddos-gateway -f           # Follow in real-time
sudo journalctl -u ddos-gateway --since=1h   # Last hour

# View system logs
sudo tail -f /var/log/syslog
```

---

## Test Network Connectivity

```bash
# Test port listening (from instance)
sudo netstat -tlnp | grep -E '80|8000|9000'

# Test curl to local app
curl -v http://localhost:8000/health      # Verbose output
curl -I http://localhost:8000/health      # Headers only
curl -w "%{http_code}\n" http://localhost/health  # Just HTTP code

# Test from another instance
ssh -i ddos-key.pem ubuntu@$IP2
  curl http://$IP1/health

# Measure response time
time curl http://localhost/health
```

---

## Common Nginx Commands (From SSH)

```bash
# Test Nginx config
sudo nginx -t

# Reload config without restart
sudo systemctl reload nginx

# Restart Nginx
sudo systemctl restart nginx

# View Nginx access logs
sudo tail -f /var/log/nginx/access.log
sudo grep "POST\|PUT\|DELETE" /var/log/nginx/access.log

# View Nginx error logs
sudo tail -f /var/log/nginx/error.log
sudo grep -i error /var/log/nginx/error.log

# Check Nginx status
sudo systemctl status nginx

# View Nginx config
sudo cat /etc/nginx/sites-enabled/ddos
```

---

## Debug Application Issues (From SSH)

```bash
# Check if Python venv is working
source /home/ddos/venv/bin/activate
python3 -c "import fastapi; print(fastapi.__version__)"

# Test app directly (without Nginx)
cd /home/ddos/app
/home/ddos/venv/bin/python3 -c "from main import app; print('App loaded OK')"

# Run uvicorn manually (in foreground)
cd /home/ddos/app
/home/ddos/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# Check file permissions
ls -la /home/ddos/
ls -la /home/ddos/app/
ls -la /home/ddos/venv/

# Check user
whoami
id ddos
```

---

## View Application Code (From SSH)

```bash
# View the FastAPI app
cat /home/ddos/app/main.py

# View systemd service file
sudo cat /etc/systemd/system/ddos-gateway.service

# View Nginx config
sudo cat /etc/nginx/sites-available/ddos

# View user-data initialization log
sudo cat /var/log/user-data.log
```

---

## Scaling Commands

```powershell
# Launch additional gateway instance
aws ec2 run-instances `
  --image-id ami-0c55b159cbfafe1f0 `
  --instance-type t3.micro `
  --key-name ddos-key `
  --security-group-ids $GW_SG_ID `
  --subnet-id $SUBNET1_ID `
  --user-data (Get-Content user-data.sh -Raw) `
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=gateway-3}]'

# Get new instance IP
aws ec2 describe-instances --filters "Name=tag:Name,Values=gateway-3" `
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
```

---

## Cleanup Commands (⚠️ DESTRUCTIVE)

```powershell
# WARNING: These commands DELETE resources

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

# Delete route tables
aws ec2 delete-route-table --route-table-id $RT_ID

# Detach and delete IGW
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID

# Delete VPC (must be done last, after all subnets/gateways deleted)
aws ec2 delete-vpc --vpc-id $VPC_ID

# Delete key pair
aws ec2 delete-key-pair --key-name ddos-key
```

---

## One-Liner Diagnostics

```powershell
# Check all instances are running
aws ec2 describe-instances --query 'Reservations[].Instances[?State.Name==`running`].{ID:InstanceId,IP:PublicIpAddress,Name:Tags[?Key==`Name`].Value|[0]}' --output table

# Find instances by VPC
aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query 'Reservations[].Instances[].InstanceId' --output text

# Count running instances
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" --query 'length(Reservations[].Instances[])' --output text

# Get total cost estimate (EC2 only, t3.micro)
# t3.micro: $0.0104 per hour
# 2 instances 24/7 = ~$15/month
Write-Host "Estimated monthly cost for 2 t3.micro instances: $((0.0104 * 24 * 30 * 2))"
```

---

## Backup Commands

```powershell
# Create AMI image from running instance (for backup)
aws ec2 create-image `
  --instance-id $INSTANCE1_ID `
  --name "ddos-gateway-backup-$(Get-Date -Format 'yyyy-MM-dd')" `
  --description "Backup of working gateway instance"

# List available images
aws ec2 describe-images --owners self --query 'Images[].{ID:ImageId,Name:Name,Created:CreationDate}' --output table
```

---

## Cost Monitoring

```powershell
# Estimate daily cost (t3.micro = $0.0104/hour)
$hourly_cost = 0.0104
$daily_cost = $hourly_cost * 24 * 2  # 2 instances
$monthly_cost = $daily_cost * 30

Write-Host "Daily cost: `$$([math]::Round($daily_cost, 2))"
Write-Host "Monthly cost: `$$([math]::Round($monthly_cost, 2))"

# Check CloudWatch for actual usage
aws cloudwatch get-metric-statistics `
  --namespace AWS/EC2 `
  --metric-name CPUUtilization `
  --dimensions Name=InstanceId,Value=$INSTANCE1_ID `
  --start-time (Get-Date).AddHours(-1).ToUniversalTime().ToString('o') `
  --end-time (Get-Date).ToUniversalTime().ToString('o') `
  --period 300 `
  --statistics Average
```

---

## Pro Tips

1. **Save IDs to a file** for future reference:
```powershell
@{
    VPC_ID = $VPC_ID
    INSTANCE1_ID = $INSTANCE1_ID
    INSTANCE2_ID = $INSTANCE2_ID
} | ConvertTo-Json | Out-File aws-ids.json
```

2. **Set up SSH config** for easier access:
```
# ~/.ssh/config
Host gateway1
    HostName $IP1
    User ubuntu
    IdentityFile ~/ddos-key.pem

# Then: ssh gateway1
```

3. **Monitor in real-time**:
```bash
watch -n 1 'curl -s http://localhost/health'
```

4. **Create snapshots before testing**:
```powershell
# After initial successful deployment, create AMI
aws ec2 create-image --instance-id $INSTANCE1_ID --name "ddos-gateway-working" --no-reboot
```

5. **Test changes safely**:
```bash
# Launch test instance from saved AMI before deploying to production
```

---

For detailed information, refer to:
- `AWS_MANUAL_SETUP_INSTRUCTIONS.md` - Step-by-step console guide
- `AWS_CLI_DEPLOYMENT_GUIDE.md` - Automated deployment script
- `AWS_DEPLOYMENT_VERIFICATION.md` - Comprehensive verification checklist
