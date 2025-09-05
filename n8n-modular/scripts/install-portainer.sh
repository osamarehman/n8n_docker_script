#!/bin/bash

# ==============================================================================
# Portainer Docker Management Standalone Installation Script
# Installs Portainer for easy Docker container management
# Can be run independently or as part of the modular stack
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

# --- Portainer Specific Configuration ---
readonly COMPONENT_NAME="portainer"
PORTAINER_SUBDOMAIN="${PORTAINER_SUBDOMAIN:-portainer}"
PORTAINER_DOMAIN="${PORTAINER_DOMAIN:-}"
PORTAINER_PASSWORD="${PORTAINER_PASSWORD:-}"

# --- Configuration Collection ---
collect_portainer_configuration() {
    info "Collecting Portainer Docker management configuration..."
    
    # Check if running in auto mode
    local auto_mode=false
    for arg in "$@"; do
        case "$arg" in
            "--auto"|"--non-interactive")
                auto_mode=true
                ;;
        esac
    done
    
    # Collect domain if not set (optional for Portainer)
    if [ -z "$PORTAINER_DOMAIN" ] && [ "$auto_mode" = "false" ]; then
        if [ -c /dev/tty ]; then
            echo
            info "🌐 Portainer Domain Configuration (Optional)"
            echo "Enter a domain for Portainer if you want HTTPS access via Caddy"
            echo "Leave empty for direct port access (HTTP only on port 9000)"
            echo "If you have Caddy installed, it will automatically proxy Portainer"
            echo
            echo -n "Enter Portainer domain [leave empty for port access]: " > /dev/tty
            read PORTAINER_DOMAIN < /dev/tty || PORTAINER_DOMAIN=""
        fi
    fi
    
    # Validate domain if provided
    if [ -n "$PORTAINER_DOMAIN" ]; then
        validate_domain "$PORTAINER_DOMAIN"
        info "🌐 Domain-based setup: $PORTAINER_DOMAIN (will be proxied by Caddy)"
    else
        info "🌐 Direct port access on port 9000"
    fi
    
    # Generate admin password if not set
    if [ -z "$PORTAINER_PASSWORD" ]; then
        PORTAINER_PASSWORD=$(generate_password 12)
        if [ ${#PORTAINER_PASSWORD} -lt 8 ]; then
            error "Failed to generate secure password"
        fi
        info "🔒 Generated secure admin password"
    fi
    
    info "👤 Admin username will be: admin"
}

# --- Create Portainer Environment File ---
create_portainer_env_impl() {
    ensure_setup_directory
    
    # Create or update .env file for Portainer
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
    
    # Remove existing Portainer configuration
    grep -v "^PORTAINER_" "$temp_env" > "${temp_env}.clean" && mv "${temp_env}.clean" "$temp_env"
    
    # Add Portainer configuration
    cat >> "$temp_env" <<EOF

# Portainer Docker Management Configuration
PORTAINER_SUBDOMAIN=${PORTAINER_SUBDOMAIN}
PORTAINER_PASSWORD=${PORTAINER_PASSWORD}
${PORTAINER_DOMAIN:+PORTAINER_DOMAIN=${PORTAINER_DOMAIN}}
EOF
    
    mv "$temp_env" "$env_file"
    file_operation "chmod" 600 "$env_file"
    
    success "Portainer environment configuration created"
}

create_portainer_env() {
    retry_with_user_prompt "Portainer Environment Creation" create_portainer_env_impl
}

# --- Create Portainer Docker Compose ---
create_portainer_compose_impl() {
    local compose_file="${SETUP_DIR}/docker-compose.portainer.yml"
    
    cat > "$compose_file" << 'EOF'
services:
  portainer:
    image: portainer/portainer-ce:${PORTAINER_VERSION}
    container_name: portainer
    restart: unless-stopped
    environment:
      - TZ=${TZ}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    networks:
      - n8n_network
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:9000/api/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
EOF

    # Add ports for direct access if no domain is configured
    if [ -z "$PORTAINER_DOMAIN" ]; then
        cat >> "$compose_file" << 'EOF'
    ports:
      - "9000:9000"
EOF
    fi

    cat >> "$compose_file" << 'EOF'

volumes:
  portainer_data:

networks:
  n8n_network:
    external: true
EOF
    
    success "Portainer Docker Compose configuration created"
}

create_portainer_compose() {
    retry_with_user_prompt "Portainer Docker Compose Creation" create_portainer_compose_impl
}

# --- Deploy Portainer ---
deploy_portainer_impl() {
    cd "$SETUP_DIR"
    
    # Ensure Docker network exists
    ensure_docker_network
    
    # Pull latest Portainer image
    info "Pulling latest Portainer container image..."
    docker pull "portainer/portainer-ce:${PORTAINER_VERSION}"
    
    # Deploy Portainer using the compose file
    info "Deploying Portainer Docker management..."
    ${DOCKER_COMPOSE_CMD} -f docker-compose.portainer.yml up -d
    
    # Wait for Portainer to be ready
    info "Waiting for Portainer to initialize (this may take 30 seconds)..."
    sleep 20
    
    # Enhanced health check
    local wait_count=0
    local max_wait=60
    while [ $wait_count -lt $max_wait ]; do
        if docker exec portainer wget --no-verbose --tries=1 --spider http://localhost:9000/api/status 2>/dev/null; then
            success "Portainer is healthy and responding!"
            break
        fi
        
        if [ $wait_count -ge $max_wait ]; then
            warning "Portainer health check timed out, but container may still be starting"
            break
        fi
        
        echo "Waiting for Portainer to be ready... ($wait_count/$max_wait seconds)"
        sleep 5
        wait_count=$((wait_count + 5))
    done
    
    # Initialize Portainer admin user
    initialize_portainer_admin
    
    # Show container status
    ${DOCKER_COMPOSE_CMD} -f docker-compose.portainer.yml ps
    
    success "Portainer Docker management deployed successfully"
}

deploy_portainer() {
    retry_with_user_prompt "Portainer Deployment" deploy_portainer_impl
}

# --- Initialize Portainer Admin User ---
initialize_portainer_admin_impl() {
    local portainer_url
    local max_attempts=12
    local attempt=1
    
    # Determine Portainer URL for initialization
    if [ -n "$PORTAINER_DOMAIN" ]; then
        portainer_url="https://${PORTAINER_DOMAIN}"
    else
        portainer_url="http://localhost:9000"
    fi
    
    info "Initializing Portainer admin user..."
    
    # Wait for Portainer to be ready to accept the initialization
    while [ $attempt -le $max_attempts ]; do
        if docker exec portainer wget --no-verbose --tries=1 --spider http://localhost:9000/api/users/admin/init 2>/dev/null; then
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            warning "Could not reach Portainer initialization endpoint. You may need to set up admin manually."
            return 0
        fi
        
        echo "Waiting for Portainer initialization endpoint... (attempt $attempt/$max_attempts)"
        sleep 5
        attempt=$((attempt + 1))
    done
    
    # Create admin user via API
    local init_response
    init_response=$(docker exec portainer sh -c "
        wget -qO- --post-data='{\"Username\":\"admin\",\"Password\":\"${PORTAINER_PASSWORD}\"}' \
        --header='Content-Type: application/json' \
        http://localhost:9000/api/users/admin/init 2>/dev/null || echo 'init_failed'
    ")
    
    if [[ "$init_response" == *"init_failed"* ]] || [[ "$init_response" == *"error"* ]]; then
        warning "Automatic admin initialization may have failed."
        warning "You can manually set up the admin user through the web interface."
    else
        success "Portainer admin user initialized successfully"
    fi
}

initialize_portainer_admin() {
    retry_with_user_prompt "Portainer Admin Initialization" initialize_portainer_admin_impl
}

# --- Configure Firewall for Portainer ---
configure_portainer_firewall_impl() {
    if ! command -v ufw >/dev/null 2>&1; then
        warning "UFW not available, skipping firewall configuration"
        return 0
    fi
    
    # Only open port if not using domain (domain traffic goes through Caddy)
    if [ -z "$PORTAINER_DOMAIN" ]; then
        info "Configuring firewall for direct Portainer access..."
        ufw allow 9000/tcp comment "Portainer Web UI"
        info "Firewall rule added for Portainer (port 9000)"
    else
        info "Domain-based setup detected - firewall will be configured by Caddy"
    fi
}

configure_portainer_firewall() {
    retry_with_user_prompt "Portainer Firewall Configuration" configure_portainer_firewall_impl
}

# --- Create Portainer Management Script ---
create_portainer_management_script_impl() {
    local mgmt_script="${SETUP_DIR}/manage-portainer.sh"
    
    cat > "$mgmt_script" << 'EOF'
#!/bin/bash

# Portainer Management Script
# Useful commands for managing your Portainer installation

cd "$(dirname "$0")"

# Load environment
if [ -f ".env" ]; then
    source .env
fi

case "${1:-help}" in
    start)
        echo "Starting Portainer..."
        docker compose -f docker-compose.portainer.yml start
        ;;
    stop)
        echo "Stopping Portainer..."
        docker compose -f docker-compose.portainer.yml stop
        ;;
    restart)
        echo "Restarting Portainer..."
        docker compose -f docker-compose.portainer.yml restart
        ;;
    logs)
        echo "Showing Portainer logs..."
        docker compose -f docker-compose.portainer.yml logs -f portainer
        ;;
    status)
        echo "=== Portainer Status ==="
        docker compose -f docker-compose.portainer.yml ps
        echo
        echo "=== Container Resources ==="
        docker stats portainer --no-stream
        ;;
    update)
        echo "Updating Portainer..."
        docker compose -f docker-compose.portainer.yml pull
        docker compose -f docker-compose.portainer.yml up -d
        echo "Update completed!"
        ;;
    backup)
        echo "Creating Portainer data backup..."
        backup_file="portainer-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
        docker run --rm -v portainer_data:/data -v "$(pwd)":/backup alpine \
            tar czf "/backup/$backup_file" -C /data .
        echo "Backup created: $backup_file"
        ;;
    restore)
        if [ -z "$2" ]; then
            echo "Usage: $0 restore <backup-file.tar.gz>"
            exit 1
        fi
        if [ ! -f "$2" ]; then
            echo "Backup file not found: $2"
            exit 1
        fi
        echo "Restoring Portainer data from: $2"
        echo "WARNING: This will overwrite existing Portainer data!"
        read -p "Continue? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            docker compose -f docker-compose.portainer.yml down
            docker run --rm -v portainer_data:/data -v "$(pwd)":/backup alpine \
                sh -c "rm -rf /data/* && tar xzf /backup/$2 -C /data"
            docker compose -f docker-compose.portainer.yml up -d
            echo "Restore completed!"
        else
            echo "Restore cancelled"
        fi
        ;;
    reset-password)
        echo "Resetting Portainer admin password..."
        docker compose -f docker-compose.portainer.yml down
        docker run --rm -v portainer_data:/data alpine \
            sh -c "rm -f /data/portainer.db /data/portainer.key"
        docker compose -f docker-compose.portainer.yml up -d
        echo "Password reset! Visit Portainer web interface to set new admin password."
        ;;
    info)
        echo "=== Portainer Installation Info ==="
        if [ -n "${PORTAINER_DOMAIN:-}" ]; then
            echo "URL: https://${PORTAINER_DOMAIN}"
        else
            PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "your-server-ip")
            echo "URL: http://${PUBLIC_IP}:9000"
        fi
        echo "Username: admin"
        echo "Password: ${PORTAINER_PASSWORD:-'(not set)'}"
        echo "Data Location: Docker volume 'portainer_data'"
        ;;
    *)
        echo "Portainer Management Script"
        echo "Usage: $0 {start|stop|restart|logs|status|update|backup|restore|reset-password|info}"
        echo ""
        echo "Commands:"
        echo "  start           Start Portainer container"
        echo "  stop            Stop Portainer container"
        echo "  restart         Restart Portainer container"
        echo "  logs            Show Portainer logs"
        echo "  status          Show container status and resources"
        echo "  update          Update to latest Portainer version"
        echo "  backup          Create backup of Portainer data"
        echo "  restore <file>  Restore Portainer data from backup"
        echo "  reset-password  Reset admin password (requires web setup)"
        echo "  info            Show connection and credential info"
        ;;
esac
EOF
    
    file_operation "chmod" +x "$mgmt_script"
    success "Portainer management script created: $mgmt_script"
}

create_portainer_management_script() {
    retry_with_user_prompt "Portainer Management Script Creation" create_portainer_management_script_impl
}

# --- Show Portainer Results ---
show_portainer_results_impl() {
    load_env_config
    
    local public_ip=$(get_public_ip)
    
    echo
    echo "🎉======================================================="
    echo "   Portainer Docker Management Successfully Installed!"
    echo "======================================================="
    echo
    
    if [ -n "${PORTAINER_DOMAIN:-}" ]; then
        echo "🌐 Portainer Access: https://${PORTAINER_DOMAIN}"
        echo "⚠️  Ensure DNS record points ${PORTAINER_DOMAIN} → ${public_ip}"
        echo "🔒 SSL: Automatic via Caddy (install/update Caddy script for HTTPS)"
    else
        echo "🌐 Portainer Access: http://${public_ip}:9000"
    fi
    
    echo
    echo "🔐 Login Credentials:"
    echo "   Username: admin"
    echo "   Password: ${PORTAINER_PASSWORD:-'(see environment file)'}"
    echo
    echo "📁 Installation Directory: ${SETUP_DIR}"
    echo "🛠️  Portainer Management Commands:"
    echo "   Status:  docker compose -f ${SETUP_DIR}/docker-compose.portainer.yml ps"
    echo "   Logs:    docker compose -f ${SETUP_DIR}/docker-compose.portainer.yml logs -f portainer"
    echo "   Restart: docker compose -f ${SETUP_DIR}/docker-compose.portainer.yml restart portainer"
    echo "   Stop:    docker compose -f ${SETUP_DIR}/docker-compose.portainer.yml down"
    echo
    echo "🎯 Advanced Management:"
    echo "   Full Management: ${SETUP_DIR}/manage-portainer.sh"
    echo "   Backup Data:     ${SETUP_DIR}/manage-portainer.sh backup"
    echo "   Update Version:  ${SETUP_DIR}/manage-portainer.sh update"
    echo "   Reset Password:  ${SETUP_DIR}/manage-portainer.sh reset-password"
    echo
    echo "✅ Features:"
    echo "   ✓ Complete Docker container management"
    echo "   ✓ Web-based interface"
    echo "   ✓ Container stats and monitoring"
    echo "   ✓ Image management"
    echo "   ✓ Volume and network management"
    echo "   ✓ User management and RBAC"
    echo "   ✓ Container templates"
    echo "   ✓ Automatic data backup capability"
    
    if [ -n "${PORTAINER_DOMAIN:-}" ]; then
        echo "   ✓ Domain-ready for HTTPS"
    else
        echo "   ✓ Direct HTTP access"
    fi
    
    echo
    echo "📚 What you can do with Portainer:"
    echo "   • Manage all your n8n stack containers"
    echo "   • Monitor resource usage and performance"
    echo "   • View container logs in real-time"
    echo "   • Update container images with one click"
    echo "   • Manage Docker networks and volumes"
    echo "   • Deploy new containers from templates"
    echo "   • Set up user accounts for team access"
    echo
    
    # First-time setup note
    if docker exec portainer sh -c "test -f /data/portainer.db" 2>/dev/null; then
        echo "ℹ️  Portainer is initialized and ready to use!"
    else
        echo "⚠️  First-time setup required:"
        echo "   1. Visit Portainer in your browser"
        echo "   2. Create admin account if prompted"
        echo "   3. Choose 'Docker' environment"
        echo "   4. Start managing your containers!"
    fi
    echo
}

show_portainer_results() {
    retry_with_user_prompt "Portainer Results Display" show_portainer_results_impl
}

# --- Cleanup Portainer Installation ---
cleanup_portainer() {
    info "Cleaning up existing Portainer installation..."
    
    cd "$SETUP_DIR" 2>/dev/null || true
    
    # Stop and remove Portainer containers
    if [ -f "docker-compose.portainer.yml" ]; then
        ${DOCKER_COMPOSE_CMD} -f docker-compose.portainer.yml down 2>/dev/null || true
    fi
    
    # Remove Portainer container if it exists
    if docker ps -aq -f name="^portainer$" | grep -q .; then
        docker rm -f "portainer" 2>/dev/null || true
    fi
    
    # Remove Portainer-related files
    rm -f "${SETUP_DIR}/docker-compose.portainer.yml" 2>/dev/null || true
    rm -f "${SETUP_DIR}/manage-portainer.sh" 2>/dev/null || true
    
    # Remove firewall rules
    if command -v ufw >/dev/null 2>&1; then
        ufw delete allow 9000/tcp 2>/dev/null || true
    fi
    
    success "Portainer cleanup completed"
}

# --- Main Portainer Installation Function ---
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
                echo "  --cleanup              Remove existing Portainer installation"
                echo "  --auto                 Run in automatic mode with defaults"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  PORTAINER_DOMAIN       Domain for Portainer (optional, for HTTPS via Caddy)"
                echo "  PORTAINER_SUBDOMAIN    Subdomain prefix (default: portainer)"
                echo "  PORTAINER_PASSWORD     Admin password (auto-generated if not set)"
                echo ""
                echo "Portainer provides a web interface for managing Docker containers,"
                echo "images, volumes, networks, and more."
                exit 0
                ;;
        esac
    done
    
    check_root
    
    if [ "$cleanup_mode" = "true" ]; then
        cleanup_portainer
        exit 0
    fi
    
    info "Starting Portainer Docker management installation..."
    
    collect_portainer_configuration "$@"
    check_system_requirements
    install_dependencies
    install_docker
    check_docker_compose
    create_portainer_env
    create_portainer_compose
    configure_portainer_firewall
    deploy_portainer
    create_portainer_management_script
    show_portainer_results
    
    success "Portainer Docker management installation completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi