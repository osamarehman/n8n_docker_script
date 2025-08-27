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
readonly SCRIPT_VERSION="2.5.2-config-optimized"
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

# Export variables for Docker Compose
export N8N_VERSION
export QDRANT_VERSION
export CADDY_VERSION
export DOZZLE_VERSION
export PORTAINER_VERSION

# Initialize variables
N8N_DOMAIN="${N8N_DOMAIN:-}"
N8N_USER="${N8N_USER:-}"
DOCKER_COMPOSE_CMD=""
FORCE_INTERACTIVE="${FORCE_INTERACTIVE:-false}"
CLEANUP_ACTION="${CLEANUP_ACTION:-}"

# Optional components configuration
INSTALL_FFMPEG="${INSTALL_FFMPEG:-}"
INSTALL_PORTAINER="${INSTALL_PORTAINER:-}"
INSTALL_DOZZLE="${INSTALL_DOZZLE:-}"
INSTALL_QDRANT="${INSTALL_QDRANT:-}"

# Subdomain configuration
N8N_SUBDOMAIN="${N8N_SUBDOMAIN:-n8n}"
PORTAINER_SUBDOMAIN="${PORTAINER_SUBDOMAIN:-portainer}"
DOZZLE_SUBDOMAIN="${DOZZLE_SUBDOMAIN:-dozzle}"
QDRANT_SUBDOMAIN="${QDRANT_SUBDOMAIN:-qdrant}"

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
        if [ -t 0 ] || [ "$FORCE_INTERACTIVE" = "true" ]; then
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
    local containers=("n8n" "caddy")
    if [ "${INSTALL_QDRANT,,}" = "yes" ] || [ -z "$INSTALL_QDRANT" ]; then
        containers+=("qdrant")
    fi
    if [ "${INSTALL_DOZZLE,,}" = "yes" ] || [ -z "$INSTALL_DOZZLE" ]; then
        containers+=("dozzle")
    fi
    if [ "${INSTALL_PORTAINER,,}" = "yes" ] || [ -z "$INSTALL_PORTAINER" ]; then
        containers+=("portainer")
    fi
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
    local volumes=("n8n_data" "caddy_data" "caddy_config")
    if [ "${INSTALL_QDRANT,,}" = "yes" ] || [ -z "$INSTALL_QDRANT" ]; then
        volumes+=("qdrant_data")
    fi
    if [ "${INSTALL_PORTAINER,,}" = "yes" ] || [ -z "$INSTALL_PORTAINER" ]; then
        volumes+=("portainer_data")
    fi
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
    # Check if cleanup action is pre-defined via environment variable
    if [ -n "$CLEANUP_ACTION" ]; then
        case "${CLEANUP_ACTION,,}" in
            keep|k)
                info "Pre-configured: Keeping existing installation. Exiting..."
                exit 0
                ;;
            clean|c)
                warning "Pre-configured: Cleaning everything and starting fresh..."
                return 0
                ;;
            exit|e)
                info "Pre-configured: Exiting without changes..."
                exit 0
                ;;
            *)
                warning "Invalid CLEANUP_ACTION value: $CLEANUP_ACTION. Using interactive mode."
                ;;
        esac
    fi
    
    echo "⚠️  An existing n8n installation was detected."
    echo
    echo "Choose an option:"
    echo "1) Keep existing installation and exit (k/keep)"
    echo "2) Clean everything and start fresh (c/clean)"
    echo "3) Exit without changes (e/exit)"
    echo
    
    while true; do
        # Force interactive mode if FORCE_INTERACTIVE is true, or if we have a TTY, or if we can access /dev/tty
        if [ "$FORCE_INTERACTIVE" = "true" ] || [ -t 0 ] || [ -c /dev/tty ]; then
            if [ -c /dev/tty ]; then
                echo -n "Choose an option [k/c/e]: " > /dev/tty
                read -r choice < /dev/tty
            else
                echo -n "Choose an option [k/c/e]: "
                read -r choice
            fi
        else
            echo "Non-interactive mode: keeping existing installation"
            echo "💡 Tip: Use CLEANUP_ACTION=clean to force cleanup, or FORCE_INTERACTIVE=true for interactive mode"
            return 1
        fi
        
        case "${choice,,}" in
            k|keep)
                info "Keeping existing installation. Exiting..."
                exit 0
                ;;
            c|clean)
                warning "⚠️  This will permanently delete all n8n data, containers, and configuration!"
                if [ -c /dev/tty ]; then
                    echo -n "Are you sure? Type 'yes' to confirm: " > /dev/tty
                    read -r confirm < /dev/tty
                else
                    echo -n "Are you sure? Type 'yes' to confirm: "
                    read -r confirm
                fi
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
    
    local containers=("n8n" "caddy")
    if [ "${INSTALL_QDRANT,,}" = "yes" ] || [ -z "$INSTALL_QDRANT" ]; then
        containers+=("qdrant")
    fi
    if [ "${INSTALL_DOZZLE,,}" = "yes" ] || [ -z "$INSTALL_DOZZLE" ]; then
        containers+=("dozzle")
    fi
    if [ "${INSTALL_PORTAINER,,}" = "yes" ] || [ -z "$INSTALL_PORTAINER" ]; then
        containers+=("portainer")
    fi
    
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
    
    local volumes=("n8n_data" "caddy_data" "caddy_config")
    if [ "${INSTALL_QDRANT,,}" = "yes" ] || [ -z "$INSTALL_QDRANT" ]; then
        volumes+=("qdrant_data")
    fi
    if [ "${INSTALL_PORTAINER,,}" = "yes" ] || [ -z "$INSTALL_PORTAINER" ]; then
        volumes+=("portainer_data")
    fi
    
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
    
    # Check for auto mode or non-interactive flag
    for arg in "$@"; do
        case "$arg" in
            "--auto"|"--non-interactive")
                auto_mode=true
                ;;
            "--force-interactive")
                FORCE_INTERACTIVE=true
                ;;
        esac
    done
    
    # Interactive by default unless explicitly set to non-interactive
    if [ "$auto_mode" = "true" ] && [ "$FORCE_INTERACTIVE" != "true" ]; then
        non_interactive=true
    fi
    
    # Collect main domain for subdomain-based setup
    local main_domain=""
    if [ -z "$N8N_DOMAIN" ]; then
        if [ "$auto_mode" = "true" ] || [ "$non_interactive" = "true" ]; then
            info "Using IP-based access (no domain configured)"
        else
            if [ -c /dev/tty ] || [ "$FORCE_INTERACTIVE" = "true" ]; then
                echo
                info "🌐 Domain Configuration"
                echo "Enter your main domain (e.g., 'mughal.pro') for subdomain-based setup."
                echo "This will create subdomains like: n8n.mughal.pro, portainer.mughal.pro, etc."
                echo "Leave empty for IP-based access (HTTP only)."
                echo
                echo -n "Enter your main domain [leave empty for IP access]: " > /dev/tty
                read main_domain < /dev/tty || main_domain=""
            else
                info "Non-interactive mode: Using IP-based access"
            fi
        fi
    else
        # If N8N_DOMAIN is already set, extract main domain from it
        if [[ "$N8N_DOMAIN" =~ ^[^.]+\.(.+)$ ]]; then
            main_domain="${BASH_REMATCH[1]}"
        else
            main_domain="$N8N_DOMAIN"
        fi
    fi
    
    # Configure subdomains if main domain is provided
    if [ -n "$main_domain" ]; then
        # Validate main domain format
        if [[ ! "$main_domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]]; then
            warning "Domain format may be invalid: $main_domain"
        fi
        
        info "🌐 Configuring subdomain-based setup for: $main_domain"
        echo
        
        # Customize subdomains if interactive
        if [ "$auto_mode" = "false" ] && [ "$non_interactive" = "false" ]; then
            if [ -c /dev/tty ] || [ "$FORCE_INTERACTIVE" = "true" ]; then
                info "📝 Subdomain Configuration"
                echo "You can customize the subdomain names for each service:"
                echo
                
                echo -n "n8n subdomain [${N8N_SUBDOMAIN}]: " > /dev/tty
                read custom_n8n < /dev/tty || custom_n8n=""
                N8N_SUBDOMAIN="${custom_n8n:-$N8N_SUBDOMAIN}"
                
                echo -n "Portainer subdomain [${PORTAINER_SUBDOMAIN}]: " > /dev/tty
                read custom_portainer < /dev/tty || custom_portainer=""
                PORTAINER_SUBDOMAIN="${custom_portainer:-$PORTAINER_SUBDOMAIN}"
                
                echo -n "Dozzle (logs) subdomain [${DOZZLE_SUBDOMAIN}]: " > /dev/tty
                read custom_dozzle < /dev/tty || custom_dozzle=""
                DOZZLE_SUBDOMAIN="${custom_dozzle:-$DOZZLE_SUBDOMAIN}"
                
                echo -n "Qdrant (vector DB) subdomain [${QDRANT_SUBDOMAIN}]: " > /dev/tty
                read custom_qdrant < /dev/tty || custom_qdrant=""
                QDRANT_SUBDOMAIN="${custom_qdrant:-$QDRANT_SUBDOMAIN}"
                
                echo
                info "📋 Subdomain Summary:"
                echo "   • n8n: ${N8N_SUBDOMAIN}.${main_domain}"
                echo "   • Portainer: ${PORTAINER_SUBDOMAIN}.${main_domain}"
                echo "   • Dozzle: ${DOZZLE_SUBDOMAIN}.${main_domain}"
                echo "   • Qdrant: ${QDRANT_SUBDOMAIN}.${main_domain}"
                echo
                
                echo -n "Confirm these subdomains? [Y/n]: " > /dev/tty
                read confirm < /dev/tty || confirm=""
                if [[ "${confirm,,}" =~ ^(n|no)$ ]]; then
                    info "Subdomain configuration cancelled. Exiting..."
                    exit 0
                fi
            fi
        fi
        
        # Set N8N_DOMAIN to the full subdomain
        N8N_DOMAIN="${N8N_SUBDOMAIN}.${main_domain}"
        
        # DNS Warning
        echo
        warning "⚠️  DNS CONFIGURATION REQUIRED"
        echo "Before proceeding, you MUST configure these DNS A records:"
        echo
        echo "   ${N8N_SUBDOMAIN}.${main_domain} → [YOUR_SERVER_IP]"
        if [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
            echo "   ${PORTAINER_SUBDOMAIN}.${main_domain} → [YOUR_SERVER_IP]"
        fi
        if [ "${INSTALL_DOZZLE,,}" = "yes" ]; then
            echo "   ${DOZZLE_SUBDOMAIN}.${main_domain} → [YOUR_SERVER_IP]"
        fi
        if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
            echo "   ${QDRANT_SUBDOMAIN}.${main_domain} → [YOUR_SERVER_IP]"
        fi
        echo
        echo "💡 All subdomains should point to the same server IP address."
        echo "💡 DNS propagation may take 5-60 minutes depending on your provider."
        echo "💡 SSL certificates will be automatically generated via Let's Encrypt."
        echo
        
        if [ "$auto_mode" = "false" ] && [ "$non_interactive" = "false" ]; then
            if [ -c /dev/tty ] || [ "$FORCE_INTERACTIVE" = "true" ]; then
                echo -n "Have you configured the DNS records? [y/N]: " > /dev/tty
                read dns_confirm < /dev/tty || dns_confirm=""
                if [[ ! "${dns_confirm,,}" =~ ^(y|yes)$ ]]; then
                    warning "Please configure DNS records first, then run the script again."
                    exit 0
                fi
            fi
        else
            warning "Auto mode: Assuming DNS records are configured"
        fi
        
        info "🌐 Domain-based setup: $N8N_DOMAIN (HTTPS enabled with subdomains)"
    else
        info "🌐 IP-based setup (HTTP only)"
    fi
    
    # Collect N8N_USER with proper email validation
    if [ -z "$N8N_USER" ]; then
        if [ "$auto_mode" = "true" ] || [ "$non_interactive" = "true" ]; then
            N8N_USER="admin@example.com"
            info "Using default username 'admin@example.com'"
        else
            if [ -c /dev/tty ] || [ "$FORCE_INTERACTIVE" = "true" ]; then
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
    
    # Collect optional component preferences
    if [ "$auto_mode" = "false" ] && [ "$non_interactive" = "false" ]; then
        if [ -c /dev/tty ] || [ "$FORCE_INTERACTIVE" = "true" ]; then
            echo
            info "📦 Optional Components"
            echo "Choose which additional components to install:"
            echo
            
            # FFmpeg and yt-dlp for media processing
            if [ -z "$INSTALL_FFMPEG" ]; then
                echo -n "Install FFmpeg + yt-dlp for video/audio processing and downloading? (recommended for media workflows) [Y/n]: " > /dev/tty
                read ffmpeg_choice < /dev/tty || ffmpeg_choice=""
                if [[ "${ffmpeg_choice,,}" =~ ^(n|no)$ ]]; then
                    INSTALL_FFMPEG="no"
                    info "❌ FFmpeg and yt-dlp will be skipped"
                else
                    INSTALL_FFMPEG="yes"
                    info "✅ FFmpeg and yt-dlp will be included in n8n container"
                fi
            fi
            
            # Qdrant Vector Database
            if [ -z "$INSTALL_QDRANT" ]; then
                echo -n "Install Qdrant vector database? (recommended for AI workflows) [Y/n]: " > /dev/tty
                read qdrant_choice < /dev/tty || qdrant_choice=""
                if [[ "${qdrant_choice,,}" =~ ^(n|no)$ ]]; then
                    INSTALL_QDRANT="no"
                    info "❌ Qdrant vector database will be skipped"
                else
                    INSTALL_QDRANT="yes"
                    info "✅ Qdrant vector database will be installed"
                fi
            fi
            
            # Portainer Docker Management
            if [ -z "$INSTALL_PORTAINER" ]; then
                echo -n "Install Portainer for Docker management? [Y/n]: " > /dev/tty
                read portainer_choice < /dev/tty || portainer_choice=""
                if [[ "${portainer_choice,,}" =~ ^(n|no)$ ]]; then
                    INSTALL_PORTAINER="no"
                    info "❌ Portainer will be skipped"
                else
                    INSTALL_PORTAINER="yes"
                    info "✅ Portainer will be installed"
                fi
            fi
            
            # Dozzle Log Viewer
            if [ -z "$INSTALL_DOZZLE" ]; then
                echo -n "Install Dozzle for container log viewing? [Y/n]: " > /dev/tty
                read dozzle_choice < /dev/tty || dozzle_choice=""
                if [[ "${dozzle_choice,,}" =~ ^(n|no)$ ]]; then
                    INSTALL_DOZZLE="no"
                    info "❌ Dozzle will be skipped"
                else
                    INSTALL_DOZZLE="yes"
                    info "✅ Dozzle will be installed"
                fi
            fi
            
            echo
        fi
    else
        # Auto mode - install all optional components by default
        INSTALL_FFMPEG="${INSTALL_FFMPEG:-yes}"
        INSTALL_QDRANT="${INSTALL_QDRANT:-yes}"
        INSTALL_PORTAINER="${INSTALL_PORTAINER:-yes}"
        INSTALL_DOZZLE="${INSTALL_DOZZLE:-yes}"
        info "Auto mode: Installing all optional components"
    fi
    
    # Set defaults for any unset values
    INSTALL_FFMPEG="${INSTALL_FFMPEG:-yes}"
    INSTALL_QDRANT="${INSTALL_QDRANT:-yes}"
    INSTALL_PORTAINER="${INSTALL_PORTAINER:-yes}"
    INSTALL_DOZZLE="${INSTALL_DOZZLE:-yes}"
    
    # Configuration summary
    echo
    info "📋 Configuration Summary:"
    info "   Domain: ${N8N_DOMAIN:-"IP-based access"}"
    info "   Username: $N8N_USER"
    info "   Database: SQLite (file-based, no PostgreSQL)"
    info "   HTTPS: ${N8N_DOMAIN:+Enabled}${N8N_DOMAIN:-Disabled}"
    info "   Optional Components:"
    info "      • FFmpeg + yt-dlp Media Processing: ${INSTALL_FFMPEG}"
    info "      • Qdrant Vector DB: ${INSTALL_QDRANT}"
    info "      • Portainer Management: ${INSTALL_PORTAINER}"
    info "      • Dozzle Log Viewer: ${INSTALL_DOZZLE}"
    echo
}

# --- Check Dependencies with Retry ---
check_system_requirements_impl() {
    local memory_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    if [ $memory_gb -lt $MIN_RAM_GB ]; then
        warning "Insufficient RAM: ${memory_gb}GB. Minimum recommended: ${MIN_RAM_GB}GB. Proceeding anyway..."
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
    
    # Generate secure passwords
    local n8n_password=$(openssl rand -base64 16 | tr -d "=+/\"'" | cut -c1-16)
    local qdrant_api_key=$(openssl rand -base64 32 | tr -d "=+/\"'" | cut -c1-32)
    
    if [ ${#n8n_password} -lt 8 ] || [ ${#qdrant_api_key} -lt 16 ]; then
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

# Qdrant Configuration
QDRANT_API_KEY=${qdrant_api_key}

# Domain Configuration
${N8N_DOMAIN:+N8N_DOMAIN=${N8N_DOMAIN}}

# Subdomain Configuration
${N8N_DOMAIN:+N8N_SUBDOMAIN=${N8N_SUBDOMAIN}}
${N8N_DOMAIN:+PORTAINER_SUBDOMAIN=${PORTAINER_SUBDOMAIN}}
${N8N_DOMAIN:+DOZZLE_SUBDOMAIN=${DOZZLE_SUBDOMAIN}}
${N8N_DOMAIN:+QDRANT_SUBDOMAIN=${QDRANT_SUBDOMAIN}}
EOF
    
    file_operation "chmod" 600 "${SETUP_DIR}/.env"
}

generate_credentials() {
    retry_with_user_prompt "Credential Generation" generate_credentials_impl
}

# --- Create Custom n8n Dockerfile with FFmpeg ---
create_custom_n8n_dockerfile() {
    if [ "${INSTALL_FFMPEG,,}" = "yes" ]; then
        info "Creating custom n8n Dockerfile with FFmpeg and yt-dlp..."
        
        cat > "${SETUP_DIR}/Dockerfile.n8n" << 'EOF'
# Use the official n8n image as base
FROM n8nio/n8n:latest

# Switch to root to install packages
USER root

# Install Python3, pip, FFmpeg, and other dependencies using Alpine package manager
RUN apk add --no-cache \
    ffmpeg \
    python3 \
    py3-pip \
    && pip3 install --no-cache-dir --break-system-packages yt-dlp

# Switch back to the default user 'node'
USER node
EOF
        
        # Build the custom image
        info "Building custom n8n image with FFmpeg and yt-dlp..."
        cd "$SETUP_DIR"
        docker build -f Dockerfile.n8n -t n8n-with-media:latest . || {
            error "Failed to build custom n8n image with FFmpeg and yt-dlp"
        }
        
        # Set the custom image name to use in docker-compose
        N8N_CUSTOM_IMAGE="n8n-with-media:latest"
        
        success "Custom n8n image with FFmpeg and yt-dlp created successfully"
    else
        # Use the standard n8n image
        N8N_CUSTOM_IMAGE="n8nio/n8n:\${N8N_VERSION}"
    fi
}

# --- Create Docker Compose with Retry ---
create_docker_compose_impl() {
    # Use the appropriate n8n image (custom with media tools or standard)
    local n8n_image_line
    if [ "${INSTALL_FFMPEG,,}" = "yes" ]; then
        n8n_image_line="    image: n8n-with-media:latest"
    else
        n8n_image_line="    image: n8nio/n8n:\${N8N_VERSION}"
    fi
    
    cat > "${SETUP_DIR}/docker-compose.yml" << EOF
services:
  n8n:
$n8n_image_line
    container_name: n8n
    restart: unless-stopped
    user: "1000:1000"
    environment:
      - TZ=\${TZ}
      # Using SQLite instead of PostgreSQL
      - DB_TYPE=sqlite
      - DB_SQLITE_VACUUM_ON_STARTUP=true
      - DB_SQLITE_POOL_SIZE=5
      # Security and performance improvements
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_PROXY_HOPS=1
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

    # Add Qdrant service conditionally
    if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
        cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'

  qdrant:
    image: qdrant/qdrant:${QDRANT_VERSION}
    container_name: qdrant
    restart: unless-stopped
    environment:
      - QDRANT__SERVICE__API_KEY=${QDRANT_API_KEY}
    volumes:
      - qdrant_data:/qdrant/storage
      - ./qdrant-config.yaml:/qdrant/config/production.yaml:ro
    networks:
      - n8n_network
EOF

        # Add Qdrant ports if no domain
        if [ -z "$N8N_DOMAIN" ]; then
            cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'
    ports:
      - "6333:6333"
EOF
        fi
    fi

    # Add Dozzle (logs viewer) conditionally
    if [ "${INSTALL_DOZZLE,,}" = "yes" ]; then
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
    fi

    # Add Portainer conditionally
    if [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
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
EOF

        # Add Portainer ports only if no domain (will be routed through Caddy if domain exists)
        if [ -z "$N8N_DOMAIN" ]; then
            cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'
    ports:
      - "9000:9000"
EOF
        fi
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
EOF

    # Add volumes conditionally based on installed services
    if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
        cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'
  qdrant_data:
EOF
    fi

    if [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
        cat >> "${SETUP_DIR}/docker-compose.yml" << 'EOF'
  portainer_data:
EOF
    fi

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

    # Create Caddyfile and Qdrant config if domain provided
    if [ -n "$N8N_DOMAIN" ]; then
        # Extract root domain from N8N_DOMAIN (e.g., ai.mughal.pro -> mughal.pro)
        local root_domain
        if [[ "$N8N_DOMAIN" =~ ^[^.]+\.(.+)$ ]]; then
            root_domain="${BASH_REMATCH[1]}"
        else
            root_domain="$N8N_DOMAIN"
        fi
        
        cat > "${SETUP_DIR}/Caddyfile" << EOF
# Main domain - n8n
${N8N_DOMAIN} {
    reverse_proxy n8n:5678 {
        health_uri /healthz
        health_interval 30s
        health_timeout 5s
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
    
    encode gzip
    
    tls {
        protocols tls1.2 tls1.3
    }
    
    log {
        output file /var/log/caddy/access.log
        format json
    }
}

EOF

        # Add Portainer subdomain conditionally
        if [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
            cat >> "${SETUP_DIR}/Caddyfile" << EOF
# Portainer subdomain
${PORTAINER_SUBDOMAIN}.${root_domain} {
    reverse_proxy portainer:9000
    
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options SAMEORIGIN
        X-XSS-Protection "1; mode=block"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }
    
    encode gzip
    
    tls {
        protocols tls1.2 tls1.3
    }
}

EOF
        fi

        # Add Dozzle subdomain conditionally
        if [ "${INSTALL_DOZZLE,,}" = "yes" ]; then
            cat >> "${SETUP_DIR}/Caddyfile" << EOF
# Dozzle subdomain
${DOZZLE_SUBDOMAIN}.${root_domain} {
    reverse_proxy dozzle:8080
    
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options SAMEORIGIN
        X-XSS-Protection "1; mode=block"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }
    
    encode gzip
    
    tls {
        protocols tls1.2 tls1.3
    }
}

EOF
        fi

        # Add Qdrant subdomain conditionally
        if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
            cat >> "${SETUP_DIR}/Caddyfile" << EOF
# Qdrant subdomain
${QDRANT_SUBDOMAIN}.${root_domain} {
    reverse_proxy qdrant:6333 {
        header_up Authorization "Bearer {\$QDRANT_API_KEY}"
    }
    
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options SAMEORIGIN
        X-XSS-Protection "1; mode=block"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }
    
    encode gzip
    
    tls {
        protocols tls1.2 tls1.3
    }
}

EOF
        fi

        # Add HTTPS redirects
        cat >> "${SETUP_DIR}/Caddyfile" << EOF
# Force HTTPS redirects
http://${N8N_DOMAIN} {
    redir https://{host}{uri} permanent
}

EOF

        if [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
            cat >> "${SETUP_DIR}/Caddyfile" << EOF
http://${PORTAINER_SUBDOMAIN}.${root_domain} {
    redir https://{host}{uri} permanent
}

EOF
        fi

        if [ "${INSTALL_DOZZLE,,}" = "yes" ]; then
            cat >> "${SETUP_DIR}/Caddyfile" << EOF
http://${DOZZLE_SUBDOMAIN}.${root_domain} {
    redir https://{host}{uri} permanent
}

EOF
        fi

        if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
            cat >> "${SETUP_DIR}/Caddyfile" << EOF
http://${QDRANT_SUBDOMAIN}.${root_domain} {
    redir https://{host}{uri} permanent
}
EOF
        fi
    fi
    
    # Create Qdrant configuration file conditionally
    if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
        cat > "${SETUP_DIR}/qdrant-config.yaml" << 'EOF'
service:
  # Enable API key authentication
  api_key: ${QDRANT_API_KEY}
  
  # HTTP settings
  http_port: 6333
  grpc_port: 6334
  
  # Enable CORS for web access
  enable_cors: true
  
  # Logging
  log_level: INFO

storage:
  # Storage settings
  storage_path: /qdrant/storage
  
  # Performance settings
  optimizers:
    deleted_threshold: 0.2
    vacuum_min_vector_number: 1000
    default_segment_number: 0
    max_segment_size_kb: 5000000
    memmap_threshold_kb: 200000
    indexing_threshold_kb: 20000
    flush_interval_sec: 5
    max_optimization_threads: 1

cluster:
  # Disable clustering for single-node setup
  enabled: false
EOF
    fi

    success "Docker Compose configuration created"
}

create_docker_compose() {
    # First create custom n8n image if FFmpeg is requested
    create_custom_n8n_dockerfile
    # Then create the docker-compose file
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
        if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
            ufw allow 6333/tcp  # Qdrant direct access
        fi
        if [ "${INSTALL_DOZZLE,,}" = "yes" ]; then
            ufw allow 8080/tcp  # Dozzle direct access
        fi
        if [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
            ufw allow 9000/tcp  # Portainer direct access
        fi
    fi
    
    system_operation "ufw_enable"
}

setup_firewall() {
    retry_with_user_prompt "Firewall Configuration" setup_firewall_impl
}

# --- Fix Qdrant Volume Permissions with Retry ---
fix_qdrant_permissions_impl() {
    info "Fixing Qdrant volume permissions for user 1000:1000..."
    
    # Create a temporary container to fix volume ownership
    docker run --rm -it \
        -v qdrant_data:/qdrant/storage \
        alpine sh -c "chown -R 1000:1000 /qdrant/storage && echo 'Permissions fixed successfully'"
    
    # Verify the permissions were set correctly
    docker run --rm \
        -v qdrant_data:/qdrant/storage \
        alpine sh -c "ls -la /qdrant/storage"
}

fix_qdrant_permissions() {
    retry_with_user_prompt "Qdrant Volume Permissions Fix" fix_qdrant_permissions_impl
}

# --- Deploy Services with Retry ---
deploy_services_impl() {
    cd "$SETUP_DIR"
    
    # Create directories with proper permissions
    local dirs="data/n8n"
    if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
        dirs="$dirs data/qdrant"
    fi
    if [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
        dirs="$dirs data/portainer"
    fi
    file_operation "mkdir" $dirs
    
    local chown_dirs="data/n8n"
    if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
        chown_dirs="$chown_dirs data/qdrant"
    fi
    file_operation "chown" 1000:1000 $chown_dirs
    
    # Pull latest images before starting services
    info "Pulling latest container images..."
    $DOCKER_COMPOSE_CMD pull
    
    # Fix Qdrant volume permissions before starting services (only if Qdrant is installed)
    if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
        fix_qdrant_permissions
    fi
    
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
        if ! public_ip=$(safe_curl "ipv4.icanhazip.com"); then
            public_ip="your-server-ip"
        fi
    fi
    
    # Load credentials from .env file
    source "${SETUP_DIR}/.env"
    
    echo
    echo "🎉======================================================"
    echo "   n8n Production Stack Deployed Successfully!"
    echo "======================================================"
    echo
    
    if [ -n "${N8N_DOMAIN:-}" ]; then
        # Extract root domain from N8N_DOMAIN (e.g., n8n.mughal.pro -> mughal.pro)
        local root_domain
        if [[ "$N8N_DOMAIN" =~ ^[^.]+\.(.+)$ ]]; then
            root_domain="${BASH_REMATCH[1]}"
        else
            root_domain="$N8N_DOMAIN"
        fi
        
        # Use subdomain variables from .env file or fallback to script defaults
        local n8n_sub="${N8N_SUBDOMAIN:-n8n}"
        local portainer_sub="${PORTAINER_SUBDOMAIN:-portainer}"
        local dozzle_sub="${DOZZLE_SUBDOMAIN:-dozzle}"
        local qdrant_sub="${QDRANT_SUBDOMAIN:-qdrant}"
        
        echo "🌐 n8n: https://${N8N_DOMAIN}"
        
        if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
            echo "🔧 Qdrant Vector DB: https://${qdrant_sub}.${root_domain}"
            echo "   └─ API Key: ${QDRANT_API_KEY}"
        fi
        if [ "${INSTALL_DOZZLE,,}" = "yes" ]; then
            echo "📊 Container Logs: https://${dozzle_sub}.${root_domain} (Dozzle)"
        fi
        if [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
            echo "🐳 Docker Management: https://${portainer_sub}.${root_domain} (Portainer)"
            echo "   └─ Username: admin | Password: admin123456"
        fi
        
        echo "⚠️  Ensure DNS records point to ${public_ip}:"
        echo "   • ${N8N_DOMAIN} → ${public_ip}"
        if [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
            echo "   • ${portainer_sub}.${root_domain} → ${public_ip}"
        fi
        if [ "${INSTALL_DOZZLE,,}" = "yes" ]; then
            echo "   • ${dozzle_sub}.${root_domain} → ${public_ip}"
        fi
        if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
            echo "   • ${qdrant_sub}.${root_domain} → ${public_ip}"
        fi
        echo "🔒 SSL Certificate: Automatic via Let's Encrypt"
    else
        echo "🌐 n8n: http://${public_ip}:5678"
        if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
            echo "🔧 Qdrant Vector DB: http://${public_ip}:6333"
        fi
        if [ "${INSTALL_DOZZLE,,}" = "yes" ]; then
            echo "📊 Container Logs: http://${public_ip}:8080 (Dozzle)"
        fi
        if [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
            echo "🐳 Docker Management: http://${public_ip}:9000 (Portainer)"
            echo "   └─ Username: admin | Password: admin123456"
        fi
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
    if [ "${INSTALL_FFMPEG,,}" = "yes" ]; then
        echo "   ✓ FFmpeg and yt-dlp for video/audio processing and downloading built into n8n container"
    fi
    if [ "${INSTALL_QDRANT,,}" = "yes" ]; then
        echo "   ✓ Qdrant vector database with API key authentication"
    fi
    echo "   ✓ Automatic HTTPS ${N8N_DOMAIN:+(with subdomain routing)}${N8N_DOMAIN:-"(add domain for HTTPS)"}"
    local monitoring_features=""
    if [ "${INSTALL_DOZZLE,,}" = "yes" ] && [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
        monitoring_features="Container monitoring (Dozzle + Portainer)"
    elif [ "${INSTALL_DOZZLE,,}" = "yes" ]; then
        monitoring_features="Container log monitoring (Dozzle)"
    elif [ "${INSTALL_PORTAINER,,}" = "yes" ]; then
        monitoring_features="Container management (Portainer)"
    fi
    if [ -n "$monitoring_features" ]; then
        echo "   ✓ $monitoring_features"
    fi
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
