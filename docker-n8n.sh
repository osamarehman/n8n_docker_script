#!/bin/bash

# ==============================================================================
# n8n Production Stack - Simplified & Fixed
# - Removed PostgreSQL (uses SQLite instead)
# - Fixed username validation for emails
# - Added Portainer for Docker management
# - Simplified configuration
# ==============================================================================

set -euo pipefail

# --- Configuration ---
readonly SCRIPT_NAME="n8n Production Stack"
readonly SCRIPT_VERSION="2.2.0-simplified"
readonly MIN_RAM_GB=2
readonly MIN_DISK_GB=8
readonly SETUP_DIR="/opt/n8n-stack"

# Pinned versions
readonly N8N_VERSION="1.58.2"
readonly QDRANT_VERSION="v1.7.4"
readonly CADDY_VERSION="2.7-alpine"
readonly DOZZLE_VERSION="v6.2.0"
readonly PORTAINER_VERSION="2.19.4"

# Initialize variables
N8N_DOMAIN="${N8N_DOMAIN:-}"
N8N_USER="${N8N_USER:-}"
DOCKER_COMPOSE_CMD=""

# --- Color Functions ---
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

# --- Fixed Input Collection ---
collect_configuration() {
    info "Collecting deployment configuration..."
    
    # Detect execution context
    local auto_mode=false
    local non_interactive=false
    
    # Check for auto mode
    for arg in "$@"; do
        if [ "$arg" = "--auto" ]; then
            auto_mode=true
            break
        fi
    done
    
    # Check if running non-interactively
    if [ ! -t 0 ] && [ "$auto_mode" = "false" ]; then
        non_interactive=true
    fi
    
    # Collect N8N_DOMAIN
    if [ -z "$N8N_DOMAIN" ]; then
        if [ "$auto_mode" = "true" ] || [ "$non_interactive" = "true" ]; then
            info "Using IP-based access (no domain configured)"
        else
            if [ -c /dev/tty ]; then
                echo -n "Enter domain for n8n (leave empty for IP access): " > /dev/tty
                read N8N_DOMAIN < /dev/tty || N8N_DOMAIN=""
            else
                info "Non-interactive mode: Using IP-based access"
            fi
        fi
    fi
    
    # Validate and report domain
    if [ -n "$N8N_DOMAIN" ]; then
        if [[ ! "$N8N_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]]; then
            warning "Domain format may be invalid: $N8N_DOMAIN"
        fi
        info "🌐 Domain-based setup: $N8N_DOMAIN (HTTPS enabled)"
    else
        info "🌐 IP-based setup (HTTP only)"
    fi
    
    # Collect N8N_USER with proper email validation
    if [ -z "$N8N_USER" ]; then
        if [ "$auto_mode" = "true" ] || [ "$non_interactive" = "true" ]; then
            N8N_USER="admin@example.com"
            info "Using default username 'admin@example.com'"
        else
            if [ -c /dev/tty ]; then
                echo -n "Enter n8n admin username/email [admin@example.com]: " > /dev/tty
                read N8N_USER < /dev/tty || N8N_USER=""
                N8N_USER="${N8N_USER:-admin@example.com}"
            else
                N8N_USER="admin@example.com"
                info "Using default username 'admin@example.com'"
            fi
        fi
    fi
    
    # FIXED: Better username validation (allow emails)
    if [[ ! "$N8N_USER" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$|^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid username format: $N8N_USER (use email address or alphanumeric/underscore/hyphen)"
    fi
    
    info "👤 Admin username: $N8N_USER"
    
    # Configuration summary
    echo
    info "📋 Configuration Summary:"
    info "   Domain: ${N8N_DOMAIN:-"IP-based access"}"
    info "   Username: $N8N_USER"
    info "   Database: SQLite (file-based, no PostgreSQL)"
    info "   HTTPS: ${N8N_DOMAIN:+Enabled}${N8N_DOMAIN:-Disabled}"
    echo
}

# --- Check Dependencies ---
check_system_requirements() {
    info "Checking VPS system requirements..."
    
    local memory_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    if [ $memory_gb -lt $MIN_RAM_GB ]; then
        error "Insufficient RAM: ${memory_gb}GB. Minimum required: ${MIN_RAM_GB}GB"
    fi
    
    local disk_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [ $disk_gb -lt $MIN_DISK_GB ]; then
        error "Insufficient disk space: ${disk_gb}GB. Minimum required: ${MIN_DISK_GB}GB"
    fi
    
    local cpu_cores=$(nproc)
    if [ $cpu_cores -lt 1 ]; then
        error "No CPU cores detected"
    fi
    
    success "VPS requirements met: ${memory_gb}GB RAM, ${disk_gb}GB disk, ${cpu_cores} CPU cores"
}

# --- Install Dependencies ---
install_dependencies() {
    info "Installing required packages..."
    
    apt-get update -y
    apt-get install -y curl wget ufw htop openssl
    
    success "Dependencies installed successfully"
}

# --- Install Docker ---
install_docker() {
    if docker --version >/dev/null 2>&1; then
        info "Docker already installed: $(docker --version)"
        return 0
    fi
    
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    
    # Wait for Docker to be ready
    sleep 5
    success "Docker installed successfully"
}

# --- Check Docker Compose ---
check_docker_compose() {
    info "Detecting Docker Compose..."
    
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
        info "Using Docker Compose: $(docker compose version --short 2>/dev/null || echo 'installed')"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
        info "Using legacy docker-compose"
    else
        error "Docker Compose not found"
    fi
}

# --- Generate Configuration ---
generate_credentials() {
    info "Generating secure credentials..."
    
    mkdir -p "$SETUP_DIR"
    
    # Generate secure password
    local n8n_password=$(openssl rand -base64 16 | tr -d "=+/\"'" | cut -c1-16)
    
    if [ ${#n8n_password} -lt 8 ]; then
        error "Failed to generate secure password"
    fi
    
    cat > "${SETUP_DIR}/.env" <<EOF
# n8n Production Stack Configuration - Simplified
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Timezone
TZ=UTC

# n8n Configuration
N8N_BASIC_AUTH_USER=${N8N_USER}
N8N_BASIC_AUTH_PASSWORD=${n8n_password}
N8N_LOG_LEVEL=warn
N8N_METRICS=false

# Container Versions
N8N_VERSION=${N8N_VERSION}
QDRANT_VERSION=${QDRANT_VERSION}
CADDY_VERSION=${CADDY_VERSION}
DOZZLE_VERSION=${DOZZLE_VERSION}
PORTAINER_VERSION=${PORTAINER_VERSION}

# Domain Configuration
${N8N_DOMAIN:+N8N_DOMAIN=${N8N_DOMAIN}}
EOF
    
    chmod 600 "${SETUP_DIR}/.env"
    success "Credentials generated"
}

# --- Create Docker Compose ---
create_docker_compose() {
    info "Creating Docker Compose configuration..."
    
    cat > "${SETUP_DIR}/docker-compose.yml" << 'EOF'
services:
  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    container_name: n8n
    restart: unless-stopped
    user: "1000:1000"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_LOG_LEVEL=${N8N_LOG_LEVEL}
      - TZ=${TZ}
      # Using SQLite instead of PostgreSQL
      - DB_TYPE=sqlite
      - DB_SQLITE_VACUUM_ON_STARTUP=true
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n_network
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s
EOF

    # Add ports for non-domain setup
    if [ -z "$N8N_DOMAIN" ]; then
        cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'
    ports:
      - "5678:5678"
EOF
    fi

    # Continue with other services
    cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'

  qdrant:
    image: qdrant/qdrant:${QDRANT_VERSION}
    container_name: qdrant
    restart: unless-stopped
    user: "1000:1000"
    volumes:
      - qdrant_data:/qdrant/storage
    networks:
      - n8n_network
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:6333/readiness || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF

    # Add Qdrant ports if no domain
    if [ -z "$N8N_DOMAIN" ]; then
        cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'
    ports:
      - "6333:6333"
EOF
    fi

    # Add Dozzle (logs viewer)
    cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'

  dozzle:
    image: amir20/dozzle:${DOZZLE_VERSION}
    container_name: dozzle
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - n8n_network
    environment:
      - DOZZLE_NO_ANALYTICS=true
    read_only: true
    tmpfs:
      - /tmp

  portainer:
    image: portainer/portainer-ce:${PORTAINER_VERSION}
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - n8n_network
    command: --admin-password='$$2y$$10$$N5b8jLZXyEoKQwXzT/6LQON8fXnG5/9mE9rL8J7FKkQVmqTGS8W3K'
EOF

    # Add Caddy for HTTPS if domain provided
    if [ -n "$N8N_DOMAIN" ]; then
        cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'

  caddy:
    image: caddy:${CADDY_VERSION}
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - n8n_network
    depends_on:
      n8n:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "caddy", "version"]
      interval: 30s
      timeout: 5s
      retries: 3
EOF
    fi

    # Add volumes and networks
    cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'

volumes:
  n8n_data:
  qdrant_data:
  portainer_data:
EOF

    if [ -n "$N8N_DOMAIN" ]; then
        cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'
  caddy_data:
  caddy_config:
EOF
    fi

    cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'

networks:
  n8n_network:
    driver: bridge
EOF

    # Create Caddyfile if domain provided
    if [ -n "$N8N_DOMAIN" ]; then
        cat > "${SETUP_DIR}/Caddyfile" << EOF
${N8N_DOMAIN} {
    reverse_proxy n8n:5678 {
        health_uri /healthz
        health_interval 30s
        health_timeout 5s
    }
    
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        -Server
    }
    
    encode gzip
}

http://${N8N_DOMAIN} {
    redir https://{host}{uri} permanent
}
EOF
    fi

    success "Docker Compose configuration created"
}

# --- Setup Firewall ---
setup_firewall() {
    if ! command -v ufw >/dev/null 2>&1; then
        warning "UFW not available"
        return 0
    fi
    
    info "Configuring firewall..."
    
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming
    ufw default allow outgoing
    
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 8080/tcp  # Dozzle
    ufw allow 9000/tcp  # Portainer
    
    if [ -z "${N8N_DOMAIN:-}" ]; then
        ufw allow 5678/tcp  # n8n
        ufw allow 6333/tcp  # Qdrant
    fi
    
    ufw --force enable
    success "Firewall configured"
}

# --- Deploy Services ---
deploy_services() {
    info "Deploying n8n stack..."
    
    cd "$SETUP_DIR"
    
    # Create directories with proper permissions
    info "Setting up data directories..."
    mkdir -p data/n8n data/qdrant data/portainer
    chown -R 1000:1000 data/n8n data/qdrant
    
    # Start services
    info "Starting containers..."
    $DOCKER_COMPOSE_CMD up -d
    
    # Wait for services
    info "Waiting for services to start (this may take 2-3 minutes)..."
    sleep 45
    
    # Check n8n specifically
    local wait_count=0
    while [ $wait_count -lt 60 ]; do
        if docker exec n8n wget --no-verbose --tries=1 --spider http://localhost:5678/healthz >/dev/null 2>&1; then
            success "n8n is healthy!"
            break
        fi
        echo "Waiting for n8n to be ready... ($wait_count/60)"
        sleep 5
        wait_count=$((wait_count + 5))
    done
    
    # Show container status
    info "Container status:"
    $DOCKER_COMPOSE_CMD ps
    
    success "Deployment completed!"
}

# --- Create Management Script ---
create_management_script() {
    cat > "${SETUP_DIR}/manage.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

case "${1:-help}" in
    start)   docker compose start ;;
    stop)    docker compose stop ;;
    restart) docker compose restart "${2:-}" ;;
    logs)    docker compose logs -f "${2:-}" ;;
    status)  
        echo "=== Container Status ==="
        docker compose ps
        echo
        echo "=== Resource Usage ==="
        docker stats --no-stream
        ;;
    update)  
        echo "Updating containers..."
        docker compose pull
        docker compose up -d
        ;;
    *)       
        echo "n8n Stack Management"
        echo "Usage: $0 {start|stop|restart|logs|status|update}"
        ;;
esac
EOF
    chmod +x "${SETUP_DIR}/manage.sh"
}

# --- Show Results ---
show_results() {
    local public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "your-server-ip")
    
    # Load credentials
    source "${SETUP_DIR}/.env"
    
    echo
    echo "🎉======================================================"
    echo "   n8n Production Stack Deployed Successfully!"
    echo "======================================================"
    echo
    
    if [ -n "${N8N_DOMAIN:-}" ]; then
        echo "🌐 n8n: https://${N8N_DOMAIN}"
        echo "⚠️  Ensure ${N8N_DOMAIN} DNS points to ${public_ip}"
    else
        echo "🌐 n8n: http://${public_ip}:5678"
        echo "🔧 Qdrant Vector DB: http://${public_ip}:6333"
    fi
    
    echo "📊 Container Logs: http://${public_ip}:8080 (Dozzle)"
    echo "🐳 Docker Management: http://${public_ip}:9000 (Portainer)"
    echo "   └─ Default password: admin/admin123456"
    echo
    echo "🔐 n8n Login:"
    echo "   Username: ${N8N_BASIC_AUTH_USER}"
    echo "   Password: ${N8N_BASIC_AUTH_PASSWORD}"
    echo
    echo "📁 Installation: ${SETUP_DIR}"
    echo "🛠️  Management: cd ${SETUP_DIR} && ./manage.sh status"
    echo
    echo "✅ Features:"
    echo "   ✓ SQLite database (no PostgreSQL complexity)"
    echo "   ✓ Qdrant vector database"
    echo "   ✓ Automatic HTTPS ${N8N_DOMAIN:+(with ${N8N_DOMAIN})}${N8N_DOMAIN:-"(add domain for HTTPS)"}"
    echo "   ✓ Container monitoring (Dozzle + Portainer)"
    echo "   ✓ Firewall configured"
    echo
}

# --- Main Function ---
main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Run as root: sudo $0"
    fi
    
    info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}..."
    
    collect_configuration "$@"
    check_system_requirements
    install_dependencies
    install_docker
    check_docker_compose
    setup_firewall
    generate_credentials
    create_docker_compose
    create_management_script
    deploy_services
    show_results
}

main "$@"