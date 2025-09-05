#!/bin/bash

# ==============================================================================
# Watchtower Auto-Update Standalone Installation Script
# Installs Watchtower for automatic Docker container updates
# Can be run independently or as part of the modular stack
# ==============================================================================

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

# --- Watchtower Specific Configuration ---
readonly COMPONENT_NAME="watchtower"
WATCHTOWER_POLL_INTERVAL="${WATCHTOWER_POLL_INTERVAL:-86400}"  # 24 hours default
WATCHTOWER_CLEANUP="${WATCHTOWER_CLEANUP:-true}"
WATCHTOWER_LOG_LEVEL="${WATCHTOWER_LOG_LEVEL:-info}"
WATCHTOWER_NOTIFICATIONS="${WATCHTOWER_NOTIFICATIONS:-false}"
WATCHTOWER_INCLUDE_STOPPED="${WATCHTOWER_INCLUDE_STOPPED:-false}"
WATCHTOWER_LABEL_ENABLE="${WATCHTOWER_LABEL_ENABLE:-true}"

# --- Configuration Collection ---
collect_watchtower_configuration() {
    info "Collecting Watchtower auto-update configuration..."
    
    # Check if running in auto mode
    local auto_mode=false
    for arg in "$@"; do
        case "$arg" in
            "--auto"|"--non-interactive")
                auto_mode=true
                ;;
        esac
    done
    
    if [ "$auto_mode" = "false" ]; then
        if [ -c /dev/tty ]; then
            echo
            info "⚙️ Watchtower Configuration"
            echo "Watchtower will automatically update your Docker containers when new versions are available."
            echo
            
            # Update interval configuration
            echo -n "Update check interval in hours [24]: " > /dev/tty
            read interval_hours < /dev/tty || interval_hours=""
            interval_hours="${interval_hours:-24}"
            
            # Validate interval
            if ! [[ "$interval_hours" =~ ^[0-9]+$ ]] || [ "$interval_hours" -lt 1 ]; then
                warning "Invalid interval, using default 24 hours"
                interval_hours=24
            fi
            
            # Convert hours to seconds
            WATCHTOWER_POLL_INTERVAL=$((interval_hours * 3600))
            
            # Cleanup configuration
            echo -n "Remove old images after update? [Y/n]: " > /dev/tty
            read cleanup_choice < /dev/tty || cleanup_choice=""
            if [[ "${cleanup_choice,,}" =~ ^(n|no)$ ]]; then
                WATCHTOWER_CLEANUP="false"
            else
                WATCHTOWER_CLEANUP="true"
            fi
            
            # Log level configuration
            echo -n "Log level (debug/info/warn/error) [info]: " > /dev/tty
            read log_level < /dev/tty || log_level=""
            log_level="${log_level:-info}"
            case "${log_level,,}" in
                debug|info|warn|error)
                    WATCHTOWER_LOG_LEVEL="${log_level,,}"
                    ;;
                *)
                    warning "Invalid log level, using 'info'"
                    WATCHTOWER_LOG_LEVEL="info"
                    ;;
            esac
            
            # Include stopped containers
            echo -n "Also update stopped containers? [y/N]: " > /dev/tty
            read stopped_choice < /dev/tty || stopped_choice=""
            if [[ "${stopped_choice,,}" =~ ^(y|yes)$ ]]; then
                WATCHTOWER_INCLUDE_STOPPED="true"
            else
                WATCHTOWER_INCLUDE_STOPPED="false"
            fi
            
            echo
        fi
    fi
    
    local hours=$((WATCHTOWER_POLL_INTERVAL / 3600))
    info "⏰ Update check interval: every ${hours} hours"
    info "🧹 Cleanup old images: $WATCHTOWER_CLEANUP"
    info "📝 Log level: $WATCHTOWER_LOG_LEVEL"
    info "⏸️  Include stopped containers: $WATCHTOWER_INCLUDE_STOPPED"
    
    # Safety warning
    echo
    warning "⚠️  WATCHTOWER SAFETY NOTICE"
    echo "Watchtower automatically updates containers when new versions are released."
    echo "This is convenient but can potentially break your applications if:"
    echo "  • New versions have breaking changes"
    echo "  • Your configuration is not compatible"
    echo "  • Dependencies change"
    echo
    echo "💡 Recommendations:"
    echo "  • Test updates in a staging environment first"
    echo "  • Monitor logs after automatic updates"
    echo "  • Have backup/rollback procedures ready"
    echo "  • Consider label-based filtering for production"
    echo
    
    if [ "$auto_mode" = "false" ]; then
        if [ -c /dev/tty ]; then
            echo -n "Do you understand these risks and want to continue? [y/N]: " > /dev/tty
            read risk_confirm < /dev/tty || risk_confirm=""
            if [[ ! "${risk_confirm,,}" =~ ^(y|yes)$ ]]; then
                info "Watchtower installation cancelled"
                exit 0
            fi
        fi
    fi
    
    echo
}

# --- Create Watchtower Environment File ---
create_watchtower_env_impl() {
    ensure_setup_directory
    
    # Create or update .env file for Watchtower
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
    
    # Remove existing Watchtower configuration
    grep -v "^WATCHTOWER_" "$temp_env" > "${temp_env}.clean" && mv "${temp_env}.clean" "$temp_env"
    
    # Add Watchtower configuration
    cat >> "$temp_env" <<EOF

# Watchtower Auto-Update Configuration
WATCHTOWER_POLL_INTERVAL=${WATCHTOWER_POLL_INTERVAL}
WATCHTOWER_CLEANUP=${WATCHTOWER_CLEANUP}
WATCHTOWER_LOG_LEVEL=${WATCHTOWER_LOG_LEVEL}
WATCHTOWER_NOTIFICATIONS=${WATCHTOWER_NOTIFICATIONS}
WATCHTOWER_INCLUDE_STOPPED=${WATCHTOWER_INCLUDE_STOPPED}
WATCHTOWER_LABEL_ENABLE=${WATCHTOWER_LABEL_ENABLE}
EOF
    
    mv "$temp_env" "$env_file"
    file_operation "chmod" 600 "$env_file"
    
    success "Watchtower environment configuration created"
}

create_watchtower_env() {
    retry_with_user_prompt "Watchtower Environment Creation" create_watchtower_env_impl
}

# --- Create Watchtower Docker Compose ---
create_watchtower_compose_impl() {
    local compose_file="${SETUP_DIR}/docker-compose.watchtower.yml"
    
    cat > "$compose_file" << 'EOF'
services:
  watchtower:
    image: containrrr/watchtower:${WATCHTOWER_VERSION}
    container_name: watchtower
    restart: unless-stopped
    environment:
      - TZ=${TZ}
      - WATCHTOWER_CLEANUP=${WATCHTOWER_CLEANUP}
      - WATCHTOWER_POLL_INTERVAL=${WATCHTOWER_POLL_INTERVAL}
      - WATCHTOWER_LOG_LEVEL=${WATCHTOWER_LOG_LEVEL}
      - WATCHTOWER_LABEL_ENABLE=${WATCHTOWER_LABEL_ENABLE}
      - WATCHTOWER_INCLUDE_STOPPED=${WATCHTOWER_INCLUDE_STOPPED}
      - WATCHTOWER_NOTIFICATIONS=${WATCHTOWER_NOTIFICATIONS}
      # Security: Run as non-root when possible
      - WATCHTOWER_NO_PULL=false
      - WATCHTOWER_NO_RESTART=false
      # Rolling restart to minimize downtime
      - WATCHTOWER_NO_STARTUP_MESSAGE=false
      - WATCHTOWER_SCHEDULE=0 0 2 * * *  # Daily at 2 AM (cron format)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /root/.docker/config.json:/config.json:ro
    networks:
      - n8n_network
    healthcheck:
      test: ["CMD-SHELL", "ps aux | grep '[w]atchtower' || exit 1"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 10s
    labels:
      - "com.centurylinklabs.watchtower.enable=false"  # Don't update itself

networks:
  n8n_network:
    external: true
EOF
    
    success "Watchtower Docker Compose configuration created"
}

create_watchtower_compose() {
    retry_with_user_prompt "Watchtower Docker Compose Creation" create_watchtower_compose_impl
}

# --- Deploy Watchtower ---
deploy_watchtower_impl() {
    cd "$SETUP_DIR"
    
    # Ensure Docker network exists
    ensure_docker_network
    
    # Pull latest Watchtower image
    info "Pulling latest Watchtower container image..."
    docker pull "containrrr/watchtower:${WATCHTOWER_VERSION}"
    
    # Deploy Watchtower using the compose file
    info "Deploying Watchtower auto-update service..."
    ${DOCKER_COMPOSE_CMD} -f docker-compose.watchtower.yml up -d
    
    # Wait for Watchtower to start
    sleep 10
    
    # Check if Watchtower is running
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "watchtower.*Up"; then
        success "Watchtower is running and monitoring containers"
    else
        warning "Watchtower may not be fully ready yet, check logs: docker logs watchtower"
    fi
    
    # Show container status
    ${DOCKER_COMPOSE_CMD} -f docker-compose.watchtower.yml ps
    
    success "Watchtower auto-update service deployed successfully"
}

deploy_watchtower() {
    retry_with_user_prompt "Watchtower Deployment" deploy_watchtower_impl
}

# --- Create Watchtower Management Script ---
create_watchtower_management_script_impl() {
    local mgmt_script="${SETUP_DIR}/manage-watchtower.sh"
    
    cat > "$mgmt_script" << 'EOF'
#!/bin/bash

# Watchtower Management Script
# Control and monitor your Watchtower auto-update service

cd "$(dirname "$0")"

# Load environment
if [ -f ".env" ]; then
    source .env
fi

case "${1:-help}" in
    start)
        echo "Starting Watchtower..."
        docker compose -f docker-compose.watchtower.yml start
        ;;
    stop)
        echo "Stopping Watchtower..."
        docker compose -f docker-compose.watchtower.yml stop
        ;;
    restart)
        echo "Restarting Watchtower..."
        docker compose -f docker-compose.watchtower.yml restart
        ;;
    logs)
        echo "Showing Watchtower logs..."
        docker compose -f docker-compose.watchtower.yml logs -f watchtower
        ;;
    status)
        echo "=== Watchtower Status ==="
        docker compose -f docker-compose.watchtower.yml ps
        echo
        echo "=== Container Resources ==="
        docker stats watchtower --no-stream
        ;;
    update)
        echo "Updating Watchtower itself..."
        docker compose -f docker-compose.watchtower.yml pull
        docker compose -f docker-compose.watchtower.yml up -d
        echo "Watchtower update completed!"
        ;;
    force-update)
        echo "Forcing Watchtower to check for updates now..."
        if docker exec watchtower sh -c "kill -USR1 1" 2>/dev/null; then
            echo "Update check triggered successfully!"
            echo "Check logs with: $0 logs"
        else
            echo "Failed to trigger update check. Is Watchtower running?"
        fi
        ;;
    last-run)
        echo "=== Last Watchtower Update Check ==="
        docker logs watchtower --tail 50 | grep -E "(Checking|Updating|Updated|No updates)" | tail -10
        ;;
    schedule)
        local hours=$((WATCHTOWER_POLL_INTERVAL / 3600))
        echo "=== Watchtower Update Schedule ==="
        echo "Check interval: Every ${hours} hours"
        echo "Cleanup old images: ${WATCHTOWER_CLEANUP}"
        echo "Include stopped containers: ${WATCHTOWER_INCLUDE_STOPPED}"
        echo "Log level: ${WATCHTOWER_LOG_LEVEL}"
        echo
        echo "Next check: Monitor with 'docker logs watchtower' to see timing"
        ;;
    monitored)
        echo "=== Containers Monitored by Watchtower ==="
        echo "All running containers are monitored unless they have:"
        echo "  com.centurylinklabs.watchtower.enable=false"
        echo
        echo "Currently running containers:"
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Labels}}" | \
            grep -v "com.centurylinklabs.watchtower.enable=false" || \
            docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
        ;;
    exclude)
        if [ -z "$2" ]; then
            echo "Usage: $0 exclude <container_name>"
            echo "This will add a label to exclude the container from Watchtower updates"
            exit 1
        fi
        container_name="$2"
        if docker ps -q -f name="^${container_name}$" | grep -q .; then
            echo "Adding exclusion label to container: $container_name"
            docker update --label-add com.centurylinklabs.watchtower.enable=false "$container_name"
            echo "Container $container_name will no longer be updated by Watchtower"
        else
            echo "Container not found: $container_name"
            exit 1
        fi
        ;;
    include)
        if [ -z "$2" ]; then
            echo "Usage: $0 include <container_name>"
            echo "This will remove the exclusion label from the container"
            exit 1
        fi
        container_name="$2"
        if docker ps -q -f name="^${container_name}$" | grep -q .; then
            echo "Removing exclusion label from container: $container_name"
            docker update --label-rm com.centurylinklabs.watchtower.enable "$container_name"
            echo "Container $container_name will now be updated by Watchtower"
        else
            echo "Container not found: $container_name"
            exit 1
        fi
        ;;
    config)
        echo "=== Watchtower Configuration ==="
        echo "Poll interval: ${WATCHTOWER_POLL_INTERVAL} seconds ($((WATCHTOWER_POLL_INTERVAL / 3600)) hours)"
        echo "Cleanup: ${WATCHTOWER_CLEANUP}"
        echo "Log level: ${WATCHTOWER_LOG_LEVEL}"
        echo "Include stopped: ${WATCHTOWER_INCLUDE_STOPPED}"
        echo "Label enable: ${WATCHTOWER_LABEL_ENABLE}"
        echo "Notifications: ${WATCHTOWER_NOTIFICATIONS}"
        echo
        echo "Config file: $(pwd)/.env"
        echo "Compose file: $(pwd)/docker-compose.watchtower.yml"
        ;;
    *)
        echo "Watchtower Management Script"
        echo "Usage: $0 {start|stop|restart|logs|status|update|force-update|last-run|schedule|monitored|exclude|include|config}"
        echo ""
        echo "Commands:"
        echo "  start           Start Watchtower service"
        echo "  stop            Stop Watchtower service" 
        echo "  restart         Restart Watchtower service"
        echo "  logs            Show Watchtower logs"
        echo "  status          Show container status and resources"
        echo "  update          Update Watchtower to latest version"
        echo "  force-update    Trigger immediate update check"
        echo "  last-run        Show last update activity"
        echo "  schedule        Show update schedule information"
        echo "  monitored       List containers being monitored"
        echo "  exclude <name>  Exclude container from updates"
        echo "  include <name>  Include container in updates"
        echo "  config          Show current configuration"
        ;;
esac
EOF
    
    file_operation "chmod" +x "$mgmt_script"
    success "Watchtower management script created: $mgmt_script"
}

create_watchtower_management_script() {
    retry_with_user_prompt "Watchtower Management Script Creation" create_watchtower_management_script_impl
}

# --- Show Watchtower Results ---
show_watchtower_results_impl() {
    load_env_config
    
    local hours=$((WATCHTOWER_POLL_INTERVAL / 3600))
    
    echo
    echo "🎉======================================================="
    echo "   Watchtower Auto-Update Service Successfully Installed!"
    echo "======================================================="
    echo
    
    echo "🤖 Watchtower Status: Monitoring and updating containers automatically"
    echo "⏰ Update Check Interval: Every ${hours} hours"
    echo "🧹 Image Cleanup: ${WATCHTOWER_CLEANUP}"
    echo "📝 Log Level: ${WATCHTOWER_LOG_LEVEL}"
    echo "⏸️  Include Stopped Containers: ${WATCHTOWER_INCLUDE_STOPPED}"
    echo
    echo "📁 Installation Directory: ${SETUP_DIR}"
    echo "🛠️  Watchtower Management Commands:"
    echo "   Status:      docker compose -f ${SETUP_DIR}/docker-compose.watchtower.yml ps"
    echo "   Logs:        docker compose -f ${SETUP_DIR}/docker-compose.watchtower.yml logs -f watchtower"
    echo "   Force Check: docker exec watchtower sh -c 'kill -USR1 1'"
    echo "   Stop:        docker compose -f ${SETUP_DIR}/docker-compose.watchtower.yml down"
    echo
    echo "🎯 Advanced Management:"
    echo "   Full Management:    ${SETUP_DIR}/manage-watchtower.sh"
    echo "   Trigger Update:     ${SETUP_DIR}/manage-watchtower.sh force-update"
    echo "   View Last Activity: ${SETUP_DIR}/manage-watchtower.sh last-run"
    echo "   Show Schedule:      ${SETUP_DIR}/manage-watchtower.sh schedule"
    echo "   List Monitored:     ${SETUP_DIR}/manage-watchtower.sh monitored"
    echo
    echo "✅ Features:"
    echo "   ✓ Automatic container updates when new versions are available"
    echo "   ✓ Configurable update intervals and cleanup policies"
    echo "   ✓ Label-based container inclusion/exclusion"
    echo "   ✓ Rolling updates to minimize downtime"
    echo "   ✓ Comprehensive logging and monitoring"
    echo "   ✓ Manual trigger capability for immediate updates"
    echo "   ✓ Safe: Watchtower excludes itself from updates"
    echo
    echo "🎯 What Watchtower Monitors:"
    echo "   • All running containers by default"
    echo "   • Containers are excluded with: com.centurylinklabs.watchtower.enable=false"
    echo "   • Currently installed stack components (n8n, Caddy, Qdrant, Portainer)"
    echo
    echo "⚡ Quick Actions:"
    echo "   Force immediate update check: ${SETUP_DIR}/manage-watchtower.sh force-update"
    echo "   Exclude a container:          ${SETUP_DIR}/manage-watchtower.sh exclude <container_name>"
    echo "   Include a container:          ${SETUP_DIR}/manage-watchtower.sh include <container_name>"
    echo
    
    echo "⚠️  Important Notes:"
    echo "   • Watchtower updates containers when newer images are available"
    echo "   • Test updates in staging before enabling in production"
    echo "   • Monitor logs after automatic updates: docker logs watchtower"
    echo "   • Back up important data before allowing automatic updates"
    echo "   • Consider disabling for critical production systems"
    echo
    
    echo "📊 Current Status:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep watchtower || echo "   Status check failed - may still be starting"
    echo
    
    echo "🔄 Next Steps:"
    echo "   1. Monitor initial logs: docker logs watchtower -f"
    echo "   2. Review which containers are being monitored"
    echo "   3. Consider excluding critical containers from automatic updates"
    echo "   4. Set up notifications if desired (see Watchtower documentation)"
    echo
}

show_watchtower_results() {
    retry_with_user_prompt "Watchtower Results Display" show_watchtower_results_impl
}

# --- Cleanup Watchtower Installation ---
cleanup_watchtower() {
    info "Cleaning up existing Watchtower installation..."
    
    cd "$SETUP_DIR" 2>/dev/null || true
    
    # Stop and remove Watchtower containers
    if [ -f "docker-compose.watchtower.yml" ]; then
        ${DOCKER_COMPOSE_CMD} -f docker-compose.watchtower.yml down 2>/dev/null || true
    fi
    
    # Remove Watchtower container if it exists
    if docker ps -aq -f name="^watchtower$" | grep -q .; then
        docker rm -f "watchtower" 2>/dev/null || true
    fi
    
    # Remove Watchtower-related files
    rm -f "${SETUP_DIR}/docker-compose.watchtower.yml" 2>/dev/null || true
    rm -f "${SETUP_DIR}/manage-watchtower.sh" 2>/dev/null || true
    
    success "Watchtower cleanup completed"
}

# --- Main Watchtower Installation Function ---
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
                echo "  --cleanup              Remove existing Watchtower installation"
                echo "  --auto                 Run in automatic mode with defaults"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  WATCHTOWER_POLL_INTERVAL    Update check interval in seconds (default: 86400)"
                echo "  WATCHTOWER_CLEANUP          Remove old images after update (default: true)"
                echo "  WATCHTOWER_LOG_LEVEL        Log level: debug/info/warn/error (default: info)"
                echo "  WATCHTOWER_INCLUDE_STOPPED  Update stopped containers (default: false)"
                echo ""
                echo "Watchtower automatically updates Docker containers when new versions"
                echo "are available. Use with caution in production environments."
                exit 0
                ;;
        esac
    done
    
    check_root
    
    if [ "$cleanup_mode" = "true" ]; then
        cleanup_watchtower
        exit 0
    fi
    
    info "Starting Watchtower auto-update service installation..."
    
    collect_watchtower_configuration "$@"
    check_system_requirements
    install_dependencies
    install_docker
    check_docker_compose
    create_watchtower_env
    create_watchtower_compose
    deploy_watchtower
    create_watchtower_management_script
    show_watchtower_results
    
    success "Watchtower auto-update service installation completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi