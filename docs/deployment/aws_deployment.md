---
sidebar_position: 3
slug: /aws_deployment
---

# AWS Cloud Deployment Guide

Complete guide for deploying RAGFlow on Amazon Web Services using EKS, ECS, and EC2 with managed AWS services.

---

import TOCInline from '@theme/TOCInline';

<TOCInline toc={toc} />

---

## Overview

This guide covers three deployment approaches on AWS:

- **EKS Deployment**: Kubernetes-based deployment using Amazon EKS
- **ECS Deployment**: Container-based deployment using Amazon ECS
- **EC2 Deployment**: Virtual machine deployment using Amazon EC2

Each approach integrates with managed AWS services for production-ready deployments.

## Prerequisites

### AWS Account Setup

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS credentials
aws configure
# Enter your Access Key ID, Secret Access Key, Region, and Output format

# Verify configuration
aws sts get-caller-identity
```

### Required Tools

```bash
# Install eksctl (for EKS)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Terraform (optional, for IaC)
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

## EKS Deployment

### 1. Create EKS Cluster

```bash
# Create cluster configuration
cat > ragflow-cluster.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ragflow-cluster
  region: us-west-2
  version: "1.28"

nodeGroups:
  - name: ragflow-nodes
    instanceType: m5.xlarge
    desiredCapacity: 3
    minSize: 2
    maxSize: 6
    volumeSize: 100
    volumeType: gp3
    ssh:
      allow: true
    iam:
      withAddonPolicies:
        ebs: true
        efs: true
        albIngress: true
        cloudWatch: true

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver

cloudWatch:
  clusterLogging:
    enable: ["api", "audit", "authenticator", "controllerManager", "scheduler"]
EOF

# Create the cluster
eksctl create cluster -f ragflow-cluster.yaml
```

### 2. Configure AWS Load Balancer Controller

```bash
# Create IAM role for AWS Load Balancer Controller
eksctl create iamserviceaccount \
  --cluster=ragflow-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name=AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
  --approve

# Install AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=ragflow-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 3. Create AWS Managed Services

```bash
# Create RDS MySQL instance
aws rds create-db-instance \
  --db-instance-identifier ragflow-mysql \
  --db-instance-class db.t3.medium \
  --engine mysql \
  --engine-version 8.0.35 \
  --master-username ragflow \
  --master-user-password YourSecurePassword123! \
  --allocated-storage 100 \
  --storage-type gp3 \
  --vpc-security-group-ids sg-xxxxxxxxx \
  --db-subnet-group-name default \
  --backup-retention-period 7 \
  --multi-az \
  --storage-encrypted

# Create ElastiCache Redis cluster
aws elasticache create-replication-group \
  --replication-group-id ragflow-redis \
  --description "RAGFlow Redis Cluster" \
  --node-type cache.t3.medium \
  --engine redis \
  --engine-version 7.0 \
  --num-cache-clusters 2 \
  --cache-parameter-group-name default.redis7 \
  --security-group-ids sg-xxxxxxxxx \
  --subnet-group-name default \
  --at-rest-encryption-enabled \
  --transit-encryption-enabled

# Create S3 bucket for object storage
aws s3 mb s3://ragflow-storage-$(date +%s) --region us-west-2
```

### 4. Deploy RAGFlow on EKS

Create AWS-specific values file:

```yaml
# aws-eks-values.yaml
env:
  DOC_ENGINE: infinity
  TIMEZONE: "UTC"
  
  # External MySQL (RDS)
  MYSQL_HOST: "ragflow-mysql.xxxxxxxxx.us-west-2.rds.amazonaws.com"
  MYSQL_PORT: "3306"
  MYSQL_PASSWORD: "YourSecurePassword123!"
  MYSQL_DBNAME: "ragflow"
  
  # External Redis (ElastiCache)
  REDIS_HOST: "ragflow-redis.xxxxxx.cache.amazonaws.com"
  REDIS_PORT: "6379"
  REDIS_PASSWORD: ""  # No password for ElastiCache without auth
  
  # S3 Configuration
  MINIO_HOST: "s3.us-west-2.amazonaws.com"
  MINIO_ROOT_USER: "AKIAIOSFODNN7EXAMPLE"
  MINIO_PASSWORD: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  
  RAGFLOW_IMAGE: infiniflow/ragflow:v0.19.1

ragflow:
  deployment:
    replicas: 3
    resources:
      requests:
        cpu: "2"
        memory: "4Gi"
      limits:
        cpu: "4"
        memory: "8Gi"
  service:
    type: ClusterIP

# Disable internal services (using AWS managed services)
mysql:
  enabled: false
redis:
  enabled: false
minio:
  enabled: false

# Configure ALB Ingress
ingress:
  enabled: true
  className: "alb"
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:123456789012:certificate/xxxxxxxx
    alb.ingress.kubernetes.io/ssl-redirect: '443'
  hosts:
    - host: ragflow.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - ragflow.yourdomain.com
```

Deploy RAGFlow:

```bash
# Clone repository
git clone https://github.com/infiniflow/ragflow.git
cd ragflow/helm

# Create namespace
kubectl create namespace ragflow

# Install RAGFlow
helm install ragflow . -n ragflow -f aws-eks-values.yaml

# Check deployment
kubectl get pods -n ragflow
kubectl get ingress -n ragflow
```

## ECS Deployment

### 1. Create ECS Cluster

```bash
# Create ECS cluster
aws ecs create-cluster \
  --cluster-name ragflow-cluster \
  --capacity-providers EC2 FARGATE \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1

# Create VPC and subnets (if not existing)
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=ragflow-vpc}]'
```

### 2. Create Task Definition

```json
{
  "family": "ragflow-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "2048",
  "memory": "4096",
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::123456789012:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "ragflow",
      "image": "infiniflow/ragflow:v0.19.1",
      "portMappings": [
        {
          "containerPort": 9380,
          "protocol": "tcp"
        },
        {
          "containerPort": 80,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "MYSQL_HOST",
          "value": "ragflow-mysql.xxxxxxxxx.us-west-2.rds.amazonaws.com"
        },
        {
          "name": "MYSQL_PASSWORD",
          "value": "YourSecurePassword123!"
        },
        {
          "name": "REDIS_HOST",
          "value": "ragflow-redis.xxxxxx.cache.amazonaws.com"
        },
        {
          "name": "MINIO_HOST",
          "value": "s3.us-west-2.amazonaws.com"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/ragflow",
          "awslogs-region": "us-west-2",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:9380/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

### 3. Create ECS Service

```bash
# Register task definition
aws ecs register-task-definition --cli-input-json file://ragflow-task-definition.json

# Create service
aws ecs create-service \
  --cluster ragflow-cluster \
  --service-name ragflow-service \
  --task-definition ragflow-task:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxxxxxxxx,subnet-yyyyyyyyy],securityGroups=[sg-xxxxxxxxx],assignPublicIp=ENABLED}" \
  --load-balancers targetGroupArn=arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/ragflow-tg/xxxxxxxxx,containerName=ragflow,containerPort=80
```

## EC2 Deployment

### 1. Launch EC2 Instance

```bash
# Create security group
aws ec2 create-security-group \
  --group-name ragflow-sg \
  --description "Security group for RAGFlow"

# Add inbound rules
aws ec2 authorize-security-group-ingress \
  --group-name ragflow-sg \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-name ragflow-sg \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-name ragflow-sg \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# Launch instance
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --count 1 \
  --instance-type m5.xlarge \
  --key-name your-key-pair \
  --security-groups ragflow-sg \
  --block-device-mappings DeviceName=/dev/xvda,Ebs='{VolumeSize=100,VolumeType=gp3}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ragflow-server}]'
```

### 2. Configure EC2 Instance

```bash
# SSH into instance
ssh -i your-key-pair.pem ec2-user@your-instance-ip

# Install Docker
sudo yum update -y
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Clone RAGFlow
git clone https://github.com/infiniflow/ragflow.git
cd ragflow/docker
```

### 3. Configure for AWS Services

Create AWS-specific environment file:

```bash
# Create .env file for AWS services
cat > .env << EOF
# RAGFlow Configuration
RAGFLOW_IMAGE=infiniflow/ragflow:v0.19.1
SVR_HTTP_PORT=9380
TIMEZONE=UTC

# External MySQL (RDS)
MYSQL_HOST=ragflow-mysql.xxxxxxxxx.us-west-2.rds.amazonaws.com
MYSQL_PORT=3306
MYSQL_PASSWORD=YourSecurePassword123!
MYSQL_DBNAME=ragflow

# External Redis (ElastiCache)
REDIS_HOST=ragflow-redis.xxxxxx.cache.amazonaws.com
REDIS_PORT=6379
REDIS_PASSWORD=

# S3 Configuration
MINIO_HOST=s3.us-west-2.amazonaws.com
MINIO_ROOT_USER=AKIAIOSFODNN7EXAMPLE
MINIO_PASSWORD=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# Disable internal services
MYSQL_ENABLED=false
REDIS_ENABLED=false
MINIO_ENABLED=false
EOF
```

Create custom Docker Compose file:

```yaml
# docker-compose-aws.yml
version: '3.8'
services:
  ragflow:
    image: ${RAGFLOW_IMAGE}
    container_name: ragflow-server
    ports:
      - "${SVR_HTTP_PORT}:9380"
      - "80:80"
      - "443:443"
    environment:
      - TZ=${TIMEZONE}
      - MYSQL_HOST=${MYSQL_HOST}
      - MYSQL_PORT=${MYSQL_PORT}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - MYSQL_DBNAME=${MYSQL_DBNAME}
      - REDIS_HOST=${REDIS_HOST}
      - REDIS_PORT=${REDIS_PORT}
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - MINIO_HOST=${MINIO_HOST}
      - MINIO_ROOT_USER=${MINIO_ROOT_USER}
      - MINIO_PASSWORD=${MINIO_PASSWORD}
    volumes:
      - ./ragflow-logs:/ragflow/logs
      - ./nginx:/etc/nginx/conf.d
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9380/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  default:
    driver: bridge
```

### 4. Deploy RAGFlow

```bash
# Start RAGFlow
docker-compose -f docker-compose-aws.yml up -d

# Check status
docker-compose -f docker-compose-aws.yml ps

# View logs
docker-compose -f docker-compose-aws.yml logs -f
```

## Infrastructure as Code (Terraform)

### Complete AWS Infrastructure

```hcl
# main.tf
provider "aws" {
  region = var.aws_region
}

# VPC and Networking
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  
  name = "ragflow-vpc"
  cidr = "10.0.0.0/16"
  
  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  enable_nat_gateway = true
  enable_vpn_gateway = true
  
  tags = {
    Environment = var.environment
    Project     = "ragflow"
  }
}

# RDS MySQL
resource "aws_db_instance" "ragflow_mysql" {
  identifier = "ragflow-mysql"
  
  engine         = "mysql"
  engine_version = "8.0.35"
  instance_class = "db.t3.medium"
  
  allocated_storage     = 100
  max_allocated_storage = 1000
  storage_type         = "gp3"
  storage_encrypted    = true
  
  db_name  = "ragflow"
  username = "ragflow"
  password = var.mysql_password
  
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.ragflow.name
  
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  multi_az               = true
  publicly_accessible    = false
  
  skip_final_snapshot = true
  
  tags = {
    Name        = "ragflow-mysql"
    Environment = var.environment
  }
}

# ElastiCache Redis
resource "aws_elasticache_replication_group" "ragflow_redis" {
  replication_group_id       = "ragflow-redis"
  description                = "RAGFlow Redis Cluster"
  
  node_type                  = "cache.t3.medium"
  port                       = 6379
  parameter_group_name       = "default.redis7"
  
  num_cache_clusters         = 2
  
  subnet_group_name          = aws_elasticache_subnet_group.ragflow.name
  security_group_ids         = [aws_security_group.elasticache.id]
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  
  tags = {
    Name        = "ragflow-redis"
    Environment = var.environment
  }
}

# S3 Bucket
resource "aws_s3_bucket" "ragflow_storage" {
  bucket = "ragflow-storage-${random_id.bucket_suffix.hex}"
  
  tags = {
    Name        = "ragflow-storage"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "ragflow_storage" {
  bucket = aws_s3_bucket.ragflow_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ragflow_storage" {
  bucket = aws_s3_bucket.ragflow_storage.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# EKS Cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  
  cluster_name    = "ragflow-cluster"
  cluster_version = "1.28"
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  node_groups = {
    ragflow_nodes = {
      desired_capacity = 3
      max_capacity     = 6
      min_capacity     = 2
      
      instance_types = ["m5.xlarge"]
      
      k8s_labels = {
        Environment = var.environment
        Application = "ragflow"
      }
    }
  }
  
  tags = {
    Environment = var.environment
    Project     = "ragflow"
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "mysql_password" {
  description = "MySQL password"
  type        = string
  sensitive   = true
}

# Random ID for unique bucket naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Outputs
output "rds_endpoint" {
  value = aws_db_instance.ragflow_mysql.endpoint
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.ragflow_redis.primary_endpoint_address
}

output "s3_bucket" {
  value = aws_s3_bucket.ragflow_storage.bucket
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
```

Deploy with Terraform:

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var="mysql_password=YourSecurePassword123!"

# Apply configuration
terraform apply -var="mysql_password=YourSecurePassword123!"
```

## Monitoring and Logging

### CloudWatch Integration

```yaml
# cloudwatch-values.yaml
ragflow:
  deployment:
    annotations:
      fluentbit.io/parser: "json"
    env:
      - name: AWS_REGION
        value: "us-west-2"
      - name: AWS_DEFAULT_REGION
        value: "us-west-2"

# Install Fluent Bit for log forwarding
helm repo add fluent https://fluent.github.io/helm-charts
helm install fluent-bit fluent/fluent-bit \
  --set cloudWatch.enabled=true \
  --set cloudWatch.region=us-west-2 \
  --set cloudWatch.logGroupName=/aws/eks/ragflow/logs
```

### Application Load Balancer Monitoring

```bash
# Enable ALB access logs
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/ragflow-alb/xxxxxxxxx \
  --attributes Key=access_logs.s3.enabled,Value=true Key=access_logs.s3.bucket,Value=ragflow-alb-logs
```

## Security Best Practices

### IAM Roles and Policies

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::ragflow-storage-*",
        "arn:aws:s3:::ragflow-storage-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "elasticache:DescribeReplicationGroups"
      ],
      "Resource": "*"
    }
  ]
}
```

### VPC Security Groups

```bash
# RDS Security Group
aws ec2 create-security-group \
  --group-name ragflow-rds-sg \
  --description "Security group for RAGFlow RDS"

aws ec2 authorize-security-group-ingress \
  --group-name ragflow-rds-sg \
  --protocol tcp \
  --port 3306 \
  --source-group ragflow-app-sg

# ElastiCache Security Group
aws ec2 create-security-group \
  --group-name ragflow-redis-sg \
  --description "Security group for RAGFlow Redis"

aws ec2 authorize-security-group-ingress \
  --group-name ragflow-redis-sg \
  --protocol tcp \
  --port 6379 \
  --source-group ragflow-app-sg
```

## Cost Optimization

### Reserved Instances

```bash
# Purchase RDS Reserved Instance
aws rds purchase-reserved-db-instances-offering \
  --reserved-db-instances-offering-id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --reserved-db-instance-id ragflow-mysql-ri

# Purchase ElastiCache Reserved Nodes
aws elasticache purchase-reserved-cache-nodes-offering \
  --reserved-cache-nodes-offering-id xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --reserved-cache-node-id ragflow-redis-ri \
  --cache-node-count 2
```

### Auto Scaling

```yaml
# cluster-autoscaler-values.yaml
autoDiscovery:
  clusterName: ragflow-cluster
  enabled: true

rbac:
  create: true
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/cluster-autoscaler-role

nodeSelector:
  kubernetes.io/os: linux
```

## Disaster Recovery

### Multi-Region Setup

```bash
# Create read replica in different region
aws rds create-db-instance-read-replica \
  --db-instance-identifier ragflow-mysql-replica \
  --source-db-instance-identifier ragflow-mysql \
  --db-instance-class db.t3.medium \
  --destination-region us-east-1

# Cross-region S3 replication
aws s3api put-bucket-replication \
  --bucket ragflow-storage-primary \
  --replication-configuration file://replication-config.json
```

## Troubleshooting

### Common AWS Issues

#### EKS Node Group Issues

```bash
# Check node group status
aws eks describe-nodegroup \
  --cluster-name ragflow-cluster \
  --nodegroup-name ragflow-nodes

# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names eks-ragflow-nodes-xxxxxxxxx
```

#### RDS Connection Issues

```bash
# Test RDS connectivity
aws rds describe-db-instances \
  --db-instance-identifier ragflow-mysql

# Check security groups
aws ec2 describe-security-groups \
  --group-ids sg-xxxxxxxxx
```

#### ECS Service Issues

```bash
# Check service status
aws ecs describe-services \
  --cluster ragflow-cluster \
  --services ragflow-service

# Check task definition
aws ecs describe-task-definition \
  --task-definition ragflow-task:1
```

## Next Steps

After successful AWS deployment:

1. [Configure monitoring with CloudWatch](../monitoring/cloudwatch_setup.md)
2. [Set up backup and disaster recovery](../backup/aws_backup.md)
3. [Implement CI/CD with CodePipeline](../cicd/aws_codepipeline.md)
4. [Configure auto-scaling policies](../scaling/aws_autoscaling.md)

For additional support, visit our [community channels](https://github.com/orgs/infiniflow/discussions) or check the [FAQ](../../faq.mdx).
