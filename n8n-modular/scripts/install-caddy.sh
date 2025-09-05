#!/bin/bash

# ==============================================================================
# Caddy Reverse Proxy Standalone Installation Script
# Provides HTTPS termination and routing for the n8n stack
# Can be run independently or as part of the modular stack
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

# --- Caddy Specific Configuration ---
readonly COMPONENT_NAME="caddy"
MAIN_DOMAIN="${MAIN_DOMAIN:-}"
N8N_SUBDOMAIN="${N8N_SUBDOMAIN:-n8n}"
PORTAINER_SUBDOMAIN="${PORTAINER_SUBDOMAIN:-portainer}"
QDRANT_SUBDOMAIN="${QDRANT_SUBDOMAIN:-qdrant}"

# Service discovery - check what services are installed
SERVICES_TO_PROXY=()

# --- Configuration Collection ---
collect_caddy_configuration() {
    info "Collecting Caddy reverse proxy configuration..."
    
    # Check if running in auto mode
    local auto_mode=false
    for arg in "$@"; do
        case "$arg" in
            "--auto"|"--non-interactive")
                auto_mode=true
                ;;
        esac
    done
    
    # Collect main domain if not set
    if [ -z "$MAIN_DOMAIN" ] && [ "$auto_mode" = "false" ]; then
        if [ -c /dev/tty ]; then
            echo
            info "🌐 Caddy Reverse Proxy Domain Configuration"
            echo "Enter your main domain for subdomain-based routing."
            echo "This will create subdomains like: n8n.yourdomain.com, portainer.yourdomain.com"
            echo "Example: if you enter 'example.com', services will be available at:"
            echo "  • n8n.example.com"
            echo "  • portainer.example.com (if installed)"
            echo "  • qdrant.example.com (if installed)"
            echo
            echo -n "Enter your main domain: " > /dev/tty
            read MAIN_DOMAIN < /dev/tty || MAIN_DOMAIN=""
        fi
    fi
    
    if [ -z "$MAIN_DOMAIN" ]; then
        error "Main domain is required for Caddy reverse proxy setup"
    fi
    
    # Validate domain
    validate_domain "$MAIN_DOMAIN"
    
    # Detect installed services
    detect_installed_services
    
    # Customize subdomains if interactive
    if [ "$auto_mode" = "false" ]; then
        if [ -c /dev/tty ]; then
            echo
            info "📝 Subdomain Configuration"
            echo "You can customize the subdomain names for each detected service:"
            echo
            
            for service in "${SERVICES_TO_PROXY[@]}"; do
                case "$service" in
                    "n8n")
                        echo -n "n8n subdomain [${N8N_SUBDOMAIN}]: " > /dev/tty
                        read custom_n8n < /dev/tty || custom_n8n=""
                        N8N_SUBDOMAIN="${custom_n8n:-$N8N_SUBDOMAIN}"
                        ;;
                    "portainer")
                        echo -n "Portainer subdomain [${PORTAINER_SUBDOMAIN}]: " > /dev/tty
                        read custom_portainer < /dev/tty || custom_portainer=""
                        PORTAINER_SUBDOMAIN="${custom_portainer:-$PORTAINER_SUBDOMAIN}"
                        ;;
                    "qdrant")
                        echo -n "Qdrant subdomain [${QDRANT_SUBDOMAIN}]: " > /dev/tty
                        read custom_qdrant < /dev/tty || custom_qdrant=""
                        QDRANT_SUBDOMAIN="${custom_qdrant:-$QDRANT_SUBDOMAIN}"
                        ;;
                esac
            done
            
            echo
            info "📋 Subdomain Summary:"
            for service in "${SERVICES_TO_PROXY[@]}"; do
                case "$service" in
                    "n8n")
                        echo "   • n8n: ${N8N_SUBDOMAIN}.${MAIN_DOMAIN}"
                        ;;
                    "portainer")
                        echo "   • Portainer: ${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN}"
                        ;;
                    "qdrant")
                        echo "   • Qdrant: ${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN}"
                        ;;
                esac
            done
            echo
        fi
    fi
    
    info "🌐 Main domain: $MAIN_DOMAIN"
    info "🎯 Services to proxy: ${SERVICES_TO_PROXY[*]}"
    
    # DNS Warning
    show_dns_configuration
}

# --- Detect Installed Services ---
detect_installed_services() {
    SERVICES_TO_PROXY=()
    
    if is_component_installed "n8n"; then
        SERVICES_TO_PROXY+=("n8n")
        info "✓ Detected n8n container"
    fi
    
    if is_component_installed "portainer"; then
        SERVICES_TO_PROXY+=("portainer")
        info "✓ Detected Portainer container"
    fi
    
    if is_component_installed "qdrant"; then
        SERVICES_TO_PROXY+=("qdrant")
        info "✓ Detected Qdrant container"
    fi
    
    if [ ${#SERVICES_TO_PROXY[@]} -eq 0 ]; then
        warning "No supported services detected. Caddy will be configured with basic routing."
        warning "Install other services first, then run this script again to add their routes."
    fi
}

# --- Show DNS Configuration ---
show_dns_configuration() {
    echo
    warning "⚠️  DNS CONFIGURATION REQUIRED"
    echo "Before Caddy can obtain SSL certificates, configure these DNS A records:"
    echo
    
    for service in "${SERVICES_TO_PROXY[@]}"; do
        case "$service" in
            "n8n")
                echo "   ${N8N_SUBDOMAIN}.${MAIN_DOMAIN} → [YOUR_SERVER_IP]"
                ;;
            "portainer")
                echo "   ${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN} → [YOUR_SERVER_IP]"
                ;;
            "qdrant")
                echo "   ${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN} → [YOUR_SERVER_IP]"
                ;;
        esac
    done
    
    echo
    echo "💡 All subdomains should point to the same server IP: $(get_public_ip)"
    echo "💡 DNS propagation may take 5-60 minutes depending on your provider."
    echo "💡 SSL certificates will be automatically generated via Let's Encrypt."
    echo
}

# --- Create Caddy Environment Configuration ---
create_caddy_env_impl() {
    ensure_setup_directory
    
    # Create or update .env file for Caddy
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
    
    # Remove existing Caddy/domain configuration
    grep -v -E "^(MAIN_DOMAIN|.*_SUBDOMAIN)" "$temp_env" > "${temp_env}.clean" && mv "${temp_env}.clean" "$temp_env"
    
    # Add Caddy configuration
    cat >> "$temp_env" <<EOF

# Caddy Reverse Proxy Configuration
MAIN_DOMAIN=${MAIN_DOMAIN}
N8N_SUBDOMAIN=${N8N_SUBDOMAIN}
PORTAINER_SUBDOMAIN=${PORTAINER_SUBDOMAIN}
QDRANT_SUBDOMAIN=${QDRANT_SUBDOMAIN}
EOF
    
    mv "$temp_env" "$env_file"
    file_operation "chmod" 600 "$env_file"
    
    success "Caddy environment configuration created"
}

create_caddy_env() {
    retry_with_user_prompt "Caddy Environment Creation" create_caddy_env_impl
}

# --- Create Caddyfile Configuration ---
create_caddyfile_impl() {
    local caddyfile="${SETUP_DIR}/Caddyfile"
    
    cat > "$caddyfile" << 'EOF'
# Caddy Reverse Proxy Configuration
# Auto-generated by n8n modular stack

EOF
    
    # Add service-specific routes
    for service in "${SERVICES_TO_PROXY[@]}"; do
        case "$service" in
            "n8n")
                cat >> "$caddyfile" << EOF
# n8n Workflow Automation
${N8N_SUBDOMAIN}.${MAIN_DOMAIN} {
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
        output file /var/log/caddy/${N8N_SUBDOMAIN}_access.log
        format json
    }
}

# Force HTTPS redirect for n8n
http://${N8N_SUBDOMAIN}.${MAIN_DOMAIN} {
    redir https://{host}{uri} permanent
}

EOF
                ;;
            "portainer")
                cat >> "$caddyfile" << EOF
# Portainer Docker Management
${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN} {
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
    
    log {
        output file /var/log/caddy/${PORTAINER_SUBDOMAIN}_access.log
        format json
    }
}

# Force HTTPS redirect for Portainer
http://${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN} {
    redir https://{host}{uri} permanent
}

EOF
                ;;
            "qdrant")
                cat >> "$caddyfile" << EOF
# Qdrant Vector Database
${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN} {
    reverse_proxy qdrant:6333
    
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
        output file /var/log/caddy/${QDRANT_SUBDOMAIN}_access.log
        format json
    }
}

# Force HTTPS redirect for Qdrant
http://${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN} {
    redir https://{host}{uri} permanent
}

EOF
                ;;
        esac
    done
    
    success "Caddyfile configuration created with ${#SERVICES_TO_PROXY[@]} service(s)"
}

create_caddyfile() {
    retry_with_user_prompt "Caddyfile Creation" create_caddyfile_impl
}

# --- Create Caddy Docker Compose ---
create_caddy_compose_impl() {
    local compose_file="${SETUP_DIR}/docker-compose.caddy.yml"
    
    cat > "$compose_file" << 'EOF'
services:
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
      - caddy_logs:/var/log/caddy
    environment:
      - TZ=${TZ}
    networks:
      - n8n_network
    healthcheck:
      test: ["CMD", "caddy", "version"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

volumes:
  caddy_data:
  caddy_config:
  caddy_logs:

networks:
  n8n_network:
    external: true
EOF
    
    success "Caddy Docker Compose configuration created"
}

create_caddy_compose() {
    retry_with_user_prompt "Caddy Docker Compose Creation" create_caddy_compose_impl
}

# --- Deploy Caddy ---
deploy_caddy_impl() {
    cd "$SETUP_DIR"
    
    # Ensure Docker network exists
    ensure_docker_network
    
    # Pull latest Caddy image
    info "Pulling latest Caddy container image..."
    docker pull "caddy:${CADDY_VERSION}"
    
    # Deploy Caddy using the compose file
    info "Deploying Caddy reverse proxy..."
    ${DOCKER_COMPOSE_CMD} -f docker-compose.caddy.yml up -d
    
    # Wait for Caddy to be ready
    sleep 10
    
    # Check Caddy status
    if docker exec caddy caddy version >/dev/null 2>&1; then
        success "Caddy is running and healthy"
    else
        warning "Caddy may not be fully ready yet, check logs: docker logs caddy"
    fi
    
    # Show container status
    ${DOCKER_COMPOSE_CMD} -f docker-compose.caddy.yml ps
    
    success "Caddy reverse proxy deployed successfully"
}

deploy_caddy() {
    retry_with_user_prompt "Caddy Deployment" deploy_caddy_impl
}

# --- Configure Firewall for Caddy ---
configure_caddy_firewall_impl() {
    if ! command -v ufw >/dev/null 2>&1; then
        warning "UFW not available, skipping firewall configuration"
        return 0
    fi
    
    info "Configuring firewall for Caddy reverse proxy..."
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp comment "HTTP (Caddy)"
    ufw allow 443/tcp comment "HTTPS (Caddy)"
    
    # Remove direct access ports for proxied services
    for service in "${SERVICES_TO_PROXY[@]}"; do
        case "$service" in
            "n8n")
                # Remove direct n8n access since it's now proxied
                ufw delete allow 5678/tcp 2>/dev/null || true
                ;;
            "portainer")
                # Remove direct Portainer access since it's now proxied
                ufw delete allow 9000/tcp 2>/dev/null || true
                ;;
            "qdrant")
                # Remove direct Qdrant access since it's now proxied
                ufw delete allow 6333/tcp 2>/dev/null || true
                ;;
        esac
    done
    
    info "Firewall configured for HTTPS reverse proxy access"
}

configure_caddy_firewall() {
    retry_with_user_prompt "Caddy Firewall Configuration" configure_caddy_firewall_impl
}

# --- Show Caddy Results ---
show_caddy_results_impl() {
    load_env_config
    
    local public_ip=$(get_public_ip)
    
    echo
    echo "🎉======================================================="
    echo "   Caddy Reverse Proxy Successfully Installed!"
    echo "======================================================="
    echo
    
    echo "🌐 SSL-Secured Service Access:"
    for service in "${SERVICES_TO_PROXY[@]}"; do
        case "$service" in
            "n8n")
                echo "   • n8n Workflow Automation: https://${N8N_SUBDOMAIN}.${MAIN_DOMAIN}"
                ;;
            "portainer")
                echo "   • Portainer Docker Management: https://${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN}"
                ;;
            "qdrant")
                echo "   • Qdrant Vector Database: https://${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN}"
                ;;
        esac
    done
    
    echo
    echo "⚠️  DNS Configuration Status:"
    echo "   Ensure ALL subdomains point to: ${public_ip}"
    for service in "${SERVICES_TO_PROXY[@]}"; do
        case "$service" in
            "n8n")
                echo "   • ${N8N_SUBDOMAIN}.${MAIN_DOMAIN} → ${public_ip}"
                ;;
            "portainer")
                echo "   • ${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN} → ${public_ip}"
                ;;
            "qdrant")
                echo "   • ${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN} → ${public_ip}"
                ;;
        esac
    done
    
    echo
    echo "🔒 SSL Certificates: Automatic via Let's Encrypt"
    echo "📁 Installation Directory: ${SETUP_DIR}"
    echo "🛠️  Caddy Management Commands:"
    echo "   Status:  docker compose -f ${SETUP_DIR}/docker-compose.caddy.yml ps"
    echo "   Logs:    docker compose -f ${SETUP_DIR}/docker-compose.caddy.yml logs -f caddy"
    echo "   Restart: docker compose -f ${SETUP_DIR}/docker-compose.caddy.yml restart caddy"
    echo "   Stop:    docker compose -f ${SETUP_DIR}/docker-compose.caddy.yml down"
    echo "   Config:  docker exec caddy caddy validate --config /etc/caddy/Caddyfile"
    echo
    echo "✅ Features:"
    echo "   ✓ Automatic HTTPS with Let's Encrypt"
    echo "   ✓ HTTP to HTTPS redirects"
    echo "   ✓ Security headers"
    echo "   ✓ GZIP compression"
    echo "   ✓ Access logging"
    echo "   ✓ Health checking for upstream services"
    echo "   ✓ Modern TLS protocols (1.2 & 1.3)"
    echo
    
    # SSL certificate status check
    echo "🔍 SSL Certificate Status Check (may take 1-2 minutes after first start):"
    for service in "${SERVICES_TO_PROXY[@]}"; do
        case "$service" in
            "n8n")
                echo "   Check n8n SSL: curl -I https://${N8N_SUBDOMAIN}.${MAIN_DOMAIN}"
                ;;
            "portainer")
                echo "   Check Portainer SSL: curl -I https://${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN}"
                ;;
            "qdrant")
                echo "   Check Qdrant SSL: curl -I https://${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN}"
                ;;
        esac
    done
    echo
}

show_caddy_results() {
    retry_with_user_prompt "Caddy Results Display" show_caddy_results_impl
}

# --- Cleanup Caddy Installation ---
cleanup_caddy() {
    info "Cleaning up existing Caddy installation..."
    
    cd "$SETUP_DIR" 2>/dev/null || true
    
    # Stop and remove Caddy containers
    if [ -f "docker-compose.caddy.yml" ]; then
        ${DOCKER_COMPOSE_CMD} -f docker-compose.caddy.yml down 2>/dev/null || true
    fi
    
    # Remove Caddy container if it exists
    if docker ps -aq -f name="^caddy$" | grep -q .; then
        docker rm -f "caddy" 2>/dev/null || true
    fi
    
    # Remove Caddy-related files
    rm -f "${SETUP_DIR}/docker-compose.caddy.yml" 2>/dev/null || true
    rm -f "${SETUP_DIR}/Caddyfile" 2>/dev/null || true
    
    # Remove firewall rules
    if command -v ufw >/dev/null 2>&1; then
        ufw delete allow 80/tcp 2>/dev/null || true
        ufw delete allow 443/tcp 2>/dev/null || true
    fi
    
    success "Caddy cleanup completed"
}

# --- Main Caddy Installation Function ---
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
                echo "  --cleanup              Remove existing Caddy installation"
                echo "  --auto                 Run in automatic mode with defaults"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  MAIN_DOMAIN            Main domain for subdomain routing (required)"
                echo "  N8N_SUBDOMAIN          n8n subdomain prefix (default: n8n)"
                echo "  PORTAINER_SUBDOMAIN    Portainer subdomain prefix (default: portainer)"
                echo "  QDRANT_SUBDOMAIN       Qdrant subdomain prefix (default: qdrant)"
                echo ""
                echo "This script automatically detects installed services and configures"
                echo "reverse proxy routes for them."
                exit 0
                ;;
        esac
    done
    
    check_root
    
    if [ "$cleanup_mode" = "true" ]; then
        cleanup_caddy
        exit 0
    fi
    
    info "Starting Caddy reverse proxy installation..."
    
    collect_caddy_configuration "$@"
    check_system_requirements
    install_dependencies
    install_docker
    check_docker_compose
    create_caddy_env
    create_caddyfile
    create_caddy_compose
    configure_caddy_firewall
    deploy_caddy
    show_caddy_results
    
    success "Caddy reverse proxy installation completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi