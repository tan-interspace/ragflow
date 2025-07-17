#!/bin/bash

# =============================================================================
# RAGFlow Health Check Script
# =============================================================================
# This script performs comprehensive health checks on all RAGFlow services
# and provides detailed status information

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
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.production.yml"

# Service endpoints
RAGFLOW_URL="http://localhost:9380"
ELASTICSEARCH_URL="http://localhost:1200"
MYSQL_PORT="5455"
REDIS_PORT="6379"
MINIO_URL="http://localhost:9000"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Function to check if a service is running
check_service_running() {
    local service_name=$1
    local container_name=$2
    
    if docker ps --format "table {{.Names}}" | grep -q "^$container_name$"; then
        print_success "$service_name is running"
        return 0
    else
        print_error "$service_name is not running"
        return 1
    fi
}

# Function to check service health
check_service_health() {
    local service_name=$1
    local container_name=$2
    
    local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-health-check")
    
    case $health_status in
        "healthy")
            print_success "$service_name health check: HEALTHY"
            return 0
            ;;
        "unhealthy")
            print_error "$service_name health check: UNHEALTHY"
            return 1
            ;;
        "starting")
            print_warning "$service_name health check: STARTING"
            return 1
            ;;
        "no-health-check")
            print_warning "$service_name: No health check configured"
            return 0
            ;;
        *)
            print_warning "$service_name health check: UNKNOWN ($health_status)"
            return 1
            ;;
    esac
}

# Function to check HTTP endpoint
check_http_endpoint() {
    local service_name=$1
    local url=$2
    local expected_status=${3:-200}
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [[ "$response" == "$expected_status" ]]; then
        print_success "$service_name HTTP endpoint: OK ($response)"
        return 0
    else
        print_error "$service_name HTTP endpoint: FAILED ($response)"
        return 1
    fi
}

# Function to check TCP port
check_tcp_port() {
    local service_name=$1
    local host=$2
    local port=$3
    
    if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        print_success "$service_name TCP port $port: OPEN"
        return 0
    else
        print_error "$service_name TCP port $port: CLOSED"
        return 1
    fi
}

# Function to check Docker Compose services
check_docker_compose() {
    print_header "Docker Compose Services"
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_error "Docker Compose file not found: $COMPOSE_FILE"
        return 1
    fi
    
    # Check if services are defined
    local services=$(docker-compose -f "$COMPOSE_FILE" config --services 2>/dev/null || echo "")
    
    if [[ -z "$services" ]]; then
        print_error "No services found in Docker Compose file"
        return 1
    fi
    
    print_success "Docker Compose file is valid"
    print_status "Defined services: $(echo $services | tr '\n' ' ')"
    
    # Check running services
    local running_services=$(docker-compose -f "$COMPOSE_FILE" ps --services --filter "status=running" 2>/dev/null || echo "")
    print_status "Running services: $(echo $running_services | tr '\n' ' ')"
    
    return 0
}

# Function to check RAGFlow application
check_ragflow() {
    print_header "RAGFlow Application"
    
    check_service_running "RAGFlow" "ragflow-server" || return 1
    check_service_health "RAGFlow" "ragflow-server"
    
    # Check main endpoint
    check_http_endpoint "RAGFlow Main" "$RAGFLOW_URL"
    
    # Check health endpoint
    check_http_endpoint "RAGFlow Health" "$RAGFLOW_URL/health"
    
    # Check API endpoint
    check_http_endpoint "RAGFlow API" "$RAGFLOW_URL/v1/system/health"
    
    # Check resource usage
    local cpu_usage=$(docker stats ragflow-server --no-stream --format "{{.CPUPerc}}" 2>/dev/null | sed 's/%//' || echo "N/A")
    local mem_usage=$(docker stats ragflow-server --no-stream --format "{{.MemUsage}}" 2>/dev/null || echo "N/A")
    
    print_status "RAGFlow CPU usage: $cpu_usage%"
    print_status "RAGFlow Memory usage: $mem_usage"
    
    return 0
}

# Function to check MySQL
check_mysql() {
    print_header "MySQL Database"
    
    check_service_running "MySQL" "ragflow-mysql" || return 1
    check_service_health "MySQL" "ragflow-mysql"
    check_tcp_port "MySQL" "localhost" "$MYSQL_PORT"
    
    # Check database connectivity
    if docker exec ragflow-mysql mysqladmin ping -h localhost --silent 2>/dev/null; then
        print_success "MySQL database: ACCESSIBLE"
    else
        print_error "MySQL database: NOT ACCESSIBLE"
        return 1
    fi
    
    # Check database size
    local db_size=$(docker exec ragflow-mysql mysql -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'DB Size in MB' FROM information_schema.tables WHERE table_schema='rag_flow';" 2>/dev/null | tail -n 1 || echo "N/A")
    print_status "Database size: ${db_size} MB"
    
    return 0
}

# Function to check Elasticsearch
check_elasticsearch() {
    print_header "Elasticsearch"
    
    check_service_running "Elasticsearch" "ragflow-elasticsearch" || return 1
    check_service_health "Elasticsearch" "ragflow-elasticsearch"
    check_http_endpoint "Elasticsearch" "$ELASTICSEARCH_URL"
    
    # Check cluster health
    local cluster_health=$(curl -s "$ELASTICSEARCH_URL/_cluster/health" 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unknown")
    
    case $cluster_health in
        "green")
            print_success "Elasticsearch cluster health: GREEN"
            ;;
        "yellow")
            print_warning "Elasticsearch cluster health: YELLOW"
            ;;
        "red")
            print_error "Elasticsearch cluster health: RED"
            return 1
            ;;
        *)
            print_warning "Elasticsearch cluster health: UNKNOWN"
            ;;
    esac
    
    # Check indices
    local indices_count=$(curl -s "$ELASTICSEARCH_URL/_cat/indices?format=json" 2>/dev/null | jq length 2>/dev/null || echo "N/A")
    print_status "Elasticsearch indices count: $indices_count"
    
    return 0
}

# Function to check Redis
check_redis() {
    print_header "Redis Cache"
    
    check_service_running "Redis" "ragflow-redis" || return 1
    check_service_health "Redis" "ragflow-redis"
    check_tcp_port "Redis" "localhost" "$REDIS_PORT"
    
    # Check Redis connectivity (requires password)
    if docker exec ragflow-redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
        print_success "Redis: ACCESSIBLE"
    else
        print_warning "Redis: Authentication required or not accessible"
    fi
    
    # Check memory usage
    local redis_memory=$(docker exec ragflow-redis redis-cli info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r' || echo "N/A")
    print_status "Redis memory usage: $redis_memory"
    
    return 0
}

# Function to check MinIO
check_minio() {
    print_header "MinIO Object Storage"
    
    check_service_running "MinIO" "ragflow-minio" || return 1
    check_service_health "MinIO" "ragflow-minio"
    check_http_endpoint "MinIO Health" "$MINIO_URL/minio/health/live"
    
    # Check MinIO API
    check_http_endpoint "MinIO API" "$MINIO_URL/minio/health/ready"
    
    return 0
}

# Function to check system resources
check_system_resources() {
    print_header "System Resources"
    
    # Check disk space
    local disk_usage=$(df -h "$PROJECT_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        print_error "Disk usage is high: ${disk_usage}%"
    elif [[ $disk_usage -gt 80 ]]; then
        print_warning "Disk usage is moderate: ${disk_usage}%"
    else
        print_success "Disk usage is normal: ${disk_usage}%"
    fi
    
    # Check memory usage
    local mem_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    if (( $(echo "$mem_usage > 90" | bc -l) )); then
        print_error "Memory usage is high: ${mem_usage}%"
    elif (( $(echo "$mem_usage > 80" | bc -l) )); then
        print_warning "Memory usage is moderate: ${mem_usage}%"
    else
        print_success "Memory usage is normal: ${mem_usage}%"
    fi
    
    # Check CPU load
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_cores=$(nproc)
    local cpu_usage=$(echo "scale=1; $cpu_load * 100 / $cpu_cores" | bc)
    
    if (( $(echo "$cpu_usage > 90" | bc -l) )); then
        print_error "CPU load is high: ${cpu_usage}%"
    elif (( $(echo "$cpu_usage > 70" | bc -l) )); then
        print_warning "CPU load is moderate: ${cpu_usage}%"
    else
        print_success "CPU load is normal: ${cpu_usage}%"
    fi
    
    return 0
}

# Function to check network connectivity
check_network() {
    print_header "Network Connectivity"
    
    # Check Docker network
    local network_name="ragflow_ragflow_network"
    if docker network ls | grep -q "$network_name"; then
        print_success "Docker network exists: $network_name"
    else
        print_error "Docker network missing: $network_name"
        return 1
    fi
    
    # Check inter-service connectivity
    if docker exec ragflow-server ping -c 1 ragflow-mysql >/dev/null 2>&1; then
        print_success "RAGFlow can reach MySQL"
    else
        print_error "RAGFlow cannot reach MySQL"
    fi
    
    if docker exec ragflow-server ping -c 1 ragflow-elasticsearch >/dev/null 2>&1; then
        print_success "RAGFlow can reach Elasticsearch"
    else
        print_error "RAGFlow cannot reach Elasticsearch"
    fi
    
    return 0
}

# Function to generate summary report
generate_summary() {
    print_header "Health Check Summary"
    
    local total_checks=$1
    local failed_checks=$2
    local success_rate=$(( (total_checks - failed_checks) * 100 / total_checks ))
    
    echo "Total checks: $total_checks"
    echo "Failed checks: $failed_checks"
    echo "Success rate: ${success_rate}%"
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "All health checks passed!"
        return 0
    elif [[ $failed_checks -le 2 ]]; then
        print_warning "Some health checks failed, but system is mostly operational"
        return 1
    else
        print_error "Multiple health checks failed, system may not be operational"
        return 2
    fi
}

# Main function
main() {
    echo "RAGFlow Production Health Check"
    echo "==============================="
    echo "Timestamp: $(date)"
    echo "Host: $(hostname)"
    echo
    
    local failed_checks=0
    local total_checks=0
    
    # Run all health checks
    check_docker_compose || ((failed_checks++))
    ((total_checks++))
    
    check_ragflow || ((failed_checks++))
    ((total_checks++))
    
    check_mysql || ((failed_checks++))
    ((total_checks++))
    
    check_elasticsearch || ((failed_checks++))
    ((total_checks++))
    
    check_redis || ((failed_checks++))
    ((total_checks++))
    
    check_minio || ((failed_checks++))
    ((total_checks++))
    
    check_system_resources || ((failed_checks++))
    ((total_checks++))
    
    check_network || ((failed_checks++))
    ((total_checks++))
    
    # Generate summary
    generate_summary $total_checks $failed_checks
    local exit_code=$?
    
    echo
    echo "Health check completed at $(date)"
    
    exit $exit_code
}

# Run main function
main "$@"
