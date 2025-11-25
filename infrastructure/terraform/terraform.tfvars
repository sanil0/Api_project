# Terraform variables configuration for Pre-LB Architecture

# AWS Configuration
aws_region   = "us-east-1"
environment  = "production"
project_name = "hybrid-ddos-detection"

# Network Configuration
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]
ssh_cidr_blocks      = ["0.0.0.0/0"]

# EC2 Configuration
gateway_instance_type   = "t3.micro"
webserver_instance_type = "t3.micro"
key_pair_name           = "hybrid-ddos-detection-key"

# Gateway ASG Configuration
gateway_min_instances     = 2
gateway_max_instances     = 4
gateway_desired_instances = 2

# Webserver ASG Configuration
webserver_min_instances     = 2
webserver_max_instances     = 10
webserver_desired_instances = 3
