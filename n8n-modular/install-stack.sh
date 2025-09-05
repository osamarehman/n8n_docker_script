#!/bin/bash

# ==============================================================================
# n8n Modular Stack Master Installation Script
# Orchestrates installation of all components in the correct order
# Provides complete stack management and individual component control
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common/utils.sh"

# --- Stack Configuration ---
readonly STACK_NAME="n8n Modular Stack"
readonly STACK_VERSION="3.0.0-modular"

# Component installation order and dependencies
readonly COMPONENTS=("n8n" "qdrant" "portainer" "watchtower" "caddy")

# Default component selection
INSTALL_N8N="${INSTALL_N8N:-yes}"
INSTALL_QDRANT="${INSTALL_QDRANT:-yes}"
INSTALL_PORTAINER="${INSTALL_PORTAINER:-yes}"
INSTALL_WATCHTOWER="${INSTALL_WATCHTOWER:-yes}"
INSTALL_CADDY="${INSTALL_CADDY:-yes}"

# Domain configuration
MAIN_DOMAIN="${MAIN_DOMAIN:-}"
N8N_SUBDOMAIN="${N8N_SUBDOMAIN:-n8n}"
PORTAINER_SUBDOMAIN="${PORTAINER_SUBDOMAIN:-portainer}"
QDRANT_SUBDOMAIN="${QDRANT_SUBDOMAIN:-qdrant}"

# Installation mode
STACK_MODE="${STACK_MODE:-interactive}"

# --- Display Stack Information ---
show_stack_info() {
    echo
    echo "🎯========================================================"
    echo "   ${STACK_NAME} v${STACK_VERSION}"
    echo "========================================================"
    echo
    echo "📦 Available Components:"
    echo "   • n8n           - Workflow automation platform (Core)"
    echo "   • Caddy         - Reverse proxy with automatic HTTPS"
    echo "   • Qdrant        - Vector database for AI/ML workflows"
    echo "   • Portainer     - Docker management interface"
    echo "   • Watchtower    - Automatic container updates"
    echo
    echo "✨ Features:"
    echo "   ✓ Modular design - install only what you need"
    echo "   ✓ Standalone scripts - each component can run independently"
    echo "   ✓ Automatic service discovery and integration"
    echo "   ✓ Domain-based routing with automatic HTTPS"
    echo "   ✓ Production-ready configurations"
    echo "   ✓ Comprehensive management tools"
    echo
}

# --- Collect Stack Configuration ---
collect_stack_configuration() {
    info "Collecting stack configuration..."
    
    # Check for command line arguments
    local auto_mode=false
    local interactive_mode=true
    
    for arg in "$@"; do
        case "$arg" in
            "--auto"|"--non-interactive")
                auto_mode=true
                interactive_mode=false
                STACK_MODE="auto"
                ;;
            "--minimal")
                INSTALL_QDRANT="no"
                INSTALL_PORTAINER="no"
                INSTALL_WATCHTOWER="no"
                ;;
            "--no-domain")
                INSTALL_CADDY="no"
                ;;
        esac
    done
    
    if [ "$interactive_mode" = "true" ]; then
        show_stack_info
        collect_domain_configuration
        collect_component_selection
        show_configuration_summary
        confirm_installation
    else
        info "Running in automatic mode with default configuration"
        if [ -n "$MAIN_DOMAIN" ]; then
            info "Domain-based setup: $MAIN_DOMAIN"
        else
            info "IP-based setup (no HTTPS)"
        fi
    fi
}

# --- Collect Domain Configuration ---
collect_domain_configuration() {
    if [ -z "$MAIN_DOMAIN" ]; then
        echo
        info "🌐 Domain Configuration"
        echo "For HTTPS and subdomain routing, enter your main domain."
        echo "This will create subdomains like: n8n.yourdomain.com, portainer.yourdomain.com"
        echo "Leave empty for IP-based access (HTTP only)."
        echo
        
        if [ -c /dev/tty ]; then
            echo -n "Enter your main domain [leave empty for IP]: " > /dev/tty
            read MAIN_DOMAIN < /dev/tty || MAIN_DOMAIN=""
        fi
    fi
    
    if [ -n "$MAIN_DOMAIN" ]; then
        validate_domain "$MAIN_DOMAIN"
        
        # Customize subdomains
        if [ -c /dev/tty ]; then
            echo
            info "📝 Subdomain Configuration"
            echo "Customize subdomain prefixes (or press Enter for defaults):"
            
            echo -n "n8n subdomain [${N8N_SUBDOMAIN}]: " > /dev/tty
            read custom_n8n < /dev/tty || custom_n8n=""
            N8N_SUBDOMAIN="${custom_n8n:-$N8N_SUBDOMAIN}"
            
            echo -n "Portainer subdomain [${PORTAINER_SUBDOMAIN}]: " > /dev/tty
            read custom_portainer < /dev/tty || custom_portainer=""
            PORTAINER_SUBDOMAIN="${custom_portainer:-$PORTAINER_SUBDOMAIN}"
            
            echo -n "Qdrant subdomain [${QDRANT_SUBDOMAIN}]: " > /dev/tty
            read custom_qdrant < /dev/tty || custom_qdrant=""
            QDRANT_SUBDOMAIN="${custom_qdrant:-$QDRANT_SUBDOMAIN}"
        fi
        
        info "🌐 Domain-based setup: $MAIN_DOMAIN"
        INSTALL_CADDY="yes"  # Force Caddy installation for domain setup
    else
        info "🌐 IP-based setup (HTTP only)"
        INSTALL_CADDY="no"   # No need for Caddy without domain
    fi
}

# --- Collect Component Selection ---
collect_component_selection() {
    echo
    info "📦 Component Selection"
    echo "Choose which components to install:"
    echo
    
    # n8n is mandatory
    info "✅ n8n (Core component - required)"
    
    if [ -c /dev/tty ]; then
        # Qdrant
        echo -n "Install Qdrant vector database? (recommended for AI workflows) [Y/n]: " > /dev/tty
        read qdrant_choice < /dev/tty || qdrant_choice=""
        if [[ "${qdrant_choice,,}" =~ ^(n|no)$ ]]; then
            INSTALL_QDRANT="no"
        fi
        
        # Portainer
        echo -n "Install Portainer for Docker management? [Y/n]: " > /dev/tty
        read portainer_choice < /dev/tty || portainer_choice=""
        if [[ "${portainer_choice,,}" =~ ^(n|no)$ ]]; then
            INSTALL_PORTAINER="no"
        fi
        
        # Watchtower
        echo -n "Install Watchtower for automatic updates? [Y/n]: " > /dev/tty
        read watchtower_choice < /dev/tty || watchtower_choice=""
        if [[ "${watchtower_choice,,}" =~ ^(n|no)$ ]]; then
            INSTALL_WATCHTOWER="no"
        fi
        
        # Caddy (if not already determined by domain)
        if [ "$INSTALL_CADDY" != "yes" ] && [ "$INSTALL_CADDY" != "no" ]; then
            echo -n "Install Caddy reverse proxy? (enables HTTPS, requires domain) [y/N]: " > /dev/tty
            read caddy_choice < /dev/tty || caddy_choice=""
            if [[ "${caddy_choice,,}" =~ ^(y|yes)$ ]]; then
                INSTALL_CADDY="yes"
                if [ -z "$MAIN_DOMAIN" ]; then
                    warning "Caddy requires a domain. Please configure domain first."
                    INSTALL_CADDY="no"
                fi
            fi
        fi
    fi
}

# --- Show Configuration Summary ---
show_configuration_summary() {
    echo
    echo "📋========================================================"
    echo "   Installation Configuration Summary"
    echo "========================================================"
    echo
    
    if [ -n "$MAIN_DOMAIN" ]; then
        echo "🌐 Access URLs (after installation):"
        echo "   • n8n:        https://${N8N_SUBDOMAIN}.${MAIN_DOMAIN}"
        [ "$INSTALL_PORTAINER" = "yes" ] && echo "   • Portainer:  https://${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN}"
        [ "$INSTALL_QDRANT" = "yes" ] && echo "   • Qdrant:     https://${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN}"
    else
        local public_ip=$(get_public_ip)
        echo "🌐 Access URLs (after installation):"
        echo "   • n8n:        http://${public_ip}:5678"
        [ "$INSTALL_PORTAINER" = "yes" ] && echo "   • Portainer:  http://${public_ip}:9000"
        [ "$INSTALL_QDRANT" = "yes" ] && echo "   • Qdrant:     http://${public_ip}:6333"
    fi
    
    echo
    echo "📦 Components to install:"
    echo "   ✅ n8n (Core)"
    [ "$INSTALL_CADDY" = "yes" ] && echo "   ✅ Caddy (Reverse Proxy)" || echo "   ❌ Caddy (Reverse Proxy)"
    [ "$INSTALL_QDRANT" = "yes" ] && echo "   ✅ Qdrant (Vector Database)" || echo "   ❌ Qdrant (Vector Database)"
    [ "$INSTALL_PORTAINER" = "yes" ] && echo "   ✅ Portainer (Docker Management)" || echo "   ❌ Portainer (Docker Management)"
    [ "$INSTALL_WATCHTOWER" = "yes" ] && echo "   ✅ Watchtower (Auto Updates)" || echo "   ❌ Watchtower (Auto Updates)"
    
    echo
    echo "🔧 Configuration:"
    echo "   • Installation Directory: ${SETUP_DIR}"
    echo "   • Database: SQLite (file-based)"
    echo "   • HTTPS: ${MAIN_DOMAIN:+Enabled (Caddy)}${MAIN_DOMAIN:-Disabled (no domain)}"
    echo "   • Network: ${SHARED_NETWORK}"
    
    if [ -n "$MAIN_DOMAIN" ]; then
        echo
        warning "⚠️  DNS CONFIGURATION REQUIRED"
        echo "Before installation, configure these DNS A records:"
        echo "   ${N8N_SUBDOMAIN}.${MAIN_DOMAIN} → $(get_public_ip)"
        [ "$INSTALL_PORTAINER" = "yes" ] && echo "   ${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN} → $(get_public_ip)"
        [ "$INSTALL_QDRANT" = "yes" ] && echo "   ${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN} → $(get_public_ip)"
    fi
    
    echo
}

# --- Confirm Installation ---
confirm_installation() {
    if [ -c /dev/tty ]; then
        echo -n "Proceed with installation? [Y/n]: " > /dev/tty
        read confirm < /dev/tty || confirm=""
        if [[ "${confirm,,}" =~ ^(n|no)$ ]]; then
            info "Installation cancelled"
            exit 0
        fi
    fi
    
    echo
    success "🚀 Starting installation..."
    echo
}

# --- Install Component ---
install_component() {
    local component="$1"
    local script_path="${SCRIPT_DIR}/scripts/install-${component}.sh"
    
    if [ ! -f "$script_path" ]; then
        error "Component script not found: $script_path"
    fi
    
    info "Installing $component..."
    
    # Set environment variables for component
    export MAIN_DOMAIN
    export N8N_SUBDOMAIN
    export PORTAINER_SUBDOMAIN  
    export QDRANT_SUBDOMAIN
    
    # Execute component installation script
    if bash "$script_path" --auto; then
        success "$component installation completed"
        return 0
    else
        error "$component installation failed"
        return 1
    fi
}

# --- Install Stack ---
install_stack_impl() {
    info "Installing n8n modular stack components..."
    
    # Install components in dependency order
    local installed_components=()
    
    # 1. Install n8n (core component)
    if [ "$INSTALL_N8N" = "yes" ]; then
        install_component "n8n"
        installed_components+=("n8n")
    fi
    
    # 2. Install optional services
    for component in "qdrant" "portainer" "watchtower"; do
        local var_name="INSTALL_${component^^}"
        if [ "${!var_name}" = "yes" ]; then
            install_component "$component"
            installed_components+=("$component")
        fi
    done
    
    # 3. Install Caddy last (it needs to detect other services)
    if [ "$INSTALL_CADDY" = "yes" ]; then
        install_component "caddy"
        installed_components+=("caddy")
        
        # Update other services to remove direct port exposure
        update_services_for_proxy
    fi
    
    success "All selected components installed successfully: ${installed_components[*]}"
}

install_stack() {
    retry_with_user_prompt "Stack Installation" install_stack_impl
}

# --- Update Services for Proxy ---
update_services_for_proxy() {
    info "Updating services to work with reverse proxy..."
    
    cd "$SETUP_DIR" || return
    
    # Restart services to pick up any networking changes
    local services_to_restart=()
    
    [ -f "docker-compose.n8n.yml" ] && services_to_restart+=("docker-compose.n8n.yml")
    [ -f "docker-compose.qdrant.yml" ] && services_to_restart+=("docker-compose.qdrant.yml")
    [ -f "docker-compose.portainer.yml" ] && services_to_restart+=("docker-compose.portainer.yml")
    
    for compose_file in "${services_to_restart[@]}"; do
        info "Restarting services in $compose_file for proxy integration..."
        ${DOCKER_COMPOSE_CMD} -f "$compose_file" restart 2>/dev/null || true
    done
    
    success "Services updated for reverse proxy"
}

# --- Create Stack Management Script ---
create_stack_management_script_impl() {
    local mgmt_script="${SETUP_DIR}/manage-stack.sh"
    
    cat > "$mgmt_script" << 'EOF'
#!/bin/bash

# n8n Modular Stack Management Script
# Unified management for all installed components

cd "$(dirname "$0")"

# Load environment
if [ -f ".env" ]; then
    source .env
fi

# Detect installed components
detect_components() {
    local components=()
    [ -f "docker-compose.n8n.yml" ] && components+=("n8n")
    [ -f "docker-compose.caddy.yml" ] && components+=("caddy")
    [ -f "docker-compose.qdrant.yml" ] && components+=("qdrant")
    [ -f "docker-compose.portainer.yml" ] && components+=("portainer")
    [ -f "docker-compose.watchtower.yml" ] && components+=("watchtower")
    echo "${components[@]}"
}

# Get compose files for installed components
get_compose_files() {
    local files=()
    [ -f "docker-compose.n8n.yml" ] && files+=("-f" "docker-compose.n8n.yml")
    [ -f "docker-compose.caddy.yml" ] && files+=("-f" "docker-compose.caddy.yml")
    [ -f "docker-compose.qdrant.yml" ] && files+=("-f" "docker-compose.qdrant.yml")
    [ -f "docker-compose.portainer.yml" ] && files+=("-f" "docker-compose.portainer.yml")
    [ -f "docker-compose.watchtower.yml" ] && files+=("-f" "docker-compose.watchtower.yml")
    echo "${files[@]}"
}

COMPONENTS=($(detect_components))
COMPOSE_FILES=($(get_compose_files))

case "${1:-help}" in
    start)
        if [ -n "$2" ]; then
            if [[ " ${COMPONENTS[@]} " =~ " $2 " ]]; then
                echo "Starting $2..."
                docker compose -f "docker-compose.$2.yml" start
            else
                echo "Component not found: $2"
                echo "Available components: ${COMPONENTS[*]}"
                exit 1
            fi
        else
            echo "Starting all stack components..."
            docker compose "${COMPOSE_FILES[@]}" start
        fi
        ;;
    stop)
        if [ -n "$2" ]; then
            if [[ " ${COMPONENTS[@]} " =~ " $2 " ]]; then
                echo "Stopping $2..."
                docker compose -f "docker-compose.$2.yml" stop
            else
                echo "Component not found: $2"
                echo "Available components: ${COMPONENTS[*]}"
                exit 1
            fi
        else
            echo "Stopping all stack components..."
            docker compose "${COMPOSE_FILES[@]}" stop
        fi
        ;;
    restart)
        if [ -n "$2" ]; then
            if [[ " ${COMPONENTS[@]} " =~ " $2 " ]]; then
                echo "Restarting $2..."
                docker compose -f "docker-compose.$2.yml" restart
            else
                echo "Component not found: $2"
                echo "Available components: ${COMPONENTS[*]}"
                exit 1
            fi
        else
            echo "Restarting all stack components..."
            docker compose "${COMPOSE_FILES[@]}" restart
        fi
        ;;
    logs)
        component="${2:-}"
        if [ -n "$component" ]; then
            if [[ " ${COMPONENTS[@]} " =~ " $component " ]]; then
                echo "Showing logs for $component..."
                docker compose -f "docker-compose.$component.yml" logs -f "$component"
            else
                echo "Component not found: $component"
                echo "Available components: ${COMPONENTS[*]}"
                exit 1
            fi
        else
            echo "Showing logs for all components..."
            docker compose "${COMPOSE_FILES[@]}" logs -f
        fi
        ;;
    status)
        echo "=== n8n Stack Status ==="
        echo "Installed components: ${COMPONENTS[*]}"
        echo
        for component in "${COMPONENTS[@]}"; do
            echo "--- $component ---"
            docker compose -f "docker-compose.$component.yml" ps
            echo
        done
        echo "=== Resource Usage ==="
        docker stats --no-stream $(docker ps --format "{{.Names}}" | grep -E "(n8n|caddy|qdrant|portainer|watchtower)")
        ;;
    update)
        component="${2:-all}"
        if [ "$component" = "all" ]; then
            echo "Updating all stack components..."
            docker compose "${COMPOSE_FILES[@]}" pull
            docker compose "${COMPOSE_FILES[@]}" up -d
            echo "Stack update completed!"
        elif [[ " ${COMPONENTS[@]} " =~ " $component " ]]; then
            echo "Updating $component..."
            docker compose -f "docker-compose.$component.yml" pull
            docker compose -f "docker-compose.$component.yml" up -d
            echo "$component update completed!"
        else
            echo "Component not found: $component"
            echo "Available components: ${COMPONENTS[*]}"
            exit 1
        fi
        ;;
    backup)
        backup_file="n8n-stack-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
        echo "Creating stack backup: $backup_file"
        
        # Create temp directory for backup
        temp_backup="/tmp/n8n-stack-backup-$$"
        mkdir -p "$temp_backup"
        
        # Backup configuration files
        cp -r . "$temp_backup/config/"
        
        # Backup Docker volumes
        echo "Backing up Docker volumes..."
        mkdir -p "$temp_backup/volumes"
        
        for volume in $(docker volume ls -q | grep -E "(n8n_data|caddy_data|caddy_config|qdrant_data|portainer_data)"); do
            echo "Backing up volume: $volume"
            docker run --rm -v "$volume":/source -v "$temp_backup/volumes":/backup alpine \
                tar czf "/backup/$volume.tar.gz" -C /source .
        done
        
        # Create final backup archive
        tar czf "$backup_file" -C "/tmp" "n8n-stack-backup-$$"
        rm -rf "$temp_backup"
        
        echo "Backup created: $backup_file"
        echo "Restore with: $0 restore $backup_file"
        ;;
    restore)
        if [ -z "$2" ] || [ ! -f "$2" ]; then
            echo "Usage: $0 restore <backup-file>"
            echo "Backup file must exist"
            exit 1
        fi
        
        backup_file="$2"
        echo "Restoring from backup: $backup_file"
        echo "WARNING: This will stop all services and restore data!"
        read -p "Continue? (y/N): " confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Restore cancelled"
            exit 0
        fi
        
        # Stop services
        echo "Stopping all services..."
        docker compose "${COMPOSE_FILES[@]}" down
        
        # Extract backup
        temp_restore="/tmp/n8n-stack-restore-$$"
        mkdir -p "$temp_restore"
        tar xzf "$backup_file" -C "$temp_restore"
        
        # Restore configuration
        echo "Restoring configuration..."
        cp -r "$temp_restore"/*/config/* .
        
        # Restore volumes
        echo "Restoring Docker volumes..."
        for volume_backup in "$temp_restore"/*/volumes/*.tar.gz; do
            if [ -f "$volume_backup" ]; then
                volume_name=$(basename "$volume_backup" .tar.gz)
                echo "Restoring volume: $volume_name"
                docker volume create "$volume_name" >/dev/null 2>&1 || true
                docker run --rm -v "$volume_name":/target -v "$volume_backup":/backup.tar.gz alpine \
                    sh -c "cd /target && rm -rf * && tar xzf /backup.tar.gz"
            fi
        done
        
        # Restart services
        echo "Starting services..."
        docker compose "${COMPOSE_FILES[@]}" up -d
        
        rm -rf "$temp_restore"
        echo "Restore completed!"
        ;;
    info)
        echo "=== n8n Modular Stack Information ==="
        echo "Installation: $(pwd)"
        echo "Components: ${COMPONENTS[*]}"
        echo
        
        if [ -n "${MAIN_DOMAIN:-}" ]; then
            echo "🌐 Access URLs:"
            [ -f "docker-compose.n8n.yml" ] && echo "   n8n:        https://${N8N_SUBDOMAIN}.${MAIN_DOMAIN}"
            [ -f "docker-compose.portainer.yml" ] && echo "   Portainer:  https://${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN}"
            [ -f "docker-compose.qdrant.yml" ] && echo "   Qdrant:     https://${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN}"
        else
            PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "your-server-ip")
            echo "🌐 Access URLs:"
            [ -f "docker-compose.n8n.yml" ] && echo "   n8n:        http://${PUBLIC_IP}:5678"
            [ -f "docker-compose.portainer.yml" ] && echo "   Portainer:  http://${PUBLIC_IP}:9000"
            [ -f "docker-compose.qdrant.yml" ] && echo "   Qdrant:     http://${PUBLIC_IP}:6333"
        fi
        
        echo
        echo "🔐 Credentials (check .env file for passwords)"
        echo "📁 Data Location: Docker volumes"
        echo "🛠️  Individual Management:"
        for component in "${COMPONENTS[@]}"; do
            if [ -f "manage-$component.sh" ]; then
                echo "   $component: ./manage-$component.sh"
            fi
        done
        ;;
    *)
        echo "n8n Modular Stack Management"
        echo "Usage: $0 {start|stop|restart|logs|status|update|backup|restore|info} [component]"
        echo ""
        echo "Commands:"
        echo "  start [component]    Start all services or specific component"
        echo "  stop [component]     Stop all services or specific component"
        echo "  restart [component]  Restart all services or specific component"
        echo "  logs [component]     Show logs for all or specific component"
        echo "  status               Show status of all components"
        echo "  update [component]   Update all or specific component"
        echo "  backup               Create full stack backup"
        echo "  restore <file>       Restore from backup file"
        echo "  info                 Show stack information and URLs"
        echo ""
        echo "Installed components: ${COMPONENTS[*]}"
        ;;
esac
EOF
    
    file_operation "chmod" +x "$mgmt_script"
    success "Stack management script created: $mgmt_script"
}

create_stack_management_script() {
    retry_with_user_prompt "Stack Management Script Creation" create_stack_management_script_impl
}

# --- Show Final Results ---
show_stack_results_impl() {
    load_env_config
    
    local public_ip=$(get_public_ip)
    local installed_components=()
    
    # Detect installed components
    [ -f "${SETUP_DIR}/docker-compose.n8n.yml" ] && installed_components+=("n8n")
    [ -f "${SETUP_DIR}/docker-compose.caddy.yml" ] && installed_components+=("caddy")
    [ -f "${SETUP_DIR}/docker-compose.qdrant.yml" ] && installed_components+=("qdrant")
    [ -f "${SETUP_DIR}/docker-compose.portainer.yml" ] && installed_components+=("portainer")
    [ -f "${SETUP_DIR}/docker-compose.watchtower.yml" ] && installed_components+=("watchtower")
    
    echo
    echo "🎉========================================================"
    echo "   ${STACK_NAME} Installation Complete!"
    echo "========================================================"
    echo
    
    if [ -n "${MAIN_DOMAIN:-}" ]; then
        echo "🌐 Your Stack is Available at:"
        [[ " ${installed_components[*]} " =~ " n8n " ]] && echo "   • n8n Workflows:     https://${N8N_SUBDOMAIN}.${MAIN_DOMAIN}"
        [[ " ${installed_components[*]} " =~ " portainer " ]] && echo "   • Docker Management: https://${PORTAINER_SUBDOMAIN}.${MAIN_DOMAIN}"
        [[ " ${installed_components[*]} " =~ " qdrant " ]] && echo "   • Vector Database:   https://${QDRANT_SUBDOMAIN}.${MAIN_DOMAIN}"
    else
        echo "🌐 Your Stack is Available at:"
        [[ " ${installed_components[*]} " =~ " n8n " ]] && echo "   • n8n Workflows:     http://${public_ip}:5678"
        [[ " ${installed_components[*]} " =~ " portainer " ]] && echo "   • Docker Management: http://${public_ip}:9000"
        [[ " ${installed_components[*]} " =~ " qdrant " ]] && echo "   • Vector Database:   http://${public_ip}:6333"
    fi
    
    echo
    echo "📦 Installed Components: ${installed_components[*]}"
    echo "🔒 SSL Certificates: ${MAIN_DOMAIN:+Automatic via Let's Encrypt}${MAIN_DOMAIN:-Not configured}"
    echo "📁 Installation Directory: ${SETUP_DIR}"
    echo
    echo "🛠️  Stack Management Commands:"
    echo "   Full Stack:     ${SETUP_DIR}/manage-stack.sh {start|stop|restart|status|logs|update|backup}"
    echo "   Component Info: ${SETUP_DIR}/manage-stack.sh info"
    echo "   Stack Status:   ${SETUP_DIR}/manage-stack.sh status"
    echo "   Create Backup:  ${SETUP_DIR}/manage-stack.sh backup"
    echo
    echo "🎯 Individual Component Management:"
    for component in "${installed_components[@]}"; do
        if [ -f "${SETUP_DIR}/manage-${component}.sh" ]; then
            echo "   $component: ${SETUP_DIR}/manage-${component}.sh"
        fi
    done
    
    echo
    echo "✅ Features Enabled:"
    echo "   ✓ Modular architecture - components work independently"
    echo "   ✓ Shared Docker network for inter-service communication"
    echo "   ✓ Persistent data storage with proper volume management"
    echo "   ✓ Production-ready configurations with security headers"
    [[ " ${installed_components[*]} " =~ " caddy " ]] && echo "   ✓ Automatic HTTPS with Let's Encrypt SSL certificates"
    [[ " ${installed_components[*]} " =~ " watchtower " ]] && echo "   ✓ Automatic container updates (monitor logs regularly)"
    echo "   ✓ Comprehensive management and backup tools"
    echo
    
    # Show credentials
    if [[ " ${installed_components[*]} " =~ " n8n " ]]; then
        echo "🔐 Login Credentials:"
        echo "   n8n Username: ${N8N_BASIC_AUTH_USER:-admin@example.com}"
        echo "   n8n Password: Check ${SETUP_DIR}/.env file"
    fi
    
    if [[ " ${installed_components[*]} " =~ " portainer " ]]; then
        echo "   Portainer Username: admin"
        echo "   Portainer Password: Check ${SETUP_DIR}/.env file"
    fi
    
    if [[ " ${installed_components[*]} " =~ " qdrant " ]]; then
        echo "   Qdrant API Key: Check ${SETUP_DIR}/.env file"
    fi
    
    echo
    echo "🚀 Next Steps:"
    echo "   1. Verify all services are running: ${SETUP_DIR}/manage-stack.sh status"
    echo "   2. Access n8n and complete the initial setup"
    echo "   3. Create your first workflow in n8n"
    if [[ " ${installed_components[*]} " =~ " qdrant " ]]; then
        echo "   4. Test Qdrant integration: ${SETUP_DIR}/test-qdrant.sh"
    fi
    echo "   5. Set up regular backups: ${SETUP_DIR}/manage-stack.sh backup"
    
    if [[ " ${installed_components[*]} " =~ " watchtower " ]]; then
        echo "   6. Monitor automatic updates: docker logs watchtower"
    fi
    
    echo
    echo "📚 Documentation and Support:"
    echo "   • n8n Documentation: https://docs.n8n.io/"
    echo "   • n8n Community: https://community.n8n.io/"
    if [[ " ${installed_components[*]} " =~ " qdrant " ]]; then
        echo "   • Qdrant Documentation: https://qdrant.tech/documentation/"
    fi
    echo "   • Docker Compose Reference: https://docs.docker.com/compose/"
    echo
    
    success "🎯 Your n8n modular stack is ready for use!"
}

show_stack_results() {
    retry_with_user_prompt "Stack Results Display" show_stack_results_impl
}

# --- Cleanup Stack ---
cleanup_stack() {
    info "Cleaning up entire n8n stack..."
    
    cd "$SETUP_DIR" 2>/dev/null || true
    
    # Stop all services
    local compose_files=(
        "docker-compose.n8n.yml"
        "docker-compose.caddy.yml"
        "docker-compose.qdrant.yml"
        "docker-compose.portainer.yml"
        "docker-compose.watchtower.yml"
    )
    
    for compose_file in "${compose_files[@]}"; do
        if [ -f "$compose_file" ]; then
            info "Stopping services in $compose_file..."
            ${DOCKER_COMPOSE_CMD} -f "$compose_file" down 2>/dev/null || true
        fi
    done
    
    # Remove containers
    for container in "n8n" "caddy" "qdrant" "portainer" "watchtower" "n8n-init" "qdrant-init"; do
        if docker ps -aq -f name="^${container}$" | grep -q .; then
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
    
    # Remove network
    docker network rm "$SHARED_NETWORK" 2>/dev/null || true
    
    # Remove files
    rm -rf "$SETUP_DIR" 2>/dev/null || true
    
    success "n8n stack cleanup completed"
}

# --- Main Function ---
main() {
    local cleanup_mode=false
    
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            "--cleanup")
                cleanup_mode=true
                ;;
            "--help"|"-h")
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --auto                 Run in automatic mode with defaults"
                echo "  --minimal              Install only n8n (no optional components)"
                echo "  --no-domain            Skip Caddy/HTTPS setup"
                echo "  --cleanup              Remove entire stack installation"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  MAIN_DOMAIN            Main domain for subdomain routing"
                echo "  INSTALL_QDRANT         Install Qdrant (yes/no, default: yes)"
                echo "  INSTALL_PORTAINER      Install Portainer (yes/no, default: yes)"
                echo "  INSTALL_WATCHTOWER     Install Watchtower (yes/no, default: yes)"
                echo "  INSTALL_CADDY          Install Caddy (yes/no, default: yes if domain)"
                echo ""
                echo "The modular stack allows you to install components individually"
                echo "or as a complete integrated solution."
                exit 0
                ;;
        esac
    done
    
    check_root
    
    if [ "$cleanup_mode" = "true" ]; then
        cleanup_stack
        exit 0
    fi
    
    info "Starting ${STACK_NAME} installation..."
    
    collect_stack_configuration "$@"
    check_system_requirements
    install_dependencies
    install_docker
    check_docker_compose
    ensure_setup_directory
    install_stack
    create_stack_management_script
    show_stack_results
    
    success "${STACK_NAME} installation completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi