# AWS Deployment - Quick Start (5 Minutes)

**TL;DR:** Choose your deployment method below and follow the steps.

---

## 📋 Pre-Check (Do This First)

```powershell
# Verify AWS CLI is installed and configured
aws sts get-caller-identity

# Should return your AWS account info
# If not: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
```

**Also needed:**
- PowerShell 5.1+ (included with Windows 10+)
- AWS credentials configured
- ~15 minutes for deployment
- ~$15/month for running costs (2 t3.micro instances)

---

## 🚀 Choose Your Deployment Method

### Method 1: Automated PowerShell (Fastest - 10 minutes)

**For:** People who want complete automation

```powershell
# Copy all code blocks from this file:
# AWS_CLI_DEPLOYMENT_GUIDE.md

# Run each step in order:
# 1. Create VPC and Network
# 2. Create Security Groups
# 3. Create Key Pair
# 4. Prepare User Data Script
# 5. Launch Gateway Instances
# 6. Verify Deployment

# Then test:
curl http://<PUBLIC_IP>/health
```

**Pros:** Fast, automated, less error-prone  
**Cons:** Requires running PowerShell scripts

### Method 2: Manual AWS Console (Most Visual - 15 minutes)

**For:** People who prefer using the AWS Console UI

```
1. Open AWS_MANUAL_SETUP_INSTRUCTIONS.md
2. Follow each STEP section
3. Use AWS Console for each step
4. Copy-paste user data script when launching
5. Run verification tests
```

**Pros:** See what's being created, understand architecture  
**Cons:** More clicking, slightly longer

### Method 3: Hybrid (Best of Both - 12 minutes)

**For:** People who want clarity + automation

1. Use PowerShell for infrastructure (VPC, subnets, security groups)
2. Manually launch instances in Console
3. Copy the user-data script from `AWS_MANUAL_SETUP_INSTRUCTIONS.md`

---

## ⏱️ Timeline

| Step | Time | What Happens |
|------|------|--------------|
| VPC/Network | 2 min | Create infrastructure |
| Security Groups | 1 min | Configure access rules |
| Key Pair | <1 min | Generate SSH keys |
| User Data Script | <1 min | Prepare app deployment code |
| Launch Instances | 2 min | EC2 instances start |
| **App Initialization** | **5-7 min** | **Wait for venv, pip, systemd to finish** |
| Verification Tests | 2 min | Confirm everything works |
| **Total** | **~15 min** | **Infrastructure ready** |

---

## ✅ Deployment Success Checklist

After deployment, you should be able to:

```bash
# Test from your computer
curl http://GATEWAY_IP_1/health
curl http://GATEWAY_IP_2/health

# Expected response:
# {"status":"ok","uptime_sec":XX,"blocked_ips":0,"total_requests":X,"blocked_requests":0}
```

**Both endpoints respond with JSON?** ✅ **SUCCESS**

---

## 🔧 Common Tasks After Deployment

### Check Instance Status
```powershell
$IP = "54.xxx.xxx.xxx"
curl http://$IP/health
curl http://$IP/stats
```

### SSH into Instance
```bash
ssh -i ddos-key.pem ubuntu@54.xxx.xxx.xxx

# View app logs
sudo journalctl -u ddos-gateway -f

# Check service status
sudo systemctl status ddos-gateway
```

### Restart App
```bash
ssh -i ddos-key.pem ubuntu@54.xxx.xxx.xxx
sudo systemctl restart ddos-gateway
sleep 5
curl http://localhost:8000/health
```

### View Nginx Errors
```bash
ssh -i ddos-key.pem ubuntu@54.xxx.xxx.xxx
sudo tail -f /var/log/nginx/error.log
```

---

## 🐛 Something Not Working?

### "Port 80 returns 502 error"
```bash
# Wait longer (app takes 3-5 minutes to initialize)
# Or SSH and check:
sudo systemctl status ddos-gateway
sudo journalctl -u ddos-gateway -n 20
```

### "Can't connect to port 80"
```bash
# Check security group allows port 80
# SSH and check Nginx:
sudo systemctl status nginx
sudo nginx -t
```

### "Can't SSH into instance"
```bash
# Check:
# 1. Security group allows port 22
# 2. Using correct key: ddos-key.pem
# 3. Using correct user: ubuntu
# 4. Instance has public IP
```

**For detailed troubleshooting:** See `AWS_DEPLOYMENT_VERIFICATION.md`

---

## 📚 Documentation Files

After following Quick Start, refer to:

| File | Use For |
|------|---------|
| `AWS_MANUAL_SETUP_INSTRUCTIONS.md` | Step-by-step Console guide |
| `AWS_CLI_DEPLOYMENT_GUIDE.md` | Copy-paste PowerShell automation |
| `AWS_DEPLOYMENT_VERIFICATION.md` | Verify + troubleshoot |
| `AWS_QUICK_REFERENCE.md` | Common commands reference |
| `AWS_DEPLOYMENT_SOLUTION_SUMMARY.md` | Full overview |

---

## 🎯 What You're Deploying

**Per Instance:**
- 🔧 FastAPI application with ML gateway logic
- 🌐 Nginx reverse proxy (port 80)
- 🚀 Uvicorn ASGI server (port 8000)
- ⚙️ systemd service (auto-restart)
- 📊 Request tracking & blocklist
- 🛡️ Rate limiting (50 req/sec per IP)

**Endpoints:**
- `GET /health` → {"status":"ok", ...}
- `GET /stats` → {"total_requests":X, ...}
- `GET /{path}` → Proxies to backend (port 9000)

---

## 💰 Cost

- **t3.micro:** $0.0104/hour per instance
- **2 instances (24/7):** ~$15/month
- **Data transfer:** Free (same region)
- **Free Tier:** Covers 750 hours/month for first year

---

## 🚨 Important Notes

1. **Wait 3-5 minutes** after launch before testing
   - Python venv setup takes time
   - systemd service needs to initialize

2. **Save your IPs** somewhere safe
   - You'll need them to test the gateway
   - Keep the ddos-key.pem file backed up

3. **Don't forget to terminate** when done testing
   - Instances cost money to run
   - Use AWS Console or CLI to stop/terminate

4. **Update security groups** for production
   - Currently allows SSH from anywhere
   - Restrict to your IP only

---

## 🚀 Next Steps

### Right Now
1. Choose deployment method above
2. Follow the guide step-by-step
3. Test with `curl http://IP/health`
4. Verify with the checklist

### After Deployment
1. Integrate your ML model into the blocklist logic
2. Set up monitoring and alerting
3. Load test to measure throughput
4. Prepare for production scaling

---

## 📞 Quick Support

**Q: Where is the app code?**  
A: `/home/ddos/app/main.py` (created automatically by user-data script)

**Q: How do I modify the app?**  
A: SSH in, edit `/home/ddos/app/main.py`, restart systemd service

**Q: Can I scale to more instances?**  
A: Yes! Launch more instances with same security group/user-data, or use Auto Scaling

**Q: How do I integrate my ML model?**  
A: Edit the `@app.middleware` function to call your model's prediction function

**Q: How do I stop paying?**  
A: Terminate instances in EC2 console (delete VPC after)

---

## 📖 Full Documentation

For complete details, see:
- `AWS_DEPLOYMENT_SOLUTION_SUMMARY.md` - Complete overview
- `AWS_DEPLOYMENT_VERIFICATION.md` - Comprehensive checklist
- `AWS_QUICK_REFERENCE.md` - Command reference

---

## Ready to Deploy?

### 👇 **START HERE:**

**Choose one:**

1. **Fast? Use Automated PowerShell:**  
   → Open `AWS_CLI_DEPLOYMENT_GUIDE.md`

2. **Visual? Use Console Guide:**  
   → Open `AWS_MANUAL_SETUP_INSTRUCTIONS.md`

3. **Need Help? Check Everything:**  
   → Open `AWS_DEPLOYMENT_SOLUTION_SUMMARY.md`

---

**Good luck! Your DDoS gateway will be operational in 15 minutes.** 🚀
