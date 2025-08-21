#!/bin/bash

# ==============================================================================
# n8n Production Stack - Simplified & Fixed with Retry Logic
# - Removed PostgreSQL (uses SQLite instead)
# - Fixed username validation for emails
# - Added Portainer for Docker management
# - Simplified configuration
# - Added comprehensive retry mechanisms for all operations
# ==============================================================================

set -euo pipefail

# --- Configuration ---
readonly SCRIPT_NAME="n8n Production Stack"
readonly SCRIPT_VERSION="2.4.0-cleanup-enhanced"
readonly MIN_RAM_GB=2
readonly MIN_DISK_GB=8
readonly SETUP_DIR="/opt/n8n-stack"

# Retry configuration
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5
readonly NETWORK_TIMEOUT=30

# Latest versions (always pull latest)
readonly N8N_VERSION="latest"
readonly QDRANT_VERSION="latest"
readonly CADDY_VERSION="latest"
readonly DOZZLE_VERSION="latest"
readonly PORTAINER_VERSION="latest"

# Initialize variables
N8N_DOMAIN="${N8N_DOMAIN:-}"
N8N_USER="${N8N_USER:-}"
DOCKER_COMPOSE_CMD=""

# --- Color Functions ---
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }
retry_info() { echo -e "\033[1;35m[RETRY]\033[0m $1"; }
cleanup_info() { echo -e "\033[1;36m[CLEANUP]\033[0m $1"; }

# --- Retry Framework ---
retry_with_user_prompt() {
    local operation_name="$1"
    local command_func="$2"
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        info "Attempting $operation_name (attempt $attempt/$MAX_RETRIES)..."
        
        if $command_func; then
            success "$operation_name completed successfully"
            return 0
        else
            local exit_code=$?
            warning "$operation_name failed on attempt $attempt/$MAX_RETRIES (exit code: $exit_code)"
            
            if [ $attempt -eq $MAX_RETRIES ]; then
                error_with_user_choice "$operation_name" "$command_func"
                return $?
            else
                retry_info "Waiting $RETRY_DELAY seconds before retry..."
                sleep $RETRY_DELAY
                attempt=$((attempt + 1))
            fi
        fi
    done
}

error_with_user_choice() {
    local operation_name="$1"
    local command_func="$2"
    
    echo
    error "❌ $operation_name failed after $MAX_RETRIES attempts!"
    echo
    echo "Options:"
    echo "1) Try again (r/retry)"
    echo "2) Skip this step (s/skip) - ⚠️  May cause issues"
    echo "3) Exit script (e/exit)"
    echo
    
    while true; do
        if [ -t 0 ]; then
            echo -n "Choose an option [r/s/e]: "
            read -r choice
        else
            echo "Non-interactive mode: exiting due to failure"
            exit 1
        fi
        
        case "${choice,,}" in
            r|retry)
                retry_info "Retrying $operation_name..."
                if retry_with_user_prompt "$operation_name" "$command_func"; then
                    return 0
                fi
                ;;
            s|skip)
                warning "⚠️  Skipping $operation_name - this may cause issues later!"
                return 0
                ;;
            e|exit)
                error "Exiting script as requested"
                ;;
            *)
                echo "Invalid choice. Please enter 'r' (retry), 's' (skip), or 'e' (exit)"
                ;;
        esac
    done
}

# --- Network Operations with Retry ---
safe_curl() {
    local url="$1"
    local output_file="${2:-}"
    local curl_args=("--fail" "--silent" "--show-error" "--location" "--connect-timeout" "$NETWORK_TIMEOUT" "--max-time" "$((NETWORK_TIMEOUT * 2))")
    
    if [ -n "$output_file" ]; then
        curl_args+=("--output" "$output_file")
    fi
    
    curl "${curl_args[@]}" "$url"
}

safe_wget() {
    local url="$1"
    local wget_args=("--quiet" "--timeout=$NETWORK_TIMEOUT" "--tries=1")
    
    wget "${wget_args[@]}" "$url"
}

# --- Docker Operations with Retry ---
docker_operation() {
    local operation="$1"
    shift
    
    case "$operation" in
        "pull")
            docker pull "$@"
            ;;
        "compose_up")
            $DOCKER_COMPOSE_CMD up -d "$@"
            ;;
        "compose_down")
            $DOCKER_COMPOSE_CMD down "$@"
            ;;
        "health_check")
            local container="$1"
            local health_url="$2"
            docker exec "$container" wget --no-verbose --tries=1 --spider "$health_url"
            ;;
        *)
            error "Unknown docker operation: $operation"
            ;;
    esac
}

# --- System Operations with Retry ---
system_operation() {
    local operation="$1"
    shift
    
    case "$operation" in
        "apt_update")
            apt-get update -y
            ;;
        "apt_install")
            apt-get install -y "$@"
            ;;
        "systemctl_enable")
            systemctl enable "$@"
            ;;
        "systemctl_start")
            systemctl start "$@"
            ;;
        "ufw_reset")
            ufw --force reset >/dev/null 2>&1
            ;;
        "ufw_enable")
            ufw --force enable
            ;;
        *)
            error "Unknown system operation: $operation"
            ;;
    esac
}

# --- File Operations with Retry ---
file_operation() {
    local operation="$1"
    shift
    
    case "$operation" in
        "mkdir")
            mkdir -p "$@"
            ;;
        "chown")
            chown -R "$@"
            ;;
        "chmod")
            chmod "$@"
            ;;
        "create_file")
            local file_path="$1"
            local content="$2"
            echo "$content" > "$file_path"
            ;;
        *)
            error "Unknown file operation: $operation"
            ;;
    esac
}

# --- Cleanup Functions ---
detect_existing_installation() {
    local has_containers=false
    local has_config=false
    local has_volumes=false
    
    # Check for existing containers
    local containers=("n8n" "qdrant" "dozzle" "portainer" "caddy")
    local existing_containers=()
    
    for container in "${containers[@]}"; do
        if docker ps -a --format "table {{.Names}}" | grep -q "^${container}$"; then
            existing_containers+=("$container")
            has_containers=true
        fi
    done
    
    # Check for existing configuration directory
    if [ -d "$SETUP_DIR" ]; then
        has_config=true
    fi
    
    # Check for existing Docker volumes
    local volumes=("n8n_data" "qdrant_data" "portainer_data" "caddy_data" "caddy_config")
    local existing_volumes=()
    
    for volume in "${volumes[@]}"; do
        if docker volume ls --format "table {{.Name}}" | grep -q "^${volume}$"; then
            existing_volumes+=("$volume")
            has_volumes=true
        fi
    done
    
    # Check for existing Docker network
    local has_network=false
    if docker network ls --format "table {{.Name}}" | grep -q "^n8n_network$"; then
        has_network=true
    fi
    
    # Return results
    if [ "$has_containers" = true ] || [ "$has_config" = true ] || [ "$has_volumes" = true ] || [ "$has_network" = true ]; then
        echo "EXISTING_INSTALLATION_FOUND"
        
        # Display what was found
        echo
        warning "🔍 Existing n8n installation detected!"
        echo
        
        if [ "$has_containers" = true ]; then
            echo "📦 Existing containers found:"
            for container in "${existing_containers[@]}"; do
                local status=$(docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep "^${container}" | awk '{print $2}')
                echo "   • $container ($status)"
            done
            echo
        fi
        
        if [ "$has_volumes" = true ]; then
            echo "💾 Existing volumes found:"
            for volume in "${existing_volumes[@]}"; do
                echo "   • $volume"
            done
            echo
        fi
        
        if [ "$has_config" = true ]; then
            echo "📁 Configuration directory exists: $SETUP_DIR"
            if [ -f "$SETUP_DIR/.env" ]; then
                echo "   • Environment file found"
            fi
            if [ -f "$SETUP_DIR/docker-compose.yml" ]; then
                echo "   • Docker Compose file found"
            fi
            echo
        fi
        
        if [ "$has_network" = true ]; then
            echo "🌐 Docker network 'n8n_network' exists"
            echo
        fi
        
        return 0
    else
        echo "NO_EXISTING_INSTALLATION"
        return 1
    fi
}

prompt_cleanup_choice() {
    echo "⚠️  An existing n8n installation was detected."
    echo
    echo "Choose an option:"
    echo "1) Keep existing installation and exit (k/keep)"
    echo "2) Clean everything and start fresh (c/clean)"
    echo "3) Exit without changes (e/exit)"
    echo
    
    while true; do
        if [ -t 0 ]; then
            echo -n "Choose an option [k/c/e]: "
            read -r choice
        else
            echo "Non-interactive mode: keeping existing installation"
            return 1
        fi
        
        case "${choice,,}" in
            k|keep)
                info "Keeping existing installation. Exiting..."
                exit 0
                ;;
            c|clean)
                warning "⚠️  This will permanently delete all n8n data, containers, and configuration!"
                echo -n "Are you sure? Type 'yes' to confirm: "
                read -r confirm
                if [ "$confirm" = "yes" ]; then
                    return 0
                else
                    info "Cleanup cancelled. Exiting..."
                    exit 0
                fi
                ;;
            e|exit)
                info "Exiting without changes..."
                exit 0
                ;;
            *)
                echo "Invalid choice. Please enter 'k' (keep), 'c' (clean), or 'e' (exit)"
                ;;
        esac
    done
}

cleanup_containers() {
    cleanup_info "Stopping and removing containers..."
    
    local containers=("n8n" "qdrant" "dozzle" "portainer" "caddy")
    
    for container in "${containers[@]}"; do
        if docker ps -q -f name="^${container}$" | grep -q .; then
            cleanup_info "Stopping container: $container"
            docker stop "$container" >/dev/null 2>&1 || true
        fi
        
        if docker ps -aq -f name="^${container}$" | grep -q .; then
            cleanup_info "Removing container: $container"
            docker rm "$container" >/dev/null 2>&1 || true
        fi
    done
}

cleanup_volumes() {
    cleanup_info "Removing Docker volumes..."
    
    local volumes=("n8n_data" "qdrant_data" "portainer_data" "caddy_data" "caddy_config")
    
    for volume in "${volumes[@]}"; do
        if docker volume ls -q | grep -q "^${volume}$"; then
            cleanup_info "Removing volume: $volume"
            docker volume rm "$volume" >/dev/null 2>&1 || true
        fi
    done
}

cleanup_network() {
    cleanup_info "Removing Docker network..."
    
    if docker network ls -q -f name="^n8n_network$" | grep -q .; then
        cleanup_info "Removing network: n8n_network"
        docker network rm n8n_network >/dev/null 2>&1 || true
    fi
}

cleanup_configuration() {
    cleanup_info "Removing configuration files..."
    
    if [ -d "$SETUP_DIR" ]; then
        cleanup_info "Removing directory: $SETUP_DIR"
        rm -rf "$SETUP_DIR" || true
    fi
}

cleanup_images() {
    cleanup_info "Cleaning up unused Docker images..."
    
    # Remove dangling images
    docker image prune -f >/dev/null 2>&1 || true
    
    # Optionally remove n8n stack images (commented out to preserve for reinstall)
    # local images=("n8nio/n8n" "qdrant/qdrant" "caddy" "amir20/dozzle" "portainer/portainer-ce")
    # for image in "${images[@]}"; do
    #     docker rmi $(docker images -q "$image") >/dev/null 2>&1 || true
    # done
}

perform_cleanup() {
    cleanup_info "🧹 Starting cleanup process..."
    echo
    
    # Stop and remove containers
    cleanup_containers
    
    # Remove volumes (this deletes all data!)
    cleanup_volumes
    
    # Remove network
    cleanup_network
    
    # Remove configuration files
    cleanup_configuration
    
    # Clean up unused images
    cleanup_images
    
    success "✅ Cleanup completed successfully!"
    echo
    info "All n8n installation components have been removed."
    info "You can now proceed with a fresh installation."
    echo
}

check_and_handle_existing_installation() {
    info "🔍 Checking for existing n8n installation..."
    
    if detect_existing_installation >/dev/null 2>&1; then
        # Show detection results
        detect_existing_installation
        
        # Prompt user for action
        prompt_cleanup_choice
        
        # If we reach here, user chose to clean
        perform_cleanup
    else
        info "✅ No existing installation found. Proceeding with fresh installation..."
    fi
}

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

# --- Check Dependencies with Retry ---
check_system_requirements_impl() {
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
    
    info "VPS requirements met: ${memory_gb}GB RAM, ${disk_gb}GB disk, ${cpu_cores} CPU cores"
}

check_system_requirements() {
    retry_with_user_prompt "System Requirements Check" check_system_requirements_impl
}

# --- Install Dependencies with Retry ---
install_dependencies_impl() {
    system_operation "apt_update"
    system_operation "apt_install" curl wget ufw htop openssl
}

install_dependencies() {
    retry_with_user_prompt "Package Installation" install_dependencies_impl
}

# --- Install Docker with Retry ---
install_docker_impl() {
    if docker --version >/dev/null 2>&1; then
        info "Docker already installed: $(docker --version)"
        return 0
    fi
    
    info "Downloading and installing Docker..."
    safe_curl "https://get.docker.com" | sh
    
    system_operation "systemctl_enable" docker
    system_operation "systemctl_start" docker
    
    # Wait for Docker to be ready and verify
    sleep 5
    docker --version >/dev/null 2>&1
}

install_docker() {
    retry_with_user_prompt "Docker Installation" install_docker_impl
}

# --- Check Docker Compose with Retry ---
check_docker_compose_impl() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
        info "Using Docker Compose: $(docker compose version --short 2>/dev/null || echo 'installed')"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
        info "Using legacy docker-compose"
    else
        return 1
    fi
}

check_docker_compose() {
    retry_with_user_prompt "Docker Compose Detection" check_docker_compose_impl
}

# --- Generate Configuration with Retry ---
generate_credentials_impl() {
    file_operation "mkdir" "$SETUP_DIR"
    
    # Generate secure password
    local n8n_password=$(openssl rand -base64 16 | tr -d "=+/\"'" | cut -c1-16)
    
    if [ ${#n8n_password} -lt 8 ]; then
        return 1
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
    
    file_operation "chmod" 600 "${SETUP_DIR}/.env"
}

generate_credentials() {
    retry_with_user_prompt "Credential Generation" generate_credentials_impl
}

# --- Create Docker Compose with Retry ---
create_docker_compose_impl() {
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
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - n8n_network
    environment:
      - DOZZLE_NO_ANALYTICS=true
    read_only: true
    tmpfs:
      - /tmp
EOF

    # Add Dozzle ports only if no domain (will be routed through Caddy if domain exists)
    if [ -z "$N8N_DOMAIN" ]; then
        cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'
    ports:
      - "8080:8080"
EOF
    fi

    # Add Portainer
    cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'

  portainer:
    image: portainer/portainer-ce:${PORTAINER_VERSION}
    container_name: portainer
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - n8n_network
    command: --admin-password='$$2y$$10$$TQQOBo/MZuOzKhLhbKmAI.XMJqYa7/zZvvODNfaAwtdu7QnOjrPgK'
EOF

    # Add Portainer ports only if no domain (will be routed through Caddy if domain exists)
    if [ -z "$N8N_DOMAIN" ]; then
        cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'
    ports:
      - "9000:9000"
EOF
    fi

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
# Main domain configuration with path-based routing
${N8N_DOMAIN} {
    # n8n on root path
    reverse_proxy n8n:5678 {
        health_uri /healthz
        health_interval 30s
        health_timeout 5s
    }
    
    # Portainer on /portainer path
    handle_path /portainer* {
        reverse_proxy portainer:9000
    }
    
    # Dozzle on /dozzle path  
    handle_path /dozzle* {
        reverse_proxy dozzle:8080
    }
    
    # Qdrant on /qdrant path
    handle_path /qdrant* {
        reverse_proxy qdrant:6333
    }
    
    # Security headers
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options SAMEORIGIN
        X-XSS-Protection "1; mode=block"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }
    
    # Enable compression
    encode gzip
    
    # Enable automatic HTTPS
    tls {
        protocols tls1.2 tls1.3
    }
    
    # Logging for debugging SSL issues
    log {
        output file /var/log/caddy/access.log
        format json
    }
}

# Force HTTPS redirect
http://${N8N_DOMAIN} {
    redir https://{host}{uri} permanent
}
EOF
    fi

    success "Docker Compose configuration created"
}

create_docker_compose() {
    retry_with_user_prompt "Docker Compose Creation" create_docker_compose_impl
}

# --- Setup Firewall with Retry ---
setup_firewall_impl() {
    if ! command -v ufw >/dev/null 2>&1; then
        warning "UFW not available"
        return 0
    fi
    
    system_operation "ufw_reset"
    ufw default deny incoming
    ufw default allow outgoing
    
    ufw allow ssh
    ufw allow 80/tcp   # HTTP (redirects to HTTPS)
    ufw allow 443/tcp  # HTTPS
    
    # Only allow direct port access if no domain is configured
    if [ -z "${N8N_DOMAIN:-}" ]; then
        ufw allow 5678/tcp  # n8n direct access
        ufw allow 6333/tcp  # Qdrant direct access
        ufw allow 8080/tcp  # Dozzle direct access
        ufw allow 9000/tcp  # Portainer direct access
    fi
    
    system_operation "ufw_enable"
}

setup_firewall() {
    retry_with_user_prompt "Firewall Configuration" setup_firewall_impl
}

# --- Deploy Services with Retry ---
deploy_services_impl() {
    cd "$SETUP_DIR"
    
    # Create directories with proper permissions
    file_operation "mkdir" data/n8n data/qdrant data/portainer
    file_operation "chown" 1000:1000 data/n8n data/qdrant
    
    # Pull latest images before starting services
    info "Pulling latest container images..."
    $DOCKER_COMPOSE_CMD pull
    
    # Start services
    docker_operation "compose_up"
    
    # Wait for services to initialize
    sleep 45
    
    # Enhanced health check with retry
    local wait_count=0
    local max_wait=300  # 5 minutes total
    while [ $wait_count -lt $max_wait ]; do
        if docker_operation "health_check" n8n "http://localhost:5678/healthz"; then
            info "n8n is healthy!"
            break
        fi
        
        if [ $wait_count -ge $max_wait ]; then
            return 1
        fi
        
        echo "Waiting for n8n to be ready... ($wait_count/$max_wait seconds)"
        sleep 5
        wait_count=$((wait_count + 5))
    done
    
    # Verify container status
    $DOCKER_COMPOSE_CMD ps
}

deploy_services() {
    retry_with_user_prompt "Service Deployment" deploy_services_impl
}

# --- Create Management Script with Retry ---
create_management_script_impl() {
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
    file_operation "chmod" +x "${SETUP_DIR}/manage.sh"
}

create_management_script() {
    retry_with_user_prompt "Management Script Creation" create_management_script_impl
}

# --- Show Results with Retry ---
show_results_impl() {
    local public_ip
    if ! public_ip=$(safe_curl "ifconfig.me"); then
        public_ip="109.123.247.217"
    fi
    
    # Load credentials
    source "${SETUP_DIR}/.env"
    
    echo
    echo "🎉======================================================"
    echo "   n8n Production Stack Deployed Successfully!"
    echo "======================================================"
    echo
    
    if [ -n "${N8N_DOMAIN:-}" ]; then
        echo "🌐 n8n: https://${N8N_DOMAIN}"
        echo "🔧 Qdrant Vector DB: https://${N8N_DOMAIN}/qdrant"
        echo "📊 Container Logs: https://${N8N_DOMAIN}/dozzle (Dozzle)"
        echo "🐳 Docker Management: https://${N8N_DOMAIN}/portainer (Portainer)"
        echo "   └─ Username: admin | Password: admin123456"
        echo "⚠️  Ensure ${N8N_DOMAIN} DNS points to ${public_ip}"
        echo "🔒 SSL Certificate: Automatic via Let's Encrypt"
    else
        echo "🌐 n8n: http://${public_ip}:5678"
        echo "🔧 Qdrant Vector DB: http://${public_ip}:6333"
        echo "📊 Container Logs: http://${public_ip}:8080 (Dozzle)"
        echo "🐳 Docker Management: http://${public_ip}:9000 (Portainer)"
        echo "   └─ Username: admin | Password: admin123456"
    fi
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
    echo "   ✓ Comprehensive retry mechanisms for reliability"
    echo "   ✓ Intelligent cleanup system for existing installations"
    echo
}

show_results() {
    retry_with_user_prompt "Results Display" show_results_impl
}

# --- Main Function ---
main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Run as root: sudo $0"
    fi
    
    info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}..."
    
    # Check for existing installation and handle cleanup if needed
    check_and_handle_existing_installation
    
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
