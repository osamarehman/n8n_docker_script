#!/bin/bash

# ==============================================================================
# n8n Standalone Installation Script
# Installs n8n workflow automation platform with SQLite database
# Can be run independently or as part of the modular stack
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

# --- n8n Specific Configuration ---
readonly COMPONENT_NAME="n8n"
N8N_DOMAIN="${N8N_DOMAIN:-}"
N8N_USER="${N8N_USER:-}"
N8N_PASSWORD="${N8N_PASSWORD:-}"
N8N_SUBDOMAIN="${N8N_SUBDOMAIN:-n8n}"

# --- Configuration Collection ---
collect_n8n_configuration() {
    info "Collecting n8n configuration..."
    
    # Check if running in auto mode
    local auto_mode=false
    for arg in "$@"; do
        case "$arg" in
            "--auto"|"--non-interactive")
                auto_mode=true
                ;;
        esac
    done
    
    # Collect domain if not set
    if [ -z "$N8N_DOMAIN" ] && [ "$auto_mode" = "false" ]; then
        if [ -c /dev/tty ]; then
            echo
            info "🌐 n8n Domain Configuration"
            echo "Enter your domain for n8n (e.g., 'n8n.yourdomain.com')"
            echo "Leave empty for IP-based access (HTTP only)"
            echo
            echo -n "Enter n8n domain [leave empty for IP]: " > /dev/tty
            read N8N_DOMAIN < /dev/tty || N8N_DOMAIN=""
        fi
    fi
    
    # Validate domain if provided
    if [ -n "$N8N_DOMAIN" ]; then
        validate_domain "$N8N_DOMAIN"
        info "🌐 Domain-based setup: $N8N_DOMAIN (HTTPS will be handled by Caddy)"
    else
        info "🌐 IP-based setup (HTTP only on port 5678)"
    fi
    
    # Collect admin username
    if [ -z "$N8N_USER" ]; then
        if [ "$auto_mode" = "true" ]; then
            N8N_USER="admin@example.com"
        else
            if [ -c /dev/tty ]; then
                echo -n "Enter n8n admin username/email [admin@example.com]: " > /dev/tty
                read N8N_USER < /dev/tty || N8N_USER=""
                N8N_USER="${N8N_USER:-admin@example.com}"
            else
                N8N_USER="admin@example.com"
            fi
        fi
    fi
    
    # Validate username
    if [[ ! "$N8N_USER" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$|^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid username format: $N8N_USER"
    fi
    
    # Generate password if not set
    if [ -z "$N8N_PASSWORD" ]; then
        N8N_PASSWORD=$(generate_password 16)
        if [ ${#N8N_PASSWORD} -lt 8 ]; then
            error "Failed to generate secure password"
        fi
    fi
    
    info "👤 Admin username: $N8N_USER"
    info "🔒 Password generated securely"
}

# --- Create n8n Environment File ---
create_n8n_env_impl() {
    ensure_setup_directory
    
    # Create or update .env file for n8n
    local env_file="${SETUP_DIR}/.env"
    local temp_env="${env_file}.tmp"
    
    # Start with existing env file if it exists, otherwise start fresh
    if [ -f "$env_file" ]; then
        cp "$env_file" "$temp_env"
    else
        cat > "$temp_env" <<EOF
# n8n Modular Stack Configuration
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Timezone
TZ=UTC
EOF
    fi
    
    # Remove existing n8n configuration
    grep -v "^N8N_" "$temp_env" > "${temp_env}.clean" && mv "${temp_env}.clean" "$temp_env"
    
    # Add n8n configuration
    cat >> "$temp_env" <<EOF

# n8n Configuration
N8N_BASIC_AUTH_USER=${N8N_USER}
N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
N8N_LOG_LEVEL=warn
N8N_METRICS=false
${N8N_DOMAIN:+N8N_DOMAIN=${N8N_DOMAIN}}
${N8N_DOMAIN:+N8N_SUBDOMAIN=${N8N_SUBDOMAIN}}
EOF
    
    mv "$temp_env" "$env_file"
    file_operation "chmod" 600 "$env_file"
    
    success "n8n environment configuration created"
}

create_n8n_env() {
    retry_with_user_prompt "n8n Environment Creation" create_n8n_env_impl
}

# --- Create n8n Docker Compose ---
create_n8n_compose_impl() {
    local compose_file="${SETUP_DIR}/docker-compose.n8n.yml"
    
    cat > "$compose_file" << 'EOF'
services:
  # Volume initialization service
  n8n-init:
    image: alpine:latest
    volumes:
      - n8n_data:/n8n-data
    command: |
      sh -c "
        echo 'Fixing volume permissions for n8n (user 1000:1000)...'
        chown -R 1000:1000 /n8n-data
        echo 'n8n volume permissions fixed'
      "
    restart: "no"
    networks:
      - n8n_network

  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    container_name: n8n
    restart: unless-stopped
    user: "1000:1000"
    depends_on:
      - n8n-init
    environment:
      - TZ=${TZ}
      # Using SQLite instead of PostgreSQL
      - DB_TYPE=sqlite
      - DB_SQLITE_VACUUM_ON_STARTUP=true
      - DB_SQLITE_POOL_SIZE=5
      # Security and performance improvements
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_PROXY_HOPS=1
      # Authentication
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
EOF

    # Add domain-specific configuration
    if [ -n "$N8N_DOMAIN" ]; then
        cat >> "$compose_file" << EOF
      # Domain-based webhook configuration
      - WEBHOOK_URL=https://${N8N_DOMAIN}/
      - N8N_HOST=${N8N_DOMAIN}
      - N8N_PROTOCOL=https
      - N8N_PORT=443
EOF
    else
        cat >> "$compose_file" << 'EOF'
      # IP-based configuration
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
    ports:
      - "5678:5678"
EOF
    fi

    cat >> "$compose_file" << 'EOF'
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

volumes:
  n8n_data:

networks:
  n8n_network:
    external: true
EOF
    
    success "n8n Docker Compose configuration created"
}

create_n8n_compose() {
    retry_with_user_prompt "n8n Docker Compose Creation" create_n8n_compose_impl
}

# --- Deploy n8n ---
deploy_n8n_impl() {
    cd "$SETUP_DIR"
    
    # Ensure Docker network exists
    ensure_docker_network
    
    # Pull latest n8n image
    info "Pulling latest n8n container image..."
    docker pull "n8nio/n8n:${N8N_VERSION}"
    
    # Deploy n8n using the compose file
    info "Deploying n8n container..."
    ${DOCKER_COMPOSE_CMD} -f docker-compose.n8n.yml up -d
    
    # Wait for n8n to be healthy
    wait_for_container_health "n8n" "http://localhost:5678/healthz"
    
    # Show container status
    ${DOCKER_COMPOSE_CMD} -f docker-compose.n8n.yml ps
    
    success "n8n deployed successfully"
}

deploy_n8n() {
    retry_with_user_prompt "n8n Deployment" deploy_n8n_impl
}

# --- Firewall Configuration for n8n ---
configure_n8n_firewall_impl() {
    if ! command -v ufw >/dev/null 2>&1; then
        warning "UFW not available, skipping firewall configuration"
        return 0
    fi
    
    # Only open port 5678 if not using domain (domain traffic goes through Caddy on 80/443)
    if [ -z "$N8N_DOMAIN" ]; then
        info "Configuring firewall for direct n8n access..."
        ufw allow 5678/tcp comment "n8n HTTP"
        info "Firewall rule added for n8n (port 5678)"
    else
        info "Domain-based setup detected - firewall will be configured by Caddy script"
    fi
}

configure_n8n_firewall() {
    retry_with_user_prompt "n8n Firewall Configuration" configure_n8n_firewall_impl
}

# --- Show n8n Results ---
show_n8n_results_impl() {
    load_env_config
    
    local public_ip=$(get_public_ip)
    
    echo
    echo "🎉======================================================="
    echo "   n8n Successfully Installed!"
    echo "======================================================="
    echo
    
    if [ -n "${N8N_DOMAIN:-}" ]; then
        echo "🌐 n8n Access: https://${N8N_DOMAIN}"
        echo "⚠️  Ensure DNS record points ${N8N_DOMAIN} → ${public_ip}"
        echo "🔒 SSL: Automatic via Caddy (install Caddy script if not done)"
    else
        echo "🌐 n8n Access: http://${public_ip}:5678"
    fi
    
    echo
    echo "🔐 n8n Login Credentials:"
    echo "   Username: ${N8N_BASIC_AUTH_USER:-$N8N_USER}"
    echo "   Password: ${N8N_BASIC_AUTH_PASSWORD:-$N8N_PASSWORD}"
    echo
    echo "📁 Installation Directory: ${SETUP_DIR}"
    echo "🛠️  Management Commands:"
    echo "   Status:  docker compose -f ${SETUP_DIR}/docker-compose.n8n.yml ps"
    echo "   Logs:    docker compose -f ${SETUP_DIR}/docker-compose.n8n.yml logs -f n8n"
    echo "   Restart: docker compose -f ${SETUP_DIR}/docker-compose.n8n.yml restart n8n"
    echo "   Stop:    docker compose -f ${SETUP_DIR}/docker-compose.n8n.yml down"
    echo
    echo "✅ Features:"
    echo "   ✓ SQLite database (no external dependencies)"
    echo "   ✓ Standard n8n image"
    echo "   ✓ Automatic volume permissions"
    echo "   ✓ Health monitoring"
    echo "   ✓ Production-ready configuration"
    
    if [ -n "${N8N_DOMAIN:-}" ]; then
        echo "   ✓ Domain-ready for HTTPS (requires Caddy)"
    else
        echo "   ✓ Direct HTTP access"
    fi
    echo
}

show_n8n_results() {
    retry_with_user_prompt "n8n Results Display" show_n8n_results_impl
}

# --- Cleanup n8n Installation ---
cleanup_n8n() {
    info "Cleaning up existing n8n installation..."
    
    cd "$SETUP_DIR" 2>/dev/null || true
    
    # Stop and remove n8n containers
    if [ -f "docker-compose.n8n.yml" ]; then
        ${DOCKER_COMPOSE_CMD} -f docker-compose.n8n.yml down 2>/dev/null || true
    fi
    
    # Remove individual containers if they exist
    for container in "n8n" "n8n-init"; do
        if docker ps -aq -f name="^${container}$" | grep -q .; then
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
    
    # Remove n8n compose file
    rm -f "${SETUP_DIR}/docker-compose.n8n.yml" 2>/dev/null || true
    
    success "n8n cleanup completed"
}

# --- Main n8n Installation Function ---
main() {
    local cleanup_mode=false
    local auto_mode=false
    
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            "--cleanup")
                cleanup_mode=true
                ;;
            "--auto"|"--non-interactive")
                auto_mode=true
                ;;
            "--help"|"-h")
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --cleanup              Remove existing n8n installation"
                echo "  --auto                 Run in automatic mode with defaults"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  N8N_DOMAIN            Domain for n8n (e.g. n8n.example.com)"
                echo "  N8N_USER              Admin username (default: admin@example.com)"
                echo "  N8N_PASSWORD          Admin password (auto-generated if not set)"
                echo "  N8N_SUBDOMAIN         Subdomain prefix (default: n8n)"
                exit 0
                ;;
        esac
    done
    
    check_root
    
    if [ "$cleanup_mode" = "true" ]; then
        cleanup_n8n
        exit 0
    fi
    
    info "Starting n8n installation..."
    
    collect_n8n_configuration "$@"
    check_system_requirements
    install_dependencies
    install_docker
    check_docker_compose
    create_n8n_env
    create_n8n_compose
    configure_n8n_firewall
    deploy_n8n
    show_n8n_results
    
    success "n8n installation completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi