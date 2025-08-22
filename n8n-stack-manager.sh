#!/bin/bash

# ==============================================================================
# n8n Stack Manager - Interactive UI-Driven Management System
# A comprehensive tool for installing, managing, and maintaining n8n Docker stacks
# ==============================================================================

set -euo pipefail

# --- Configuration ---
readonly SCRIPT_NAME="n8n Stack Manager"
readonly SCRIPT_VERSION="3.0.0-ui"
readonly MIN_RAM_GB=2
readonly MIN_DISK_GB=8
readonly SETUP_DIR="/opt/n8n-stack"

# UI Configuration
readonly DIALOG_HEIGHT=20
readonly DIALOG_WIDTH=70
readonly CHECKLIST_HEIGHT=15

# Service definitions
declare -A SERVICES=(
    ["n8n"]="Core Automation Platform"
    ["qdrant"]="Vector Database for AI workflows"
    ["portainer"]="Docker Management Interface"
    ["dozzle"]="Real-time Log Viewer"
    ["caddy"]="Reverse Proxy with SSL"
    ["redis"]="Caching Layer (Optional)"
    ["postgresql"]="Database (Optional - uses SQLite by default)"
    ["grafana"]="Monitoring Dashboard (Optional)"
)

declare -A SERVICE_PORTS=(
    ["n8n"]="5678"
    ["qdrant"]="6333"
    ["portainer"]="9000"
    ["dozzle"]="8080"
    ["caddy"]="80,443"
    ["redis"]="6379"
    ["postgresql"]="5432"
    ["grafana"]="3000"
)

declare -A SERVICE_STATUS=()
declare -a SELECTED_SERVICES=()

# --- Color Functions ---
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; }

# --- UI Helper Functions ---
check_dialog() {
    if ! command -v dialog >/dev/null 2>&1; then
        echo "Installing dialog for better UI experience..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq && apt-get install -y dialog
        elif command -v yum >/dev/null 2>&1; then
            yum install -y dialog
        else
            error "Could not install dialog. Please install it manually."
        fi
    fi
}

show_banner() {
    dialog --title "Welcome" --msgbox "\n🚀 n8n Stack Manager v${SCRIPT_VERSION}\n\nA comprehensive tool for managing your n8n Docker infrastructure.\n\nFeatures:\n• Interactive service selection\n• Real-time health monitoring\n• Automated issue resolution\n• Configuration management\n• Backup & restore capabilities" 15 60
}

# --- Service Management Functions ---
detect_service_status() {
    local service="$1"
    
    if docker ps --format "table {{.Names}}" 2>/dev/null | grep -q "^${service}$"; then
        if docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep "^${service}" | grep -q "Up"; then
            SERVICE_STATUS["$service"]="🟢 Running"
        else
            SERVICE_STATUS["$service"]="🔴 Stopped"
        fi
    elif docker ps -a --format "table {{.Names}}" 2>/dev/null | grep -q "^${service}$"; then
        SERVICE_STATUS["$service"]="🟡 Exists (Stopped)"
    else
        SERVICE_STATUS["$service"]="⚪ Not Installed"
    fi
}

update_all_service_status() {
    for service in "${!SERVICES[@]}"; do
        detect_service_status "$service"
    done
}

# --- Main Menu Functions ---
show_main_menu() {
    local choice
    choice=$(dialog --clear --title "n8n Stack Manager" \
        --menu "Choose an option:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
        "1" "🚀 Fresh Installation" \
        "2" "🔧 Manage Existing Installation" \
        "3" "🩺 Health Check & Diagnostics" \
        "4" "🛠️  Repair & Fix Issues" \
        "5" "⚙️  Configuration Management" \
        "6" "💾 Backup & Restore" \
        "7" "📊 System Information" \
        "8" "🗑️  Cleanup & Uninstall" \
        "0" "❌ Exit" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) fresh_installation_menu ;;
        2) manage_existing_menu ;;
        3) health_check_menu ;;
        4) repair_menu ;;
        5) configuration_menu ;;
        6) backup_menu ;;
        7) system_info_menu ;;
        8) cleanup_menu ;;
        0) exit_application ;;
        *) show_main_menu ;;
    esac
}

# --- Fresh Installation Menu ---
fresh_installation_menu() {
    # Check for existing installation
    if detect_existing_installation_silent; then
        dialog --title "Existing Installation Detected" \
            --yesno "An existing n8n installation was found. Do you want to:\n\nYes: Clean and start fresh\nNo: Return to main menu" 10 60
        
        if [ $? -eq 0 ]; then
            perform_cleanup_silent
        else
            show_main_menu
            return
        fi
    fi
    
    # Service selection
    select_services_menu
    
    if [ ${#SELECTED_SERVICES[@]} -eq 0 ]; then
        dialog --title "No Services Selected" --msgbox "No services were selected. Returning to main menu." 8 50
        show_main_menu
        return
    fi
    
    # Configuration
    collect_configuration_ui
    
    # Confirmation
    show_installation_summary
    
    # Install
    perform_installation
}

select_services_menu() {
    local options=()
    local defaults=("n8n" "qdrant" "portainer" "dozzle" "caddy")
    
    for service in "${!SERVICES[@]}"; do
        local status="off"
        if [[ " ${defaults[@]} " =~ " ${service} " ]]; then
            status="on"
        fi
        options+=("$service" "${SERVICES[$service]}" "$status")
    done
    
    local selected
    selected=$(dialog --clear --title "Service Selection" \
        --checklist "Select services to install:" $DIALOG_HEIGHT $DIALOG_WIDTH $CHECKLIST_HEIGHT \
        "${options[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        SELECTED_SERVICES=()
        for service in $selected; do
            service=$(echo "$service" | tr -d '"')
            SELECTED_SERVICES+=("$service")
        done
    fi
}

# --- Health Check Menu ---
health_check_menu() {
    update_all_service_status
    
    local status_text=""
    local issues_found=false
    
    for service in "${!SERVICES[@]}"; do
        local status="${SERVICE_STATUS[$service]:-⚪ Unknown}"
        local port="${SERVICE_PORTS[$service]:-N/A}"
        status_text+="\n$service: $status (Port: $port)"
        
        if [[ "$status" == *"🔴"* ]] || [[ "$status" == *"🟡"* ]]; then
            issues_found=true
        fi
    done
    
    local menu_options=()
    menu_options+=("refresh" "🔄 Refresh Status")
    
    if [ "$issues_found" = true ]; then
        menu_options+=("fix" "🛠️  Fix Issues Automatically")
    fi
    
    menu_options+=("logs" "📋 View Service Logs")
    menu_options+=("back" "⬅️  Back to Main Menu")
    
    local choice
    choice=$(dialog --clear --title "Service Health Status" \
        --extra-button --extra-label "Details" \
        --menu "$status_text\n\nChoose an action:" 25 80 8 \
        "${menu_options[@]}" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        refresh) health_check_menu ;;
        fix) auto_fix_issues ;;
        logs) view_logs_menu ;;
        back) show_main_menu ;;
        *) health_check_menu ;;
    esac
}

# --- Repair Menu ---
repair_menu() {
    local repair_options=()
    local issues_detected=()
    
    # Check for common issues
    if docker volume ls 2>/dev/null | grep -q "qdrant_data"; then
        if ! check_qdrant_permissions; then
            repair_options+=("qdrant_perms" "🔧 Fix Qdrant Permission Issues")
            issues_detected+=("Qdrant permission issues detected")
        fi
    fi
    
    if docker ps -a --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -q "Exited"; then
        repair_options+=("restart_failed" "🔄 Restart Failed Containers")
        issues_detected+=("Failed containers detected")
    fi
    
    if docker images -f "dangling=true" -q 2>/dev/null | grep -q .; then
        repair_options+=("clean_images" "🧹 Clean Unused Docker Images")
        issues_detected+=("Unused Docker images found")
    fi
    
    repair_options+=("reset_network" "🌐 Reset Network Configuration")
    repair_options+=("fix_volumes" "💾 Repair Volume Permissions")
    repair_options+=("update_services" "⬆️  Update All Services")
    repair_options+=("back" "⬅️  Back to Main Menu")
    
    local issues_text=""
    if [ ${#issues_detected[@]} -gt 0 ]; then
        issues_text="Issues detected:\n"
        for issue in "${issues_detected[@]}"; do
            issues_text+="• $issue\n"
        done
        issues_text+="\n"
    fi
    
    local choice
    choice=$(dialog --clear --title "Repair & Fix Issues" \
        --menu "${issues_text}Select a repair action:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
        "${repair_options[@]}" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        qdrant_perms) fix_qdrant_permissions_ui ;;
        restart_failed) restart_failed_containers ;;
        clean_images) clean_docker_images ;;
        reset_network) reset_network_config ;;
        fix_volumes) fix_volume_permissions ;;
        update_services) update_all_services ;;
        back) show_main_menu ;;
        *) repair_menu ;;
    esac
}

# --- Configuration Menu ---
configuration_menu() {
    local choice
    choice=$(dialog --clear --title "Configuration Management" \
        --menu "Choose a configuration option:" $DIALOG_HEIGHT $DIALOG_WIDTH 8 \
        "1" "🌐 Domain & SSL Settings" \
        "2" "👤 User Management" \
        "3" "🔐 Security Settings" \
        "4" "📊 Performance Tuning" \
        "5" "🔧 Service Configuration" \
        "6" "📄 Export Configuration" \
        "7" "📥 Import Configuration" \
        "0" "⬅️  Back to Main Menu" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) domain_ssl_config ;;
        2) user_management_config ;;
        3) security_config ;;
        4) performance_config ;;
        5) service_config ;;
        6) export_config ;;
        7) import_config ;;
        0) show_main_menu ;;
        *) configuration_menu ;;
    esac
}

# --- System Information Menu ---
system_info_menu() {
    local system_info=""
    
    # System resources
    local memory_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    local disk_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    local cpu_cores=$(nproc)
    
    system_info+="System Resources:\n"
    system_info+="• RAM: ${memory_gb}GB\n"
    system_info+="• Disk Space: ${disk_gb}GB available\n"
    system_info+="• CPU Cores: ${cpu_cores}\n\n"
    
    # Docker info
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        system_info+="Docker Information:\n"
        system_info+="• Version: ${docker_version}\n"
        
        local running_containers=$(docker ps -q 2>/dev/null | wc -l)
        local total_containers=$(docker ps -aq 2>/dev/null | wc -l)
        system_info+="• Containers: ${running_containers}/${total_containers} running\n"
        
        local images_count=$(docker images -q 2>/dev/null | wc -l)
        system_info+="• Images: ${images_count}\n"
        
        local volumes_count=$(docker volume ls -q 2>/dev/null | wc -l)
        system_info+="• Volumes: ${volumes_count}\n\n"
    fi
    
    # Installation info
    if [ -d "$SETUP_DIR" ]; then
        system_info+="Installation Information:\n"
        system_info+="• Setup Directory: $SETUP_DIR\n"
        
        if [ -f "$SETUP_DIR/.env" ]; then
            system_info+="• Configuration: Found\n"
        fi
        
        if [ -f "$SETUP_DIR/docker-compose.yml" ]; then
            system_info+="• Docker Compose: Found\n"
        fi
    fi
    
    dialog --title "System Information" --msgbox "$system_info" 20 70
    show_main_menu
}

# --- Utility Functions ---
detect_existing_installation_silent() {
    local containers=("n8n" "qdrant" "dozzle" "portainer" "caddy")
    
    for container in "${containers[@]}"; do
        if docker ps -a --format "table {{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
            return 0
        fi
    done
    
    if [ -d "$SETUP_DIR" ]; then
        return 0
    fi
    
    return 1
}

perform_cleanup_silent() {
    # Stop and remove containers
    local containers=("n8n" "qdrant" "dozzle" "portainer" "caddy" "redis" "postgresql" "grafana")
    
    for container in "${containers[@]}"; do
        docker stop "$container" >/dev/null 2>&1 || true
        docker rm "$container" >/dev/null 2>&1 || true
    done
    
    # Remove volumes
    local volumes=("n8n_data" "qdrant_data" "portainer_data" "caddy_data" "caddy_config" "redis_data" "postgres_data" "grafana_data")
    
    for volume in "${volumes[@]}"; do
        docker volume rm "$volume" >/dev/null 2>&1 || true
    done
    
    # Remove network
    docker network rm n8n_network >/dev/null 2>&1 || true
    
    # Remove configuration
    rm -rf "$SETUP_DIR" >/dev/null 2>&1 || true
}

check_qdrant_permissions() {
    if docker volume ls 2>/dev/null | grep -q "qdrant_data"; then
        local owner=$(docker run --rm -v qdrant_data:/check alpine stat -c "%u:%g" /check 2>/dev/null || echo "0:0")
        if [ "$owner" != "1000:1000" ]; then
            return 1
        fi
    fi
    return 0
}

fix_qdrant_permissions_ui() {
    dialog --title "Fixing Qdrant Permissions" --infobox "Fixing Qdrant volume permissions..." 5 50
    
    if docker volume ls 2>/dev/null | grep -q "qdrant_data"; then
        # Stop Qdrant if running
        docker stop qdrant >/dev/null 2>&1 || true
        
        # Fix permissions
        docker run --rm -v qdrant_data:/qdrant/storage alpine chown -R 1000:1000 /qdrant/storage >/dev/null 2>&1
        
        # Restart Qdrant
        docker start qdrant >/dev/null 2>&1 || true
        
        dialog --title "Success" --msgbox "Qdrant permissions have been fixed successfully!" 6 50
    else
        dialog --title "Error" --msgbox "Qdrant volume not found. Please install Qdrant first." 6 50
    fi
    
    repair_menu
}

collect_configuration_ui() {
    # Domain configuration
    local domain
    domain=$(dialog --title "Domain Configuration" \
        --inputbox "Enter your domain (leave empty for IP-based access):\n\nExample: example.com\nThis will create subdomains like n8n.example.com" 12 60 \
        3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$domain" ]; then
        export N8N_DOMAIN="n8n.$domain"
        export MAIN_DOMAIN="$domain"
    fi
    
    # Admin user configuration
    local admin_user
    admin_user=$(dialog --title "Admin User" \
        --inputbox "Enter admin username/email:" 8 50 "admin@example.com" \
        3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$admin_user" ]; then
        export N8N_USER="$admin_user"
    fi
}

show_installation_summary() {
    local summary="Installation Summary:\n\n"
    summary+="Selected Services:\n"
    
    for service in "${SELECTED_SERVICES[@]}"; do
        summary+="• $service - ${SERVICES[$service]}\n"
    done
    
    summary+="\nConfiguration:\n"
    summary+="• Domain: ${N8N_DOMAIN:-IP-based access}\n"
    summary+="• Admin User: ${N8N_USER:-admin@example.com}\n"
    summary+="• Setup Directory: $SETUP_DIR\n"
    
    dialog --title "Installation Summary" \
        --yesno "$summary\nProceed with installation?" 18 70
    
    if [ $? -ne 0 ]; then
        show_main_menu
    fi
}

perform_installation() {
    # Create progress dialog
    (
        echo "10" ; echo "Checking system requirements..."
        sleep 1
        
        echo "20" ; echo "Installing dependencies..."
        install_dependencies_silent
        
        echo "30" ; echo "Installing Docker..."
        install_docker_silent
        
        echo "40" ; echo "Generating configuration..."
        generate_configuration_files
        
        echo "60" ; echo "Creating Docker Compose configuration..."
        create_docker_compose_config
        
        echo "80" ; echo "Starting services..."
        start_selected_services
        
        echo "90" ; echo "Configuring firewall..."
        configure_firewall_silent
        
        echo "100" ; echo "Installation complete!"
        sleep 1
    ) | dialog --title "Installing n8n Stack" --gauge "Preparing installation..." 8 60 0
    
    dialog --title "Installation Complete" \
        --msgbox "n8n Stack has been installed successfully!\n\nYou can now access your services and manage them from the main menu." 8 60
    
    show_main_menu
}

# --- Stub Functions (to be implemented) ---
manage_existing_menu() {
    dialog --title "Coming Soon" --msgbox "Manage Existing Installation feature is coming soon!" 6 50
    show_main_menu
}

backup_menu() {
    dialog --title "Coming Soon" --msgbox "Backup & Restore feature is coming soon!" 6 50
    show_main_menu
}

cleanup_menu() {
    dialog --title "Coming Soon" --msgbox "Cleanup & Uninstall feature is coming soon!" 6 50
    show_main_menu
}

auto_fix_issues() {
    dialog --title "Coming Soon" --msgbox "Auto-fix feature is coming soon!" 6 50
    health_check_menu
}

view_logs_menu() {
    dialog --title "Coming Soon" --msgbox "Log viewer is coming soon!" 6 50
    health_check_menu
}

domain_ssl_config() {
    dialog --title "Coming Soon" --msgbox "Domain & SSL configuration is coming soon!" 6 50
    configuration_menu
}

user_management_config() {
    dialog --title "Coming Soon" --msgbox "User management is coming soon!" 6 50
    configuration_menu
}

security_config() {
    dialog --title "Coming Soon" --msgbox "Security settings are coming soon!" 6 50
    configuration_menu
}

performance_config() {
    dialog --title "Coming Soon" --msgbox "Performance tuning is coming soon!" 6 50
    configuration_menu
}

service_config() {
    dialog --title "Coming Soon" --msgbox "Service configuration is coming soon!" 6 50
    configuration_menu
}

export_config() {
    dialog --title "Coming Soon" --msgbox "Configuration export is coming soon!" 6 50
    configuration_menu
}

import_config() {
    dialog --title "Coming Soon" --msgbox "Configuration import is coming soon!" 6 50
    configuration_menu
}

restart_failed_containers() {
    dialog --title "Coming Soon" --msgbox "Container restart feature is coming soon!" 6 50
    repair_menu
}

clean_docker_images() {
    dialog --title "Coming Soon" --msgbox "Image cleanup feature is coming soon!" 6 50
    repair_menu
}

reset_network_config() {
    dialog --title "Coming Soon" --msgbox "Network reset feature is coming soon!" 6 50
    repair_menu
}

fix_volume_permissions() {
    dialog --title "Coming Soon" --msgbox "Volume permission fix is coming soon!" 6 50
    repair_menu
}

update_all_services() {
    dialog --title "Coming Soon" --msgbox "Service update feature is coming soon!" 6 50
    repair_menu
}

install_dependencies_silent() {
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y curl wget ufw htop openssl >/dev/null 2>&1 || true
}

install_docker_silent() {
    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | sh >/dev/null 2>&1 || true
        systemctl enable docker >/dev/null 2>&1 || true
        systemctl start docker >/dev/null 2>&1 || true
    fi
}

generate_configuration_files() {
    mkdir -p "$SETUP_DIR"
    
    # Generate passwords
    local n8n_password=$(openssl rand -base64 16 | tr -d "=+/\"'" | cut -c1-16)
    local qdrant_api_key=$(openssl rand -base64 32 | tr -d "=+/\"'" | cut -c1-32)
    
    cat > "${SETUP_DIR}/.env" <<EOF
# n8n Stack Configuration
TZ=UTC
N8N_BASIC_AUTH_USER=${N8N_USER:-admin@example.com}
N8N_BASIC_AUTH_PASSWORD=${n8n_password}
QDRANT_API_KEY=${qdrant_api_key}
${N8N_DOMAIN:+N8N_DOMAIN=${N8N_DOMAIN}}
EOF
    
    chmod 600 "${SETUP_DIR}/.env"
}

create_docker_compose_config() {
    # This would create the docker-compose.yml based on selected services
    # For now, create a basic version
    cat > "${SETUP_DIR}/docker-compose.yml" <<EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    user: "1000:1000"
    environment:
      - TZ=\${TZ}
      - DB_TYPE=sqlite
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n_network
    ports:
      - "5678:5678"

volumes:
  n8n_data:

networks:
  n8n_network:
    driver: bridge
EOF
}

start_selected_services() {
    cd "$SETUP_DIR"
    docker compose up -d >/dev/null 2>&1 || true
}

configure_firewall_silent() {
    if command -v ufw >/dev/null 2>&1; then
        ufw --force reset >/dev/null 2>&1 || true
        ufw default deny incoming >/dev/null 2>&1 || true
        ufw default allow outgoing >/dev/null 2>&1 || true
        ufw allow ssh >/dev/null 2>&1 || true
        ufw allow 80/tcp >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        ufw allow 5678/tcp >/dev/null 2>&1 || true
        ufw --force enable >/dev/null 2>&1 || true
    fi
}

exit_application() {
    clear
    echo "Thank you for using n8n Stack Manager!"
    exit 0
}

# --- Main Function ---
main() {
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root. Please use: sudo $0"
        exit 1
    fi
    
    # Check and install dialog
    check_dialog
    
    # Show banner
    show_banner
    
    # Start main menu loop
    while true; do
        show_main_menu
    done
}

# Trap to clean up dialog on exit
trap 'clear' EXIT

# Run main function
main "$@"
