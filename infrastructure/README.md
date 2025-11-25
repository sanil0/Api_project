# Phase 3 Deployment - Hybrid DDoS Detection System

This directory contains the complete AWS infrastructure setup for deploying the hybrid DDoS detection system to production.

## Overview

The infrastructure deploys a scalable, high-availability DDoS detection system using:
- **Stage 1**: KDD21+ model (99.45% accuracy)
- **Stage 2**: CICDDOS2019 + Real Benign model (95.34% accuracy)
- **Ensemble**: Combined voting for final decision

## Architecture

```
Internet → ALB → Auto Scaling Group → EC2 Instances → FastAPI → ML Models
                      ↓
                CloudWatch Logs & Metrics
```

### Components

1. **VPC**: Isolated network with public/private subnets across 2 AZs
2. **Application Load Balancer**: Distributes traffic, health checks
3. **Auto Scaling Group**: 2-10 EC2 instances (t3.medium)
4. **FastAPI Application**: ML inference API with ensemble logic
5. **S3 Bucket**: Model storage and versioning
6. **CloudWatch**: Monitoring, logging, alerting

## Files

- `main.tf` - Complete Terraform infrastructure definition
- `user_data.sh` - EC2 instance initialization script
- `deploy.sh` - Automated deployment script
- `test_deployment.py` - End-to-end testing script
- `terraform.tfvars.example` - Configuration template

## Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **Terraform** >= 1.0 installed
3. **Trained models** available in `../IDDMSCA(copy)/models/`
4. **Python 3.8+** for testing scripts

## Quick Deployment

1. **Clone and navigate**:
   ```bash
   cd infrastructure
   chmod +x deploy.sh
   ```

2. **Deploy infrastructure**:
   ```bash
   ./deploy.sh
   ```

3. **Test deployment**:
   ```bash
   python test_deployment.py --url http://your-load-balancer-url --quick
   ```

## Manual Deployment Steps

### 1. Prepare Configuration

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
```

### 2. Initialize Terraform

```bash
terraform init
terraform plan
terraform apply
```

### 3. Upload Models to S3

```bash
# Get S3 bucket name from Terraform output
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# Upload models
aws s3 cp ../../IDDMSCA(copy)/models/hybrid_stage1_model_v2.pkl s3://$BUCKET_NAME/
aws s3 cp ../../IDDMSCA(copy)/models/hybrid_stage1_scaler_v2.pkl s3://$BUCKET_NAME/
aws s3 cp ../../IDDMSCA(copy)/models/hybrid_stage2_model_v3_real_benign.pkl s3://$BUCKET_NAME/
aws s3 cp ../../IDDMSCA(copy)/models/hybrid_stage2_scaler_v3_real_benign.pkl s3://$BUCKET_NAME/
```

## API Endpoints

After deployment, the system exposes these endpoints:

- **Health Check**: `GET /health`
- **DDoS Detection**: `POST /detect`
- **System Stats**: `GET /stats`
- **Reload Models**: `POST /reload-models`

### Detection Request Format

```json
{
  "source_ip": "192.168.1.100",
  "destination_ip": "10.0.1.50",
  "source_port": 12345,
  "destination_port": 80,
  "protocol": "TCP",
  "packet_size": 1500,
  "request_rate": 10.5,
  "user_agent": "Mozilla/5.0...",
  "referer": "https://example.com",
  "method": "GET",
  "uri": "/api/data",
  "headers": {"Content-Type": "application/json"}
}
```

### Detection Response Format

```json
{
  "is_ddos": false,
  "confidence": 0.85,
  "stage1_prediction": false,
  "stage2_prediction": false,
  "ensemble_decision": "BENIGN",
  "inference_time_ms": 2.34,
  "features_extracted": 109,
  "timestamp": "2025-11-16T16:30:00Z"
}
```

## Performance Targets

- **Latency**: < 50ms (SLA requirement)
- **Throughput**: > 1,000 requests/second
- **Availability**: 99.9% uptime
- **Auto-scaling**: 2-10 instances based on CPU/memory

## Testing

### Quick Health Check

```bash
curl http://your-load-balancer-url/health
```

### Performance Test

```bash
python test_deployment.py \
  --url http://your-load-balancer-url \
  --requests 1000 \
  --concurrent 50
```

### Load Test Example

```bash
# Install dependencies
pip install requests

# Run comprehensive test
python test_deployment.py \
  --url http://your-alb-dns-name \
  --requests 5000 \
  --concurrent 100
```

## Monitoring

### CloudWatch Dashboards

The deployment automatically creates:
- EC2 instance metrics (CPU, memory, disk)
- Application logs (API and supervisor)
- Custom DDoS detection metrics

### Log Groups

- `ddos-detection-api`: FastAPI application logs
- `ddos-detection-supervisor`: Process management logs

### Alarms

- High CPU utilization (>70%) → Scale up
- Low CPU utilization (<20%) → Scale down

## Security

- **VPC**: Isolated network environment
- **Security Groups**: Restricted inbound/outbound rules
- **IAM Roles**: Least privilege access
- **S3**: Server-side encryption enabled
- **SSL/TLS**: Available via ALB (certificate required)

## Cost Optimization

- **t3.medium instances**: Balanced performance/cost
- **Auto-scaling**: Scale down during low traffic
- **S3**: Intelligent tiering for model storage
- **CloudWatch**: Optimized log retention

## Troubleshooting

### Common Issues

1. **Models not loading**:
   ```bash
   # Check S3 bucket access
   aws s3 ls s3://your-bucket-name
   
   # SSH to instance and check logs
   sudo tail -f /opt/ddos-detection/logs/api.log
   ```

2. **High latency**:
   ```bash
   # Check instance metrics
   aws cloudwatch get-metric-statistics \
     --namespace AWS/EC2 \
     --metric-name CPUUtilization
   ```

3. **Health check failing**:
   ```bash
   # Check instance status
   curl http://instance-ip:8000/health
   ```

### Log Locations

- Application: `/opt/ddos-detection/logs/api.log`
- Supervisor: `/opt/ddos-detection/logs/supervisor.log`
- System: `/var/log/syslog`

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

**Warning**: This will delete all infrastructure and data!

## Support

For issues or questions:
1. Check CloudWatch logs
2. Review Terraform outputs
3. Run test script with `--quick` flag
4. Verify model files in S3

## Next Steps

After successful deployment:
1. Configure custom domain and SSL certificate
2. Set up additional monitoring and alerting
3. Implement CI/CD pipeline for model updates
4. Configure backup and disaster recovery