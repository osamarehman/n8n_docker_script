#!/bin/bash

# ==============================================================================
# Common Utilities for n8n Modular Stack
# Shared functions, retry mechanisms, and system operations
# ==============================================================================

set -euo pipefail

# --- Global Configuration ---
readonly SCRIPT_VERSION="3.0.0-modular"
readonly MIN_RAM_GB=2
readonly MIN_DISK_GB=8
readonly SETUP_DIR="/opt/n8n-stack"
readonly SHARED_NETWORK="n8n_network"

# Retry configuration
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5
readonly NETWORK_TIMEOUT=30

# Latest versions (always pull latest)
export N8N_VERSION="latest"
export QDRANT_VERSION="latest"
export CADDY_VERSION="latest"
export WATCHTOWER_VERSION="latest"
export PORTAINER_VERSION="latest"

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
        if [ -t 0 ] || [ "${FORCE_INTERACTIVE:-false}" = "true" ]; then
            if [ -c /dev/tty ]; then
                echo -n "Choose an option [r/s/e]: " > /dev/tty
                read -r choice < /dev/tty
            else
                echo -n "Choose an option [r/s/e]: "
                read -r choice
            fi
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

# --- Docker Operations with Retry ---
docker_operation() {
    local operation="$1"
    shift
    
    case "$operation" in
        "pull")
            docker pull "$@"
            ;;
        "compose_up")
            ${DOCKER_COMPOSE_CMD:-docker compose} up -d "$@"
            ;;
        "compose_down")
            ${DOCKER_COMPOSE_CMD:-docker compose} down "$@"
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

# --- Docker Network Management ---
ensure_docker_network() {
    if ! docker network ls --format "table {{.Name}}" | grep -q "^${SHARED_NETWORK}$"; then
        info "Creating shared Docker network: $SHARED_NETWORK"
        docker network create "$SHARED_NETWORK" --driver bridge
        success "Docker network created: $SHARED_NETWORK"
    else
        info "Docker network already exists: $SHARED_NETWORK"
    fi
}

# --- System Requirements Check ---
check_system_requirements_impl() {
    local memory_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    if [ $memory_gb -lt $MIN_RAM_GB ]; then
        warning "Insufficient RAM: ${memory_gb}GB. Minimum recommended: ${MIN_RAM_GB}GB. Proceeding anyway..."
    fi
    
    local disk_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    if [ $disk_gb -lt $MIN_DISK_GB ]; then
        warning "Insufficient disk space: ${disk_gb}GB. Minimum required: ${MIN_DISK_GB}GB. Proceeding anyway..."
    fi
    
    local cpu_cores=$(nproc)
    if [ $cpu_cores -lt 1 ]; then
        warning "No CPU cores detected. Proceeding anyway..."
    fi
    
    info "VPS requirements met: ${memory_gb}GB RAM, ${disk_gb}GB disk, ${cpu_cores} CPU cores"
}

check_system_requirements() {
    retry_with_user_prompt "System Requirements Check" check_system_requirements_impl
}

# --- Docker Installation ---
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

# --- Docker Compose Check ---
check_docker_compose_impl() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
        export DOCKER_COMPOSE_CMD
        info "Using Docker Compose: $(docker compose version --short 2>/dev/null || echo 'installed')"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker-compose"
        export DOCKER_COMPOSE_CMD
        info "Using legacy docker-compose"
    else
        return 1
    fi
}

check_docker_compose() {
    retry_with_user_prompt "Docker Compose Detection" check_docker_compose_impl
}

# --- Install System Dependencies ---
install_dependencies_impl() {
    system_operation "apt_update"
    system_operation "apt_install" curl wget ufw htop openssl
}

install_dependencies() {
    retry_with_user_prompt "Package Installation" install_dependencies_impl
}

# --- Domain Validation ---
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]]; then
        error "Invalid domain format: $domain"
    fi
}

# --- Generate Secure Password ---
generate_password() {
    local length="${1:-16}"
    openssl rand -base64 "$length" | tr -d "=+/\"'" | cut -c1-"$length"
}

# --- Get Public IP ---
get_public_ip() {
    local public_ip
    if ! public_ip=$(safe_curl "ifconfig.me"); then
        if ! public_ip=$(safe_curl "ipv4.icanhazip.com"); then
            public_ip="your-server-ip"
        fi
    fi
    echo "$public_ip"
}

# --- Load Environment Configuration ---
load_env_config() {
    local env_file="${SETUP_DIR}/.env"
    if [ -f "$env_file" ]; then
        set -a
        source "$env_file"
        set +a
        info "Loaded configuration from $env_file"
    else
        warning "Environment file not found: $env_file"
    fi
}

# --- Container Health Check ---
wait_for_container_health() {
    local container_name="$1"
    local health_url="$2"
    local max_wait="${3:-300}"
    local wait_count=0
    
    info "Waiting for $container_name to be healthy..."
    
    while [ $wait_count -lt $max_wait ]; do
        if docker_operation "health_check" "$container_name" "$health_url"; then
            success "$container_name is healthy!"
            return 0
        fi
        
        if [ $wait_count -ge $max_wait ]; then
            error "$container_name failed to become healthy within ${max_wait} seconds"
        fi
        
        echo "Waiting for $container_name to be ready... ($wait_count/$max_wait seconds)"
        sleep 5
        wait_count=$((wait_count + 5))
    done
}

# --- Root Permission Check ---
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root. Please use: sudo $0"
    fi
}

# --- Component Status Check ---
is_component_installed() {
    local component="$1"
    docker ps -a --format "table {{.Names}}" | grep -q "^${component}$"
}

# --- Configuration Directory Setup ---
ensure_setup_directory() {
    file_operation "mkdir" "$SETUP_DIR"
    info "Setup directory ready: $SETUP_DIR"
}