# RAGFlow Production Docker Compose Setup

This repository contains a comprehensive, production-ready Docker Compose configuration for RAGFlow, including all required services, monitoring, security, and operational best practices.

## 🏗️ Architecture Overview

The production setup includes:

- **RAGFlow Application**: Main application server with web interface and API
- **MySQL 8.0**: Primary database for metadata and application data
- **Elasticsearch 8.11**: Vector database for document search and embeddings
- **Redis (Valkey)**: Caching and session storage
- **MinIO**: Object storage for files and documents
- **Nginx**: Reverse proxy with SSL termination and load balancing
- **Monitoring Stack**: Prometheus, Grafana, and various exporters (optional)
- **Backup System**: Automated backup scripts and procedures

## 📋 Prerequisites

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 4 cores | 8+ cores |
| **RAM** | 16 GB | 32+ GB |
| **Disk** | 50 GB | 100+ GB SSD |
| **Network** | 1 Gbps | 10 Gbps |

### Software Requirements

- **Docker**: >= 24.0.0
- **Docker Compose**: >= v2.26.1
- **Operating System**: Linux (Ubuntu 22.04+ recommended)
- **SSL Certificates**: Valid certificates for production domains

### Optional Requirements

- **gVisor**: For sandbox code execution functionality
- **Monitoring Tools**: For comprehensive observability

## 🚀 Quick Start

### 1. Clone and Setup

```bash
# Clone the repository
git clone <repository-url>
cd ragflow-production

# Run the setup script
chmod +x scripts/setup-production.sh
./scripts/setup-production.sh
```

### 2. Configure Environment

```bash
# Copy and customize the environment file
cp .env.production .env

# Edit the environment file with your specific settings
nano .env
```

**Important**: Change all default passwords and API keys!

### 3. Configure SSL Certificates

```bash
# Replace self-signed certificates with your own
cp your-certificate.crt ssl/ragflow.crt
cp your-private-key.key ssl/ragflow.key
cp your-ca-bundle.crt ssl/ragflow-ca.crt
```

### 4. Start Services

```bash
# Start all services
docker-compose -f docker-compose.production.yml up -d

# Check service status
docker-compose -f docker-compose.production.yml ps

# View logs
docker-compose -f docker-compose.production.yml logs -f
```

### 5. Verify Installation

```bash
# Check application health
curl -k https://your-domain.com/health

# Check individual services
curl http://localhost:1200/_cluster/health  # Elasticsearch
curl http://localhost:6379  # Redis (requires auth)
curl http://localhost:9000/minio/health/live  # MinIO
```

## 📁 Directory Structure

```
ragflow-production/
├── docker-compose.production.yml    # Main Docker Compose file
├── .env.production                  # Environment template
├── .env                            # Your environment file (created)
├── nginx/
│   ├── ragflow.production.conf     # Nginx configuration
│   └── ssl/                        # SSL certificates
├── mysql/
│   └── conf.d/ragflow.cnf         # MySQL configuration
├── redis/
│   └── redis.conf                 # Redis configuration
├── elasticsearch/
│   └── config/elasticsearch.yml   # Elasticsearch configuration
├── monitoring/
│   ├── prometheus.yml             # Prometheus configuration
│   └── grafana/                   # Grafana dashboards
├── scripts/
│   ├── setup-production.sh       # Setup script
│   └── backup.sh                 # Backup script
├── volumes/                       # Persistent data (created)
├── backups/                       # Backup storage (created)
└── logs/                         # Application logs (created)
```

## ⚙️ Configuration

### Environment Variables

Key environment variables to configure:

```bash
# Application
RAGFLOW_IMAGE=infiniflow/ragflow:v0.19.1
SVR_HTTP_PORT=9380
TIMEZONE=UTC

# Database passwords (change these!)
MYSQL_PASSWORD=your_secure_mysql_password
REDIS_PASSWORD=your_secure_redis_password
MINIO_PASSWORD=your_secure_minio_password
ELASTIC_PASSWORD=your_secure_elasticsearch_password

# External services
OPENAI_API_KEY=your_openai_api_key
ANTHROPIC_API_KEY=your_anthropic_api_key

# Security
JWT_SECRET=your_jwt_secret_key
REGISTER_ENABLED=0  # Disable registration in production
```

### Service Configuration

Each service has its own configuration file:

- **Nginx**: `nginx/ragflow.production.conf`
- **MySQL**: `mysql/conf.d/ragflow.cnf`
- **Redis**: `redis/redis.conf`
- **Elasticsearch**: `elasticsearch/config/elasticsearch.yml`

### Resource Limits

Default resource limits are set for production use:

```yaml
# RAGFlow application
resources:
  limits:
    cpus: '4.0'
    memory: 8G
  reservations:
    cpus: '2.0'
    memory: 4G
```

Adjust these based on your hardware and usage patterns.

## 🔒 Security

### SSL/TLS Configuration

1. **Obtain SSL certificates** from a trusted CA
2. **Place certificates** in the `ssl/` directory
3. **Update Nginx configuration** with your domain name
4. **Enable HTTPS redirect** in Nginx

### Network Security

- All services run in an isolated Docker network
- Only necessary ports are exposed
- Rate limiting is configured in Nginx
- Security headers are set

### Authentication

- Strong passwords are generated automatically
- API keys should be rotated regularly
- Consider implementing OAuth/SSO for user authentication

### Firewall Configuration

```bash
# Allow only necessary ports
sudo ufw allow 80/tcp    # HTTP (redirects to HTTPS)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 22/tcp    # SSH (restrict to specific IPs)

# Block all other ports
sudo ufw default deny incoming
sudo ufw enable
```

## 📊 Monitoring

### Prometheus Metrics

The setup includes comprehensive monitoring:

- Application metrics from RAGFlow
- System metrics from Node Exporter
- Container metrics from cAdvisor
- Database metrics from various exporters

### Grafana Dashboards

Pre-configured dashboards for:

- RAGFlow application performance
- Database performance (MySQL, Elasticsearch, Redis)
- System resource utilization
- Network and storage metrics

### Health Checks

All services include health checks:

```bash
# Check all service health
docker-compose -f docker-compose.production.yml ps

# Individual health checks
curl https://your-domain.com/health
curl http://localhost:1200/_cluster/health
```

## 💾 Backup and Recovery

### Automated Backups

The setup includes automated backup scripts:

```bash
# Run manual backup
./scripts/backup.sh

# Schedule automated backups (crontab)
0 2 * * * /path/to/ragflow-production/scripts/backup.sh
```

### Backup Components

- **MySQL database**: Full database dump
- **Elasticsearch indices**: Snapshot repository
- **MinIO data**: Object storage backup
- **RAGFlow data**: Application data and models
- **Configuration files**: All configuration backups

### Recovery Procedures

1. **Stop services**: `docker-compose down`
2. **Restore data**: From backup location
3. **Start services**: `docker-compose up -d`
4. **Verify integrity**: Check all services

## 🔧 Maintenance

### Regular Tasks

- **Update Docker images**: Monthly security updates
- **Rotate passwords**: Quarterly password rotation
- **Clean up logs**: Weekly log rotation
- **Monitor disk space**: Daily space monitoring
- **Review security**: Monthly security audits

### Scaling

#### Horizontal Scaling

```yaml
# Add more RAGFlow instances
ragflow-2:
  image: ${RAGFLOW_IMAGE}
  # ... same configuration as ragflow

ragflow-3:
  image: ${RAGFLOW_IMAGE}
  # ... same configuration as ragflow
```

#### Vertical Scaling

Adjust resource limits in the Docker Compose file:

```yaml
deploy:
  resources:
    limits:
      cpus: '8.0'      # Increase CPU
      memory: 16G      # Increase memory
```

## 🐛 Troubleshooting

### Common Issues

1. **Service won't start**
   ```bash
   # Check logs
   docker-compose logs service-name
   
   # Check resource usage
   docker stats
   ```

2. **Database connection errors**
   ```bash
   # Verify database is running
   docker-compose ps mysql
   
   # Check database logs
   docker-compose logs mysql
   ```

3. **Elasticsearch issues**
   ```bash
   # Check cluster health
   curl http://localhost:1200/_cluster/health
   
   # Check node stats
   curl http://localhost:1200/_nodes/stats
   ```

### Performance Tuning

1. **Increase JVM heap** for Elasticsearch
2. **Tune MySQL buffer pool** size
3. **Adjust Redis memory** limits
4. **Optimize Nginx** worker processes

### Log Analysis

```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f ragflow

# Search logs for errors
docker-compose logs | grep ERROR
```

## 📞 Support

### Documentation

- [RAGFlow Official Documentation](https://ragflow.io/docs)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Production Best Practices](https://docs.docker.com/compose/production/)

### Community

- [RAGFlow GitHub Issues](https://github.com/infiniflow/ragflow/issues)
- [RAGFlow Community Forum](https://github.com/infiniflow/ragflow/discussions)

### Professional Support

For enterprise support and consulting:
- Contact: [support@ragflow.io](mailto:support@ragflow.io)
- Documentation: [Enterprise Support](https://ragflow.io/enterprise)

## 📄 License

This configuration is provided under the same license as RAGFlow.
See the [LICENSE](LICENSE) file for details.

---

**⚠️ Important**: This is a production configuration. Always test in a staging environment before deploying to production. Ensure you have proper backups and monitoring in place.
