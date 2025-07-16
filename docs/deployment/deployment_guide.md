---
sidebar_position: 1
slug: /deployment_guide
---

# RAGFlow Deployment Guide

Comprehensive instructions for deploying RAGFlow in three different environments: local development, Docker deployment, and staging environment.

---

import TOCInline from '@theme/TOCInline';

<TOCInline toc={toc} />

---

## Overview

This guide covers deploying RAGFlow in three scenarios:

- **Local Development**: Setting up RAGFlow from source code for development
- **Docker Deployment**: Using pre-built or custom Docker images
- **Staging Environment**: Production-ready deployment with optimization

Each section includes system requirements, prerequisites, configuration steps, and troubleshooting tips.

## 1. Local Development Environment

### System Requirements

| Component | Requirement |
|-----------|-------------|
| **CPU** | ≥ 4 cores (x86) |
| **RAM** | ≥ 16 GB |
| **Disk** | ≥ 50 GB |
| **Docker** | ≥ 24.0.0 & Docker Compose ≥ v2.26.1 |
| **Python** | 3.10 |
| **OS** | Linux, macOS, or Windows with WSL2 |

### Prerequisites Installation

```bash
# Install uv and pre-commit
pipx install uv pre-commit

# Optional: Set UV index for faster downloads (China users)
export UV_INDEX=https://mirrors.aliyun.com/pypi/simple

# Optional: Set HuggingFace mirror if needed
export HF_ENDPOINT=https://hf-mirror.com
```

### Step-by-Step Setup

#### 1. Clone Repository and Install Dependencies

```bash
# Clone the repository
git clone https://github.com/infiniflow/ragflow.git
cd ragflow/

# Install Python dependencies
uv sync --python 3.10 --all-extras
uv run download_deps.py
pre-commit install
```

#### 2. Launch Third-Party Services

```bash
# Start base services (MinIO, Elasticsearch, Redis, MySQL)
docker compose -f docker/docker-compose-base.yml up -d
```

#### 3. Configure Host Resolution

Add the following to your `/etc/hosts` file:

```
127.0.0.1       es01 infinity mysql minio redis sandbox-executor-manager
```

#### 4. Update Service Configuration

Modify `docker/service_conf.yaml.template` to update ports:

```yaml
# Update MySQL port to 5455 and Elasticsearch port to 1200
mysql:
  port: 5455
  # ... other config

elasticsearch:
  port: 1200
  # ... other config
```

#### 5. Launch RAGFlow Backend

```bash
# Comment out nginx in docker/entrypoint.sh first
# Then activate virtual environment
source .venv/bin/activate
export PYTHONPATH=$(pwd)

# Start task executor
JEMALLOC_PATH=$(pkg-config --variable=libdir jemalloc)/libjemalloc.so
LD_PRELOAD=$JEMALLOC_PATH python rag/svr/task_executor.py 1 &

# Start API server
python api/ragflow_server.py
```

### Development Commands

```bash
# Start services
docker compose -f docker/docker-compose-base.yml up -d

# Stop services
docker compose -f docker/docker-compose-base.yml down

# View logs
docker compose -f docker/docker-compose-base.yml logs -f

# Restart specific service
docker compose -f docker/docker-compose-base.yml restart mysql
```

## 2. Docker Deployment

### System Requirements

| Component | Requirement |
|-----------|-------------|
| **CPU** | ≥ 4 cores |
| **RAM** | ≥ 16 GB |
| **Disk** | ≥ 50 GB (slim) / ≥ 60 GB (full) |
| **Docker** | ≥ 24.0.0 & Docker Compose ≥ v2.26.1 |

### Docker Image Options

| Image Type | Size | Description |
|------------|------|-------------|
| `infiniflow/ragflow:v0.19.1-slim` | ~2 GB | Without embedding models |
| `infiniflow/ragflow:v0.19.1` | ~9 GB | With embedding models |
| `infiniflow/ragflow:nightly-slim` | ~2 GB | Latest development (slim) |
| `infiniflow/ragflow:nightly` | ~9 GB | Latest development (full) |

### Quick Start with Pre-built Images

#### 1. Download and Setup

```bash
# Clone repository
git clone https://github.com/infiniflow/ragflow.git
cd ragflow/docker

# Start with CPU (slim version)
docker compose -f docker-compose.yml up -d

# OR start with GPU acceleration
docker compose -f docker-compose-gpu.yml up -d
```

#### 2. Configure Different Versions

Edit `docker/.env` file:

```bash
# For slim version (default)
RAGFLOW_IMAGE=infiniflow/ragflow:v0.19.1-slim

# For full version with embedding models
RAGFLOW_IMAGE=infiniflow/ragflow:v0.19.1

# For nightly builds
RAGFLOW_IMAGE=infiniflow/ragflow:nightly-slim
```

### Building Custom Docker Images

#### Build Slim Image (without embedding models)

```bash
git clone https://github.com/infiniflow/ragflow.git
cd ragflow/
uv run download_deps.py
docker build -f Dockerfile.deps -t infiniflow/ragflow_deps .
docker build --build-arg LIGHTEN=1 -f Dockerfile -t infiniflow/ragflow:nightly-slim .
```

#### Build Full Image (with embedding models)

```bash
git clone https://github.com/infiniflow/ragflow.git
cd ragflow/
uv run download_deps.py
docker build -f Dockerfile.deps -t infiniflow/ragflow_deps .
docker build -f Dockerfile -t infiniflow/ragflow:nightly .
```

### Platform-Specific Deployments

#### ARM64 Platform Support

```bash
# For ARM64 platforms, build custom image
git clone https://github.com/infiniflow/ragflow.git
cd ragflow/

# Update xgboost version in pyproject.toml to 1.6.0
# Ensure unixODBC is properly installed

# Build for ARM64
docker build --platform linux/arm64 --build-arg LIGHTEN=1 -f Dockerfile -t infiniflow/ragflow:arm64-slim .
```

#### macOS Deployment

```bash
# Edit docker/.env file
# Change RAGFLOW_IMAGE to your built image
RAGFLOW_IMAGE=infiniflow/ragflow:nightly-slim

# Launch on macOS
cd docker
docker compose -f docker-compose-macos.yml up -d
```

### Docker Commands Reference

```bash
# Start services
docker compose -f docker-compose.yml up -d

# Stop services
docker compose -f docker-compose.yml down

# Stop and remove volumes (WARNING: deletes data)
docker compose -f docker-compose.yml down -v

# View logs
docker compose -f docker-compose.yml logs -f ragflow

# Restart specific service
docker compose -f docker-compose.yml restart ragflow

# Check service status
docker compose -f docker-compose.yml ps
```

## 3. Staging Environment Deployment

### System Requirements

| Component | Requirement |
|-----------|-------------|
| **CPU** | ≥ 8 cores (recommended) |
| **RAM** | ≥ 32 GB (recommended) |
| **Disk** | ≥ 100 GB SSD |
| **Network** | Stable internet for LLM API calls |
| **Load Balancer** | For high availability |

### Environment Configuration

#### 1. Production Docker Compose

Create a `docker-compose-staging.yml` file:

```yaml
version: '3.8'
services:
  ragflow:
    image: infiniflow/ragflow:v0.19.1
    container_name: ragflow-staging
    restart: unless-stopped
    ports:
      - "9380:9380"
      - "80:80"
      - "443:443"
    environment:
      - TZ=UTC
      - HF_ENDPOINT=${HF_ENDPOINT}
    volumes:
      - ./ragflow-logs:/ragflow/logs
      - ./nginx:/etc/nginx/conf.d
    networks:
      - ragflow-staging
    deploy:
      resources:
        limits:
          memory: 16G
        reservations:
          memory: 8G

networks:
  ragflow-staging:
    driver: bridge
```

#### 2. Environment Variables

Create a `.env` file:

```bash
# Core Configuration
RAGFLOW_IMAGE=infiniflow/ragflow:v0.19.1
TIMEZONE=UTC
SVR_HTTP_PORT=9380

# External Services
HF_ENDPOINT=https://huggingface.co
OPENAI_API_KEY=your_openai_key
ANTHROPIC_API_KEY=your_anthropic_key

# Database Configuration
MYSQL_PASSWORD=secure_password_here
REDIS_PASSWORD=secure_redis_password

# Storage Configuration
MINIO_ACCESS_KEY=staging_access_key
MINIO_SECRET_KEY=secure_secret_key

# Performance Tuning
WORKERS=4
MAX_CONNECTIONS=100
```

### Performance Optimization

#### 1. Resource Allocation

Add to your `docker-compose-staging.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '4.0'
      memory: 16G
    reservations:
      cpus: '2.0'
      memory: 8G
  restart_policy:
    condition: on-failure
    delay: 5s
    max_attempts: 3
```

#### 2. Nginx Configuration

Create `nginx/ragflow-staging.conf`:

```nginx
upstream ragflow_backend {
    server ragflow:9380;
    keepalive 32;
}

server {
    listen 80;
    server_name your-staging-domain.com;
    
    client_max_body_size 100M;
    proxy_read_timeout 300s;
    proxy_connect_timeout 75s;
    
    location / {
        proxy_pass http://ragflow_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### External Service Integration

#### 1. LLM Configuration

Configure in RAGFlow UI or via API:

```yaml
llm_providers:
  openai:
    api_key: "${OPENAI_API_KEY}"
    base_url: "https://api.openai.com/v1"
    models:
      - gpt-4
      - gpt-3.5-turbo
  
  anthropic:
    api_key: "${ANTHROPIC_API_KEY}"
    base_url: "https://api.anthropic.com"
    models:
      - claude-3-sonnet
```

For detailed LLM setup, see [Configure model API key](../models/llm_api_key_setup.md).

#### 2. Local Model Deployment (Ollama)

```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Pull models
ollama pull llama2
ollama pull mistral

# Configure firewall
sudo ufw allow 11434/tcp

# Start Ollama service
systemctl enable ollama
systemctl start ollama
```

For more details, see [Deploy a local LLM](../models/deploy_local_llm.mdx).

### Monitoring and Logging

#### 1. Health Check Script

Create `health_check.sh`:

```bash
#!/bin/bash
# Health check script for RAGFlow staging

RAGFLOW_URL="http://localhost:9380/health"
LOG_FILE="/var/log/ragflow-health.log"

response=$(curl -s -o /dev/null -w "%{http_code}" $RAGFLOW_URL)

if [ $response -eq 200 ]; then
    echo "$(date): RAGFlow is healthy" >> $LOG_FILE
    exit 0
else
    echo "$(date): RAGFlow health check failed (HTTP $response)" >> $LOG_FILE
    exit 1
fi
```

#### 2. Log Rotation

Create `/etc/logrotate.d/ragflow`:

```
/path/to/ragflow-logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        docker compose -f docker-compose-staging.yml restart ragflow
    endscript
}
```

### Deployment Commands

Create `deploy.sh`:

```bash
#!/bin/bash
# Staging deployment script

set -e

echo "Starting RAGFlow staging deployment..."

# Pull latest images
echo "Pulling latest images..."
docker compose -f docker-compose-staging.yml pull

# Stop services gracefully
echo "Stopping services..."
docker compose -f docker-compose-staging.yml down

# Start services
echo "Starting services..."
docker compose -f docker-compose-staging.yml up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 30

# Run health check
echo "Running health check..."
./health_check.sh

echo "Staging deployment completed successfully!"
```

## Troubleshooting Common Issues

### Memory Issues

**Problem**: Out of memory errors during startup or operation

**Solutions**:
- Increase Docker memory limits in Docker Desktop settings
- Add more system RAM (minimum 16GB recommended)
- Use slim image version to reduce memory footprint
- Optimize Docker resource allocation in compose file

### Port Conflicts

**Problem**: Port already in use errors

**Solutions**:
- Check which process is using the port: `lsof -i :9380`
- Update port mappings in `docker/.env`
- Use different ports for development vs staging environments

### ARM64 Compatibility

**Problem**: Docker image not compatible with ARM64 (Apple Silicon)

**Solutions**:
- Build custom image following ARM64 instructions above
- Update `xgboost` version to 1.6.0 in `pyproject.toml`
- Ensure `unixODBC` is properly installed

### HuggingFace Access Issues

**Problem**: Cannot download models from HuggingFace

**Solutions**:
- Set `HF_ENDPOINT` environment variable to mirror site
- For China users: `export HF_ENDPOINT=https://hf-mirror.com`
- Check network connectivity and firewall settings
- Verify HuggingFace API token if using private models

### Database Connection Issues

**Problem**: Cannot connect to MySQL/Elasticsearch

**Solutions**:
- Check host resolution in `/etc/hosts`
- Verify service startup order in Docker Compose
- Check container logs: `docker compose logs mysql`
- Ensure ports are not blocked by firewall

### File Upload Issues

**Problem**: Large file uploads fail or timeout

**Solutions**:
- Increase `client_max_body_size` in Nginx configuration
- Adjust `proxy_read_timeout` and `proxy_connect_timeout`
- Check available disk space
- Verify MinIO storage configuration

### Performance Issues

**Problem**: Slow response times or high resource usage

**Solutions**:
- Monitor resource usage: `docker stats`
- Optimize chunking method for your document types
- Use appropriate embedding models for your use case
- Consider scaling horizontally with multiple instances

## Best Practices

### Security

- Use strong passwords for database and storage services
- Configure SSL/TLS certificates for production deployments
- Regularly update Docker images and dependencies
- Implement proper firewall rules
- Use secrets management for API keys

### Backup and Recovery

- Regularly backup database and MinIO storage
- Test backup restoration procedures
- Document recovery processes
- Consider automated backup solutions

### Monitoring

- Implement comprehensive logging
- Set up alerting for critical issues
- Monitor resource usage trends
- Use health checks for service availability

## Next Steps

After successful deployment:

1. [Configure your API keys](../models/llm_api_key_setup.md) for LLM providers
2. [Create your first knowledge base](../dataset/configure_knowledge_base.md)
3. [Start an AI chat](../chat/start_chat.md) to test functionality
4. Explore [advanced features](../category/guides) and configurations

For additional support, visit our [community channels](https://github.com/orgs/infiniflow/discussions) or check the [FAQ](../../faq.mdx).