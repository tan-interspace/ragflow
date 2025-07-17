---
sidebar_position: 2
slug: /kubernetes_deployment
---

# Kubernetes Deployment Guide

Complete guide for deploying RAGFlow on Kubernetes using Helm charts with production-ready configurations.

---

import TOCInline from '@theme/TOCInline';

<TOCInline toc={toc} />

---

## Overview

This guide covers deploying RAGFlow on Kubernetes clusters using the official Helm charts. It includes:

- **Prerequisites**: Kubernetes cluster setup and requirements
- **Helm Installation**: Step-by-step deployment process
- **Configuration**: Customizing values for your environment
- **Scaling**: High availability and auto-scaling setup
- **Monitoring**: Observability and health checks
- **Troubleshooting**: Common issues and solutions

## Prerequisites

### Kubernetes Cluster Requirements

| Component | Requirement |
|-----------|-------------|
| **Kubernetes Version** | ≥ 1.20.0 |
| **CPU** | ≥ 8 cores total |
| **Memory** | ≥ 32 GB total |
| **Storage** | ≥ 100 GB persistent volumes |
| **Nodes** | ≥ 3 nodes (recommended for HA) |

### Required Tools

```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installations
kubectl version --client
helm version
```

### Storage Classes

Ensure your cluster has a default storage class or configure one:

```bash
# Check available storage classes
kubectl get storageclass

# Set default storage class (if needed)
kubectl patch storageclass <your-storage-class> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/infiniflow/ragflow.git
cd ragflow/helm
```

### 2. Basic Installation

```bash
# Create namespace
kubectl create namespace ragflow

# Install with default values
helm install ragflow . -n ragflow

# Check deployment status
kubectl get pods -n ragflow
```

### 3. Access RAGFlow

```bash
# Port forward to access locally
kubectl port-forward -n ragflow svc/ragflow 8080:80

# Access at http://localhost:8080
```

## Configuration

### Custom Values File

Create a `custom-values.yaml` file for your environment:

```yaml
# custom-values.yaml
env:
  # Use Infinity as document engine (recommended)
  DOC_ENGINE: infinity
  
  # Configure timezone
  TIMEZONE: "UTC"
  
  # Set strong passwords
  MYSQL_PASSWORD: "your-secure-mysql-password"
  REDIS_PASSWORD: "your-secure-redis-password"
  MINIO_PASSWORD: "your-secure-minio-password"
  ELASTIC_PASSWORD: "your-secure-elastic-password"
  
  # Use full image with embedding models
  RAGFLOW_IMAGE: infiniflow/ragflow:v0.19.1

# Configure resource requests and limits
ragflow:
  deployment:
    resources:
      requests:
        cpu: "2"
        memory: "4Gi"
      limits:
        cpu: "4"
        memory: "8Gi"
  service:
    type: LoadBalancer  # or NodePort for on-premises

# Configure persistent storage
mysql:
  storage:
    className: "fast-ssd"  # Your storage class
    capacity: 20Gi
  deployment:
    resources:
      requests:
        cpu: "1"
        memory: "2Gi"
      limits:
        cpu: "2"
        memory: "4Gi"

minio:
  storage:
    className: "fast-ssd"
    capacity: 50Gi
  deployment:
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "1"
        memory: "2Gi"

redis:
  storage:
    className: "fast-ssd"
    capacity: 10Gi
  deployment:
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "1"
        memory: "2Gi"

infinity:
  storage:
    className: "fast-ssd"
    capacity: 20Gi
  deployment:
    resources:
      requests:
        cpu: "2"
        memory: "4Gi"
      limits:
        cpu: "4"
        memory: "8Gi"

# Configure ingress for external access
ingress:
  enabled: true
  className: "nginx"  # or your ingress controller
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
  hosts:
    - host: ragflow.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: ragflow-tls
      hosts:
        - ragflow.yourdomain.com
```

### Deploy with Custom Configuration

```bash
# Install with custom values
helm install ragflow . -n ragflow -f custom-values.yaml

# Or upgrade existing installation
helm upgrade ragflow . -n ragflow -f custom-values.yaml
```

## Production Configuration

### High Availability Setup

For production deployments, configure multiple replicas and anti-affinity:

```yaml
# production-values.yaml
ragflow:
  deployment:
    replicas: 3
    strategy:
      type: RollingUpdate
      rollingUpdate:
        maxSurge: 1
        maxUnavailable: 0
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                - ragflow
            topologyKey: kubernetes.io/hostname

mysql:
  deployment:
    replicas: 1  # Use external managed database for HA
    
redis:
  deployment:
    replicas: 1  # Use Redis Cluster for HA
```

### Resource Limits and Requests

```yaml
# Set appropriate resource limits
ragflow:
  deployment:
    resources:
      requests:
        cpu: "4"
        memory: "8Gi"
      limits:
        cpu: "8"
        memory: "16Gi"

infinity:
  deployment:
    resources:
      requests:
        cpu: "4"
        memory: "8Gi"
      limits:
        cpu: "8"
        memory: "16Gi"
```

## External Services Integration

### Using Managed Databases

For production, consider using managed services:

```yaml
# external-services-values.yaml
env:
  # External MySQL (e.g., AWS RDS, Google Cloud SQL)
  MYSQL_HOST: "your-mysql-endpoint.amazonaws.com"
  MYSQL_PORT: "3306"
  MYSQL_PASSWORD: "your-secure-password"
  
  # External Redis (e.g., AWS ElastiCache, Google Memorystore)
  REDIS_HOST: "your-redis-endpoint.amazonaws.com"
  REDIS_PORT: "6379"
  REDIS_PASSWORD: "your-secure-password"
  
  # External Object Storage (e.g., AWS S3, Google Cloud Storage)
  MINIO_HOST: "s3.amazonaws.com"
  MINIO_ROOT_USER: "your-access-key"
  MINIO_PASSWORD: "your-secret-key"

# Disable internal services when using external ones
mysql:
  enabled: false
redis:
  enabled: false
minio:
  enabled: false
```

## Monitoring and Observability

### Health Checks

The Helm chart includes built-in health checks:

```bash
# Check pod health
kubectl get pods -n ragflow

# View pod logs
kubectl logs -n ragflow deployment/ragflow

# Check service endpoints
kubectl get endpoints -n ragflow
```

### Prometheus Monitoring

Add Prometheus annotations for monitoring:

```yaml
ragflow:
  deployment:
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "9380"
      prometheus.io/path: "/metrics"
```

## Scaling

### Horizontal Pod Autoscaling

```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ragflow-hpa
  namespace: ragflow
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ragflow
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

Apply the HPA:

```bash
kubectl apply -f hpa.yaml
```

## Security

### Network Policies

```yaml
# network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ragflow-network-policy
  namespace: ragflow
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: ragflow
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: mysql
    ports:
    - protocol: TCP
      port: 3306
```

### RBAC Configuration

```yaml
# rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ragflow
  namespace: ragflow
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ragflow
  namespace: ragflow
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ragflow
  namespace: ragflow
subjects:
- kind: ServiceAccount
  name: ragflow
  namespace: ragflow
roleRef:
  kind: Role
  name: ragflow
  apiGroup: rbac.authorization.k8s.io
```

## Backup and Recovery

### Database Backup

```bash
# Create backup job
kubectl create job --from=cronjob/mysql-backup mysql-backup-manual -n ragflow

# Restore from backup
kubectl exec -it mysql-pod -n ragflow -- mysql -u root -p < backup.sql
```

### Persistent Volume Backup

```yaml
# backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ragflow-backup
  namespace: ragflow
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: alpine:latest
            command:
            - /bin/sh
            - -c
            - |
              apk add --no-cache rsync
              rsync -av /data/ /backup/$(date +%Y%m%d)/
            volumeMounts:
            - name: data
              mountPath: /data
            - name: backup
              mountPath: /backup
          volumes:
          - name: data
            persistentVolumeClaim:
              claimName: ragflow-data
          - name: backup
            persistentVolumeClaim:
              claimName: ragflow-backup
          restartPolicy: OnFailure
```

## Troubleshooting

### Common Issues

#### Pod Stuck in Pending State

```bash
# Check node resources
kubectl describe nodes

# Check PVC status
kubectl get pvc -n ragflow

# Check events
kubectl get events -n ragflow --sort-by='.lastTimestamp'
```

#### Service Not Accessible

```bash
# Check service endpoints
kubectl get endpoints -n ragflow

# Check ingress status
kubectl describe ingress ragflow -n ragflow

# Test internal connectivity
kubectl run test-pod --image=busybox -it --rm -- wget -qO- http://ragflow.ragflow.svc.cluster.local
```

#### Database Connection Issues

```bash
# Check MySQL pod logs
kubectl logs -n ragflow deployment/mysql

# Test database connectivity
kubectl exec -it deployment/ragflow -n ragflow -- nc -zv mysql 3306
```

### Debugging Commands

```bash
# Get all resources in namespace
kubectl get all -n ragflow

# Describe problematic pod
kubectl describe pod <pod-name> -n ragflow

# Check resource usage
kubectl top pods -n ragflow
kubectl top nodes

# View detailed logs
kubectl logs -f deployment/ragflow -n ragflow --previous
```

## Helm Commands Reference

```bash
# List releases
helm list -n ragflow

# Get values
helm get values ragflow -n ragflow

# Upgrade release
helm upgrade ragflow . -n ragflow -f values.yaml

# Rollback release
helm rollback ragflow 1 -n ragflow

# Uninstall release
helm uninstall ragflow -n ragflow

# Dry run installation
helm install ragflow . -n ragflow --dry-run --debug
```

## Next Steps

After successful Kubernetes deployment:

1. [Configure SSL/TLS certificates](../security/ssl_setup.md)
2. [Set up monitoring and alerting](../monitoring/prometheus_setup.md)
3. [Configure backup strategies](../backup/backup_guide.md)
4. [Implement CI/CD pipelines](../cicd/pipeline_setup.md)

For additional support, visit our [community channels](https://github.com/orgs/infiniflow/discussions) or check the [FAQ](../../faq.mdx).
