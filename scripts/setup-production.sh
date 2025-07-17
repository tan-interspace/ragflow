#!/bin/bash

# =============================================================================
# RAGFlow Production Setup Script
# =============================================================================
# This script sets up the production environment for RAGFlow
# including directory structure, permissions, and initial configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VOLUMES_DIR="$PROJECT_ROOT/volumes"
BACKUP_DIR="$PROJECT_ROOT/backups"
LOGS_DIR="$PROJECT_ROOT/logs"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root for security reasons"
        exit 1
    fi
}

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check available disk space (minimum 50GB)
    available_space=$(df "$PROJECT_ROOT" | awk 'NR==2 {print $4}')
    required_space=$((50 * 1024 * 1024)) # 50GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        print_warning "Available disk space is less than 50GB. Consider freeing up space."
    fi
    
    # Check available memory (minimum 16GB)
    available_memory=$(free -m | awk 'NR==2{print $2}')
    required_memory=16384 # 16GB in MB
    
    if [[ $available_memory -lt $required_memory ]]; then
        print_warning "Available memory is less than 16GB. Performance may be affected."
    fi
    
    print_success "System requirements check completed"
}

# Function to create directory structure
create_directories() {
    print_status "Creating directory structure..."
    
    # Main directories
    mkdir -p "$VOLUMES_DIR"/{ragflow,mysql,elasticsearch,redis,minio}/{data,logs,config}
    mkdir -p "$BACKUP_DIR"/{mysql,elasticsearch,ragflow}
    mkdir -p "$LOGS_DIR"
    mkdir -p "$PROJECT_ROOT"/{nginx,monitoring,scripts}
    mkdir -p "$PROJECT_ROOT"/ssl
    
    # RAGFlow specific directories
    mkdir -p "$VOLUMES_DIR/ragflow"/{models,history_data_agent}
    
    # MySQL specific directories
    mkdir -p "$VOLUMES_DIR/mysql/conf.d"
    
    # Elasticsearch specific directories
    mkdir -p "$VOLUMES_DIR/elasticsearch"/{config,plugins}
    
    # Redis specific directories
    mkdir -p "$VOLUMES_DIR/redis/conf"
    
    # MinIO specific directories
    mkdir -p "$VOLUMES_DIR/minio/config"
    
    # Monitoring directories
    mkdir -p "$PROJECT_ROOT/monitoring"/{grafana,prometheus,alertmanager}
    mkdir -p "$PROJECT_ROOT/monitoring/grafana"/{dashboards,datasources}
    
    print_success "Directory structure created"
}

# Function to set proper permissions
set_permissions() {
    print_status "Setting proper permissions..."
    
    # Set ownership for volume directories
    sudo chown -R 1000:1000 "$VOLUMES_DIR/ragflow"
    sudo chown -R 999:999 "$VOLUMES_DIR/mysql"
    sudo chown -R 1000:1000 "$VOLUMES_DIR/elasticsearch"
    sudo chown -R 999:999 "$VOLUMES_DIR/redis"
    sudo chown -R 1001:1001 "$VOLUMES_DIR/minio"
    
    # Set proper permissions
    chmod -R 755 "$VOLUMES_DIR"
    chmod -R 644 "$PROJECT_ROOT"/*.yml
    chmod +x "$PROJECT_ROOT"/scripts/*.sh
    
    # Secure sensitive files
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        chmod 600 "$PROJECT_ROOT/.env"
    fi
    
    print_success "Permissions set correctly"
}

# Function to generate SSL certificates (self-signed for development)
generate_ssl_certificates() {
    print_status "Generating SSL certificates..."
    
    SSL_DIR="$PROJECT_ROOT/ssl"
    
    if [[ ! -f "$SSL_DIR/ragflow.crt" ]]; then
        # Generate private key
        openssl genrsa -out "$SSL_DIR/ragflow.key" 2048
        
        # Generate certificate signing request
        openssl req -new -key "$SSL_DIR/ragflow.key" -out "$SSL_DIR/ragflow.csr" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=ragflow.local"
        
        # Generate self-signed certificate
        openssl x509 -req -days 365 -in "$SSL_DIR/ragflow.csr" \
            -signkey "$SSL_DIR/ragflow.key" -out "$SSL_DIR/ragflow.crt"
        
        # Set proper permissions
        chmod 600 "$SSL_DIR/ragflow.key"
        chmod 644 "$SSL_DIR/ragflow.crt"
        
        print_success "SSL certificates generated"
        print_warning "Using self-signed certificates. Replace with proper certificates for production."
    else
        print_status "SSL certificates already exist"
    fi
}

# Function to create environment file
create_env_file() {
    print_status "Creating environment file..."
    
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        cp "$PROJECT_ROOT/.env.production" "$PROJECT_ROOT/.env"
        
        # Generate random passwords
        MYSQL_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        MINIO_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        ELASTIC_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        JWT_SECRET=$(openssl rand -base64 64 | tr -d "=+/" | cut -c1-50)
        
        # Replace placeholder passwords
        sed -i "s/CHANGE_THIS_MYSQL_PASSWORD_IN_PRODUCTION/$MYSQL_PASSWORD/g" "$PROJECT_ROOT/.env"
        sed -i "s/CHANGE_THIS_REDIS_PASSWORD_IN_PRODUCTION/$REDIS_PASSWORD/g" "$PROJECT_ROOT/.env"
        sed -i "s/CHANGE_THIS_MINIO_PASSWORD_IN_PRODUCTION/$MINIO_PASSWORD/g" "$PROJECT_ROOT/.env"
        sed -i "s/CHANGE_THIS_ELASTICSEARCH_PASSWORD_IN_PRODUCTION/$ELASTIC_PASSWORD/g" "$PROJECT_ROOT/.env"
        sed -i "s/CHANGE_THIS_JWT_SECRET_TO_A_RANDOM_STRING_IN_PRODUCTION/$JWT_SECRET/g" "$PROJECT_ROOT/.env"
        
        chmod 600 "$PROJECT_ROOT/.env"
        
        print_success "Environment file created with random passwords"
        print_warning "Please review and customize the .env file before starting services"
    else
        print_status "Environment file already exists"
    fi
}

# Function to initialize system settings
init_system_settings() {
    print_status "Initializing system settings..."
    
    # Increase vm.max_map_count for Elasticsearch
    echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
    
    # Increase file descriptor limits
    echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
    echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf
    
    # Disable swap for better performance
    sudo swapoff -a
    
    print_success "System settings initialized"
}

# Function to create backup script
create_backup_script() {
    print_status "Creating backup script..."
    
    cat > "$PROJECT_ROOT/scripts/backup.sh" << 'EOF'
#!/bin/bash

# RAGFlow Backup Script
set -euo pipefail

BACKUP_DIR="/path/to/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR/$DATE"

# Backup MySQL
docker exec ragflow-mysql mysqldump -u root -p$MYSQL_PASSWORD --all-databases > "$BACKUP_DIR/$DATE/mysql_backup.sql"

# Backup Elasticsearch
docker exec ragflow-elasticsearch curl -X PUT "localhost:9200/_snapshot/backup_repo/$DATE" -H 'Content-Type: application/json' -d'{"indices": "*"}'

# Backup MinIO data
docker exec ragflow-minio mc mirror /data "$BACKUP_DIR/$DATE/minio/"

# Backup RAGFlow data
tar -czf "$BACKUP_DIR/$DATE/ragflow_data.tar.gz" -C /path/to/volumes/ragflow .

# Clean old backups (keep last 7 days)
find "$BACKUP_DIR" -type d -mtime +7 -exec rm -rf {} +

echo "Backup completed: $BACKUP_DIR/$DATE"
EOF
    
    chmod +x "$PROJECT_ROOT/scripts/backup.sh"
    print_success "Backup script created"
}

# Function to create monitoring setup
setup_monitoring() {
    print_status "Setting up monitoring configuration..."
    
    # Create Grafana datasource configuration
    cat > "$PROJECT_ROOT/monitoring/grafana/datasources/prometheus.yml" << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF
    
    print_success "Monitoring configuration created"
}

# Function to validate configuration
validate_configuration() {
    print_status "Validating configuration..."
    
    # Check if required files exist
    required_files=(
        "$PROJECT_ROOT/docker-compose.production.yml"
        "$PROJECT_ROOT/.env"
        "$PROJECT_ROOT/nginx/ragflow.production.conf"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_error "Required file missing: $file"
            exit 1
        fi
    done
    
    # Validate Docker Compose file
    if ! docker-compose -f "$PROJECT_ROOT/docker-compose.production.yml" config > /dev/null 2>&1; then
        print_error "Docker Compose configuration is invalid"
        exit 1
    fi
    
    print_success "Configuration validation completed"
}

# Main function
main() {
    print_status "Starting RAGFlow production setup..."
    
    check_root
    check_requirements
    create_directories
    set_permissions
    generate_ssl_certificates
    create_env_file
    init_system_settings
    create_backup_script
    setup_monitoring
    validate_configuration
    
    print_success "RAGFlow production setup completed successfully!"
    echo
    print_status "Next steps:"
    echo "1. Review and customize the .env file"
    echo "2. Replace self-signed SSL certificates with proper ones"
    echo "3. Configure your domain name in nginx configuration"
    echo "4. Start the services: docker-compose -f docker-compose.production.yml up -d"
    echo "5. Monitor the logs: docker-compose -f docker-compose.production.yml logs -f"
    echo
    print_warning "Remember to:"
    echo "- Set up proper DNS records for your domain"
    echo "- Configure firewall rules"
    echo "- Set up monitoring and alerting"
    echo "- Schedule regular backups"
    echo "- Review security settings"
}

# Run main function
main "$@"
