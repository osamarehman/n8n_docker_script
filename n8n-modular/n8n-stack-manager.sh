#!/bin/bash

# ==============================================================================
# n8n Stack Manager - Interactive UI-Driven Management System
# A comprehensive tool for installing, managing, and maintaining n8n Docker stacks
# Integrates with the modular installation scripts
# ==============================================================================

set -euo pipefail

# --- Configuration ---
readonly SCRIPT_NAME="n8n Stack Manager"
readonly SCRIPT_VERSION="3.0.0-modular-ui"
readonly MIN_RAM_GB=2
readonly MIN_DISK_GB=8
readonly SETUP_DIR="/opt/n8n-stack"
readonly MODULAR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# UI Configuration
readonly DIALOG_HEIGHT=20
readonly DIALOG_WIDTH=70
readonly CHECKLIST_HEIGHT=15

# Service definitions - updated to match modular scripts
declare -A SERVICES=(
    ["n8n"]="Core Workflow Automation Platform (Required)"
    ["caddy"]="Reverse Proxy with Automatic HTTPS"
    ["qdrant"]="Vector Database for AI/ML Workflows"
    ["portainer"]="Docker Management Web Interface"
    ["watchtower"]="Automatic Container Updates"
)

declare -A SERVICE_PORTS=(
    ["n8n"]="5678"
    ["caddy"]="80,443"
    ["qdrant"]="6333"
    ["portainer"]="9000"
    ["watchtower"]="N/A"
)

declare -A SERVICE_DESCRIPTIONS=(
    ["n8n"]="Essential for workflow automation - always required"
    ["caddy"]="Enables HTTPS and domain routing - recommended with domain"
    ["qdrant"]="Perfect for AI workflows and vector searches"
    ["portainer"]="Easy Docker container management via web UI"
    ["watchtower"]="Keeps containers updated automatically"
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
    dialog --title "Welcome" --msgbox "\n🚀 n8n Stack Manager v${SCRIPT_VERSION}\n\nA comprehensive UI for managing your modular n8n Docker infrastructure.\n\n✨ Features:\n• Interactive service selection\n• Modular component installation\n• Real-time health monitoring\n• Configuration management\n• Backup & restore capabilities\n• Individual service management\n\n🎯 Built on modular architecture for maximum flexibility!" 18 65
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

check_modular_scripts() {
    local missing_scripts=()
    for service in "${!SERVICES[@]}"; do
        local script_path="${MODULAR_DIR}/scripts/install-${service}.sh"
        if [ ! -f "$script_path" ]; then
            missing_scripts+=("$service")
        fi
    done
    
    if [ ${#missing_scripts[@]} -gt 0 ]; then
        dialog --title "Missing Scripts" --msgbox "The following modular installation scripts are missing:\n\n$(printf '%s\n' "${missing_scripts[@]}")\n\nPlease ensure all modular scripts are in:\n${MODULAR_DIR}/scripts/" 12 60
        return 1
    fi
    return 0
}

# --- Main Menu Functions ---
show_main_menu() {
    local choice
    choice=$(dialog --clear --title "n8n Stack Manager" \
        --menu "Choose an option:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 \
        "1" "🚀 Fresh Installation (Modular)" \
        "2" "🔧 Manage Existing Installation" \
        "3" "🩺 Health Check & Diagnostics" \
        "4" "🛠️  Repair & Fix Issues" \
        "5" "⚙️  Individual Service Management" \
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
        5) individual_service_menu ;;
        6) backup_menu ;;
        7) system_info_menu ;;
        8) cleanup_menu ;;
        0) exit_application ;;
        *) show_main_menu ;;
    esac
}

# --- Fresh Installation Menu ---
fresh_installation_menu() {
    if ! check_modular_scripts; then
        show_main_menu
        return
    fi
    
    # Check for existing installation
    if detect_existing_installation_silent; then
        dialog --title "Existing Installation Detected" \
            --yesno "An existing n8n installation was found. Do you want to:\n\nYes: Clean and start fresh\nNo: Return to main menu\n\nWARNING: This will remove all existing data!" 12 60
        
        if [ $? -eq 0 ]; then
            perform_full_cleanup_silent
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
    perform_modular_installation
}

select_services_menu() {
    local options=()
    local defaults=("n8n" "caddy" "qdrant" "portainer")
    
    for service in "${!SERVICES[@]}"; do
        local status="off"
        if [[ " ${defaults[@]} " =~ " ${service} " ]]; then
            status="on"
        fi
        options+=("$service" "${SERVICES[$service]}" "$status")
    done
    
    local selected
    selected=$(dialog --clear --title "Service Selection" \
        --checklist "Select services to install:\n\n🔵 n8n is required for the stack to function\n🔵 Caddy provides HTTPS (recommended with domain)\n🔵 Other services are optional but enhance functionality" \
        $DIALOG_HEIGHT $DIALOG_WIDTH $CHECKLIST_HEIGHT \
        "${options[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        SELECTED_SERVICES=()
        # Ensure n8n is always included
        local has_n8n=false
        for service in $selected; do
            service=$(echo "$service" | tr -d '"')
            SELECTED_SERVICES+=("$service")
            if [ "$service" = "n8n" ]; then
                has_n8n=true
            fi
        done
        
        if [ "$has_n8n" = false ]; then
            SELECTED_SERVICES=("n8n" "${SELECTED_SERVICES[@]}")
            dialog --title "n8n Added" --msgbox "n8n has been automatically added as it's required for the stack to function." 7 50
        fi
    fi
}

# --- Individual Service Management Menu ---
individual_service_menu() {
    update_all_service_status
    
    local menu_options=()
    for service in "${!SERVICES[@]}"; do
        local status="${SERVICE_STATUS[$service]:-⚪ Unknown}"
        menu_options+=("$service" "$status - ${SERVICE_DESCRIPTIONS[$service]}")
    done
    
    menu_options+=("back" "⬅️  Back to Main Menu")
    
    local choice
    choice=$(dialog --clear --title "Individual Service Management" \
        --menu "Select a service to manage:" 18 80 10 \
        "${menu_options[@]}" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        back) show_main_menu ;;
        *) manage_individual_service "$choice" ;;
    esac
}

manage_individual_service() {
    local service="$1"
    local status="${SERVICE_STATUS[$service]:-⚪ Unknown}"
    
    local service_options=()
    
    if [[ "$status" == *"⚪ Not Installed"* ]]; then
        service_options+=("install" "📥 Install $service")
    else
        service_options+=("status" "📊 Show Status")
        service_options+=("logs" "📋 View Logs")
        
        if [[ "$status" == *"🟢 Running"* ]]; then
            service_options+=("stop" "⏹️  Stop Service")
            service_options+=("restart" "🔄 Restart Service")
        elif [[ "$status" == *"🔴 Stopped"* ]] || [[ "$status" == *"🟡 Exists"* ]]; then
            service_options+=("start" "▶️  Start Service")
        fi
        
        service_options+=("update" "⬆️  Update Service")
        service_options+=("remove" "🗑️  Remove Service")
    fi
    
    service_options+=("back" "⬅️  Back to Service List")
    
    local choice
    choice=$(dialog --clear --title "$service Management" \
        --menu "Service: $service\nStatus: $status\n\nSelect an action:" 15 60 8 \
        "${service_options[@]}" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        install) install_individual_service "$service" ;;
        status) show_service_status "$service" ;;
        logs) show_service_logs "$service" ;;
        start) start_service "$service" ;;
        stop) stop_service "$service" ;;
        restart) restart_service "$service" ;;
        update) update_service "$service" ;;
        remove) remove_service "$service" ;;
        back) individual_service_menu ;;
        *) manage_individual_service "$service" ;;
    esac
}

install_individual_service() {
    local service="$1"
    local script_path="${MODULAR_DIR}/scripts/install-${service}.sh"
    
    if [ ! -f "$script_path" ]; then
        dialog --title "Error" --msgbox "Installation script not found:\n$script_path" 8 60
        manage_individual_service "$service"
        return
    fi
    
    # Collect configuration for this service
    collect_service_configuration "$service"
    
    dialog --title "Installing $service" --infobox "Installing $service...\nThis may take a few minutes." 6 50
    
    # Run the modular installation script
    if bash "$script_path" --auto; then
        dialog --title "Success" --msgbox "$service has been installed successfully!" 6 50
    else
        dialog --title "Error" --msgbox "$service installation failed. Check the logs for details." 7 60
    fi
    
    manage_individual_service "$service"
}

collect_service_configuration() {
    local service="$1"
    
    case "$service" in
        "caddy"|"n8n"|"qdrant"|"portainer")
            # Domain configuration for services that can use it
            local domain
            domain=$(dialog --title "Domain Configuration" \
                --inputbox "Enter your domain for $service (leave empty for IP access):\n\nExample: yourdomain.com\nThis will create: ${service}.yourdomain.com" 10 60 \
                3>&1 1>&2 2>&3)
            
            if [ $? -eq 0 ] && [ -n "$domain" ]; then
                export MAIN_DOMAIN="$domain"
                case "$service" in
                    "n8n") export N8N_DOMAIN="n8n.$domain" ;;
                    "caddy") export MAIN_DOMAIN="$domain" ;;
                    "qdrant") export QDRANT_DOMAIN="qdrant.$domain" ;;
                    "portainer") export PORTAINER_DOMAIN="portainer.$domain" ;;
                esac
            fi
            ;;
    esac
    
    # Service-specific configuration
    case "$service" in
        "n8n")
            local admin_user
            admin_user=$(dialog --title "n8n Admin User" \
                --inputbox "Enter admin username/email:" 8 50 "admin@example.com" \
                3>&1 1>&2 2>&3)
            
            if [ $? -eq 0 ] && [ -n "$admin_user" ]; then
                export N8N_USER="$admin_user"
            fi
            ;;
        "watchtower")
            local interval
            interval=$(dialog --title "Watchtower Configuration" \
                --inputbox "Update check interval in hours:" 8 40 "24" \
                3>&1 1>&2 2>&3)
            
            if [ $? -eq 0 ] && [ -n "$interval" ]; then
                export WATCHTOWER_POLL_INTERVAL=$((interval * 3600))
            fi
            ;;
    esac
}

# --- Service Control Functions ---
start_service() {
    local service="$1"
    local compose_file="${SETUP_DIR}/docker-compose.${service}.yml"
    
    if [ -f "$compose_file" ]; then
        dialog --title "Starting $service" --infobox "Starting $service..." 5 40
        if docker compose -f "$compose_file" start; then
            dialog --title "Success" --msgbox "$service started successfully!" 6 40
        else
            dialog --title "Error" --msgbox "Failed to start $service" 6 40
        fi
    else
        dialog --title "Error" --msgbox "Configuration file not found: $compose_file" 7 50
    fi
    
    manage_individual_service "$service"
}

stop_service() {
    local service="$1"
    local compose_file="${SETUP_DIR}/docker-compose.${service}.yml"
    
    if [ -f "$compose_file" ]; then
        dialog --title "Stopping $service" --infobox "Stopping $service..." 5 40
        if docker compose -f "$compose_file" stop; then
            dialog --title "Success" --msgbox "$service stopped successfully!" 6 40
        else
            dialog --title "Error" --msgbox "Failed to stop $service" 6 40
        fi
    else
        dialog --title "Error" --msgbox "Configuration file not found: $compose_file" 7 50
    fi
    
    manage_individual_service "$service"
}

restart_service() {
    local service="$1"
    local compose_file="${SETUP_DIR}/docker-compose.${service}.yml"
    
    if [ -f "$compose_file" ]; then
        dialog --title "Restarting $service" --infobox "Restarting $service..." 5 40
        if docker compose -f "$compose_file" restart; then
            dialog --title "Success" --msgbox "$service restarted successfully!" 6 40
        else
            dialog --title "Error" --msgbox "Failed to restart $service" 6 40
        fi
    else
        dialog --title "Error" --msgbox "Configuration file not found: $compose_file" 7 50
    fi
    
    manage_individual_service "$service"
}

update_service() {
    local service="$1"
    local compose_file="${SETUP_DIR}/docker-compose.${service}.yml"
    
    if [ -f "$compose_file" ]; then
        dialog --title "Updating $service" --infobox "Updating $service...\nThis may take a few minutes." 6 40
        if docker compose -f "$compose_file" pull && docker compose -f "$compose_file" up -d; then
            dialog --title "Success" --msgbox "$service updated successfully!" 6 40
        else
            dialog --title "Error" --msgbox "Failed to update $service" 6 40
        fi
    else
        dialog --title "Error" --msgbox "Configuration file not found: $compose_file" 7 50
    fi
    
    manage_individual_service "$service"
}

remove_service() {
    local service="$1"
    
    dialog --title "Remove $service" \
        --yesno "Are you sure you want to remove $service?\n\nThis will:\n• Stop the service\n• Remove the container\n• Keep data volumes (safe)\n\nData can be recovered by reinstalling." 12 50
    
    if [ $? -eq 0 ]; then
        local script_path="${MODULAR_DIR}/scripts/install-${service}.sh"
        
        dialog --title "Removing $service" --infobox "Removing $service..." 5 40
        
        if [ -f "$script_path" ] && bash "$script_path" --cleanup; then
            dialog --title "Success" --msgbox "$service removed successfully!\n\nData volumes were preserved and can be recovered by reinstalling the service." 8 50
        else
            dialog --title "Error" --msgbox "Failed to remove $service cleanly.\nYou may need to remove it manually." 7 50
        fi
    fi
    
    individual_service_menu
}

show_service_status() {
    local service="$1"
    local status_info=""
    
    # Container status
    if docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "^${service}"; then
        status_info+="Container Status:\n"
        status_info+="$(docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "^${service}" || echo "Not found")\n\n"
    fi
    
    # Resource usage if running
    if docker ps --format "table {{.Names}}" | grep -q "^${service}$"; then
        status_info+="Resource Usage:\n"
        status_info+="$(docker stats "$service" --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || echo "Unable to get stats")\n\n"
    fi
    
    # Health check if available
    local health=$(docker inspect "$service" --format='{{.State.Health.Status}}' 2>/dev/null || echo "no healthcheck")
    if [ "$health" != "no healthcheck" ]; then
        status_info+="Health Status: $health\n\n"
    fi
    
    # Configuration file
    local compose_file="${SETUP_DIR}/docker-compose.${service}.yml"
    if [ -f "$compose_file" ]; then
        status_info+="Configuration: $compose_file ✓\n"
    else
        status_info+="Configuration: Missing ❌\n"
    fi
    
    dialog --title "$service Status" --msgbox "$status_info" 15 70
    manage_individual_service "$service"
}

show_service_logs() {
    local service="$1"
    
    if docker ps --format "table {{.Names}}" | grep -q "^${service}$"; then
        # Get last 50 lines of logs
        local logs
        logs=$(docker logs "$service" --tail 50 2>&1 || echo "Unable to retrieve logs")
        
        # Show in scrollable dialog
        echo "$logs" > "/tmp/${service}_logs.txt"
        dialog --title "$service Logs (Last 50 lines)" --textbox "/tmp/${service}_logs.txt" 20 80
        rm -f "/tmp/${service}_logs.txt"
    else
        dialog --title "Error" --msgbox "$service is not running. Cannot show logs." 6 50
    fi
    
    manage_individual_service "$service"
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
    menu_options+=("stack" "📊 Full Stack Status")
    menu_options+=("back" "⬅️  Back to Main Menu")
    
    local choice
    choice=$(dialog --clear --title "Service Health Status" \
        --menu "$status_text\n\nChoose an action:" 20 80 8 \
        "${menu_options[@]}" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        refresh) health_check_menu ;;
        fix) auto_fix_issues ;;
        logs) view_logs_menu ;;
        stack) show_stack_status ;;
        back) show_main_menu ;;
        *) health_check_menu ;;
    esac
}

show_stack_status() {
    local stack_info=""
    
    # Check if stack management script exists
    if [ -f "${SETUP_DIR}/manage-stack.sh" ]; then
        stack_info+="Stack Management: Available ✓\n\n"
        
        # Get stack status
        cd "${SETUP_DIR}" 2>/dev/null || true
        stack_info+="$(bash manage-stack.sh status 2>/dev/null | head -20 || echo "Unable to get stack status")\n"
    else
        stack_info+="Stack Management: Not Available\n\n"
        stack_info+="Individual container status:\n"
        for service in "${!SERVICES[@]}"; do
            if docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep -q "^${service}"; then
                stack_info+="$(docker ps -a --format "table {{.Names}}\t{{.Status}}" | grep "^${service}")\n"
            fi
        done
    fi
    
    dialog --title "Full Stack Status" --msgbox "$stack_info" 20 80
    health_check_menu
}

# --- Configuration Collection ---
collect_configuration_ui() {
    # Domain configuration
    local domain
    domain=$(dialog --title "Domain Configuration" \
        --inputbox "Enter your domain for HTTPS setup (leave empty for IP access):\n\nExample: yourdomain.com\nThis will create subdomains like n8n.yourdomain.com\n\nLeave empty to use IP addresses and HTTP only." 12 60 \
        3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$domain" ]; then
        export MAIN_DOMAIN="$domain"
        export N8N_DOMAIN="n8n.$domain"
    fi
    
    # Admin user configuration
    local admin_user
    admin_user=$(dialog --title "Admin User" \
        --inputbox "Enter n8n admin username/email:" 8 50 "admin@example.com" \
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
    summary+="• Domain: ${MAIN_DOMAIN:-IP-based access}\n"
    summary+="• n8n Admin: ${N8N_USER:-admin@example.com}\n"
    summary+="• Setup Directory: $SETUP_DIR\n"
    summary+="• Installation Method: Modular Scripts\n"
    
    if [ -n "${MAIN_DOMAIN:-}" ]; then
        summary+="\n⚠️  DNS Configuration Required:\n"
        for service in "${SELECTED_SERVICES[@]}"; do
            if [[ "$service" =~ ^(n8n|caddy|qdrant|portainer)$ ]]; then
                summary+="• ${service}.${MAIN_DOMAIN} → [server-ip]\n"
            fi
        done
    fi
    
    dialog --title "Installation Summary" \
        --yesno "$summary\nProceed with modular installation?" 20 70
    
    if [ $? -ne 0 ]; then
        show_main_menu
    fi
}

perform_modular_installation() {
    # Create progress dialog with modular installation steps
    (
        echo "5" ; echo "Preparing environment..."
        sleep 1
        
        echo "10" ; echo "Setting up environment variables..."
        # Export all configuration for modular scripts
        export INSTALL_N8N="no"
        export INSTALL_CADDY="no"
        export INSTALL_QDRANT="no"
        export INSTALL_PORTAINER="no"
        export INSTALL_WATCHTOWER="no"
        
        for service in "${SELECTED_SERVICES[@]}"; do
            case "$service" in
                "n8n") export INSTALL_N8N="yes" ;;
                "caddy") export INSTALL_CADDY="yes" ;;
                "qdrant") export INSTALL_QDRANT="yes" ;;
                "portainer") export INSTALL_PORTAINER="yes" ;;
                "watchtower") export INSTALL_WATCHTOWER="yes" ;;
            esac
        done
        
        local progress=15
        local step_size=$((70 / ${#SELECTED_SERVICES[@]}))
        
        for service in "${SELECTED_SERVICES[@]}"; do
            echo "$progress" ; echo "Installing $service..."
            
            local script_path="${MODULAR_DIR}/scripts/install-${service}.sh"
            if [ -f "$script_path" ]; then
                if ! bash "$script_path" --auto; then
                    echo "100" ; echo "Error installing $service!"
                    sleep 2
                    exit 1
                fi
            fi
            
            progress=$((progress + step_size))
        done
        
        echo "90" ; echo "Finalizing installation..."
        sleep 1
        
        echo "95" ; echo "Creating management scripts..."
        # The modular scripts should have created manage-stack.sh
        
        echo "100" ; echo "Installation complete!"
        sleep 1
        
    ) | dialog --title "Installing n8n Modular Stack" --gauge "Preparing installation..." 8 60 0
    
    local install_result=$?
    
    if [ $install_result -eq 0 ]; then
        show_installation_complete
    else
        dialog --title "Installation Failed" \
            --msgbox "The installation encountered errors.\n\nPlease check the system logs and try again.\nYou can also try installing individual services from the main menu." 10 60
    fi
    
    show_main_menu
}

show_installation_complete() {
    local completion_text="🎉 n8n Modular Stack Installation Complete!\n\n"
    completion_text+="Installed Services:\n"
    
    for service in "${SELECTED_SERVICES[@]}"; do
        completion_text+="✓ $service\n"
    done
    
    completion_text+="\nAccess Information:\n"
    if [ -n "${MAIN_DOMAIN:-}" ]; then
        completion_text+="🌐 HTTPS Access (after DNS setup):\n"
        [[ " ${SELECTED_SERVICES[*]} " =~ " n8n " ]] && completion_text+="• n8n: https://n8n.${MAIN_DOMAIN}\n"
        [[ " ${SELECTED_SERVICES[*]} " =~ " portainer " ]] && completion_text+="• Portainer: https://portainer.${MAIN_DOMAIN}\n"
        [[ " ${SELECTED_SERVICES[*]} " =~ " qdrant " ]] && completion_text+="• Qdrant: https://qdrant.${MAIN_DOMAIN}\n"
    else
        local public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "your-server-ip")
        completion_text+="🌐 HTTP Access:\n"
        [[ " ${SELECTED_SERVICES[*]} " =~ " n8n " ]] && completion_text+="• n8n: http://${public_ip}:5678\n"
        [[ " ${SELECTED_SERVICES[*]} " =~ " portainer " ]] && completion_text+="• Portainer: http://${public_ip}:9000\n"
        [[ " ${SELECTED_SERVICES[*]} " =~ " qdrant " ]] && completion_text+="• Qdrant: http://${public_ip}:6333\n"
    fi
    
    completion_text+="\n🛠️  Management:\n"
    completion_text+="• Stack: ${SETUP_DIR}/manage-stack.sh\n"
    completion_text+="• Individual: Use this UI manager\n"
    completion_text+="\n📋 Check credentials in: ${SETUP_DIR}/.env"
    
    dialog --title "Installation Complete" --msgbox "$completion_text" 22 70
}

# --- Existing Functions (Enhanced) ---
manage_existing_menu() {
    if ! detect_existing_installation_silent; then
        dialog --title "No Installation Found" --msgbox "No existing n8n installation was found.\n\nUse 'Fresh Installation' to install the stack." 8 50
        show_main_menu
        return
    fi
    
    local choice
    choice=$(dialog --clear --title "Manage Existing Installation" \
        --menu "Choose a management option:" $DIALOG_HEIGHT $DIALOG_WIDTH 8 \
        "1" "🏃 Start All Services" \
        "2" "⏹️  Stop All Services" \
        "3" "🔄 Restart All Services" \
        "4" "⬆️  Update All Services" \
        "5" "📊 Show Stack Status" \
        "6" "📋 View Logs" \
        "7" "🔧 Individual Service Management" \
        "0" "⬅️  Back to Main Menu" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) stack_operation "start" ;;
        2) stack_operation "stop" ;;
        3) stack_operation "restart" ;;
        4) stack_operation "update" ;;
        5) show_stack_status ;;
        6) view_logs_menu ;;
        7) individual_service_menu ;;
        0) show_main_menu ;;
        *) manage_existing_menu ;;
    esac
}

stack_operation() {
    local operation="$1"
    local operation_text=""
    
    case "$operation" in
        "start") operation_text="Starting" ;;
        "stop") operation_text="Stopping" ;;
        "restart") operation_text="Restarting" ;;
        "update") operation_text="Updating" ;;
    esac
    
    dialog --title "$operation_text Stack" --infobox "$operation_text all services...\nThis may take a moment." 6 50
    
    if [ -f "${SETUP_DIR}/manage-stack.sh" ]; then
        cd "${SETUP_DIR}"
        if bash manage-stack.sh "$operation"; then
            dialog --title "Success" --msgbox "Stack $operation completed successfully!" 6 50
        else
            dialog --title "Error" --msgbox "Stack $operation failed. Check logs for details." 7 50
        fi
    else
        dialog --title "Error" --msgbox "Stack management script not found.\nTry individual service management instead." 8 50
    fi
    
    manage_existing_menu
}

# --- Enhanced Repair Menu ---
repair_menu() {
    local repair_options=()
    local issues_detected=()
    
    # Check for common issues
    update_all_service_status
    
    # Check for stopped services
    local stopped_services=()
    for service in "${!SERVICES[@]}"; do
        local status="${SERVICE_STATUS[$service]:-⚪ Unknown}"
        if [[ "$status" == *"🔴 Stopped"* ]] || [[ "$status" == *"🟡 Exists"* ]]; then
            stopped_services+=("$service")
        fi
    done
    
    if [ ${#stopped_services[@]} -gt 0 ]; then
        repair_options+=("restart_services" "🔄 Start Stopped Services")
        issues_detected+=("Stopped services: ${stopped_services[*]}")
    fi
    
    # Check for permission issues
    if docker volume ls 2>/dev/null | grep -q "n8n_data\|qdrant_data"; then
        repair_options+=("fix_permissions" "🔧 Fix Volume Permissions")
    fi
    
    # Check for network issues
    if ! docker network ls | grep -q "n8n_network"; then
        repair_options+=("fix_network" "🌐 Recreate Docker Network")
        issues_detected+=("Docker network missing")
    fi
    
    # Check for unused images
    if docker images -f "dangling=true" -q 2>/dev/null | grep -q .; then
        repair_options+=("clean_images" "🧹 Clean Unused Images")
        issues_detected+=("Unused Docker images found")
    fi
    
    # Always available options
    repair_options+=("reset_stack" "🔄 Reset Entire Stack")
    repair_options+=("logs_debug" "🔍 Debug Logs Analysis")
    repair_options+=("back" "⬅️  Back to Main Menu")
    
    local issues_text=""
    if [ ${#issues_detected[@]} -gt 0 ]; then
        issues_text="🚨 Issues detected:\n"
        for issue in "${issues_detected[@]}"; do
            issues_text+="• $issue\n"
        done
        issues_text+="\n"
    else
        issues_text="✅ No obvious issues detected.\n\n"
    fi
    
    local choice
    choice=$(dialog --clear --title "Repair & Fix Issues" \
        --menu "${issues_text}Select a repair action:" 18 70 10 \
        "${repair_options[@]}" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        restart_services) restart_stopped_services ;;
        fix_permissions) fix_all_permissions ;;
        fix_network) recreate_network ;;
        clean_images) clean_unused_images ;;
        reset_stack) reset_entire_stack ;;
        logs_debug) debug_logs_analysis ;;
        back) show_main_menu ;;
        *) repair_menu ;;
    esac
}

restart_stopped_services() {
    dialog --title "Restarting Services" --infobox "Restarting stopped services..." 5 50
    
    local restarted=()
    for service in "${!SERVICES[@]}"; do
        local status="${SERVICE_STATUS[$service]:-⚪ Unknown}"
        if [[ "$status" == *"🔴 Stopped"* ]] || [[ "$status" == *"🟡 Exists"* ]]; then
            if docker start "$service" >/dev/null 2>&1; then
                restarted+=("$service")
            fi
        fi
    done
    
    if [ ${#restarted[@]} -gt 0 ]; then
        dialog --title "Success" --msgbox "Restarted services:\n$(printf '%s\n' "${restarted[@]}")" 10 50
    else
        dialog --title "Info" --msgbox "No stopped services found to restart." 6 50
    fi
    
    repair_menu
}

fix_all_permissions() {
    dialog --title "Fixing Permissions" --infobox "Fixing volume permissions for all services..." 6 50
    
    local volumes=("n8n_data" "qdrant_data")
    local fixed=()
    
    for volume in "${volumes[@]}"; do
        if docker volume ls | grep -q "$volume"; then
            if docker run --rm -v "$volume":/fix alpine chown -R 1000:1000 /fix >/dev/null 2>&1; then
                fixed+=("$volume")
            fi
        fi
    done
    
    if [ ${#fixed[@]} -gt 0 ]; then
        dialog --title "Success" --msgbox "Fixed permissions for:\n$(printf '%s\n' "${fixed[@]}")" 10 50
    else
        dialog --title "Info" --msgbox "No volumes found or permissions were already correct." 7 50
    fi
    
    repair_menu
}

recreate_network() {
    dialog --title "Recreating Network" --infobox "Recreating Docker network..." 5 50
    
    # Remove old network
    docker network rm n8n_network >/dev/null 2>&1 || true
    
    # Create new network
    if docker network create n8n_network >/dev/null 2>&1; then
        dialog --title "Success" --msgbox "Docker network recreated successfully!\n\nYou may need to restart services to reconnect to the new network." 8 60
    else
        dialog --title "Error" --msgbox "Failed to recreate Docker network." 6 50
    fi
    
    repair_menu
}

clean_unused_images() {
    dialog --title "Cleaning Images" --infobox "Removing unused Docker images..." 5 50
    
    local removed
    removed=$(docker image prune -f 2>/dev/null || echo "0 images")
    
    dialog --title "Cleanup Complete" --msgbox "Docker image cleanup completed:\n\n$removed" 8 60
    repair_menu
}

reset_entire_stack() {
    dialog --title "Reset Stack" \
        --yesno "⚠️  WARNING: This will reset the entire stack!\n\nThis will:\n• Stop all containers\n• Remove all containers\n• Keep data volumes (safe)\n• Recreate network\n\nConfiguration and data will be preserved.\nContinue?" 12 60
    
    if [ $? -eq 0 ]; then
        dialog --title "Resetting Stack" --infobox "Resetting stack...\nThis may take a moment." 6 40
        
        # Stop all services
        for service in "${!SERVICES[@]}"; do
            docker stop "$service" >/dev/null 2>&1 || true
            docker rm "$service" >/dev/null 2>&1 || true
        done
        
        # Recreate network
        docker network rm n8n_network >/dev/null 2>&1 || true
        docker network create n8n_network >/dev/null 2>&1 || true
        
        # Restart services if compose files exist
        if [ -f "${SETUP_DIR}/manage-stack.sh" ]; then
            cd "${SETUP_DIR}"
            bash manage-stack.sh start >/dev/null 2>&1 || true
        fi
        
        dialog --title "Reset Complete" --msgbox "Stack has been reset successfully!\n\nAll services should be restarting with fresh containers." 8 60
    fi
    
    repair_menu
}

debug_logs_analysis() {
    local log_summary=""
    
    for service in "${!SERVICES[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
            log_summary+="\n=== $service ===\n"
            log_summary+="$(docker logs "$service" --tail 5 2>&1 || echo "Unable to get logs")\n"
        fi
    done
    
    if [ -n "$log_summary" ]; then
        echo "$log_summary" > "/tmp/debug_logs.txt"
        dialog --title "Debug Logs Analysis" --textbox "/tmp/debug_logs.txt" 20 80
        rm -f "/tmp/debug_logs.txt"
    else
        dialog --title "No Logs" --msgbox "No running services found to analyze." 6 50
    fi
    
    repair_menu
}

# --- Auto Fix Issues ---
auto_fix_issues() {
    dialog --title "Auto-fixing Issues" --infobox "Analyzing and fixing common issues...\nThis may take a moment." 6 60
    
    local fixes_applied=()
    
    # Fix stopped services
    for service in "${!SERVICES[@]}"; do
        local status="${SERVICE_STATUS[$service]:-⚪ Unknown}"
        if [[ "$status" == *"🔴 Stopped"* ]]; then
            if docker start "$service" >/dev/null 2>&1; then
                fixes_applied+=("Started $service")
            fi
        fi
    done
    
    # Fix permissions
    local volumes=("n8n_data" "qdrant_data")
    for volume in "${volumes[@]}"; do
        if docker volume ls | grep -q "$volume"; then
            if docker run --rm -v "$volume":/fix alpine chown -R 1000:1000 /fix >/dev/null 2>&1; then
                fixes_applied+=("Fixed permissions for $volume")
            fi
        fi
    done
    
    # Show results
    if [ ${#fixes_applied[@]} -gt 0 ]; then
        local fixes_text="Auto-fix completed! Applied fixes:\n\n"
        for fix in "${fixes_applied[@]}"; do
            fixes_text+="✓ $fix\n"
        done
        dialog --title "Auto-fix Complete" --msgbox "$fixes_text" 12 60
    else
        dialog --title "Auto-fix Complete" --msgbox "No issues were found that could be automatically fixed.\n\nThe system appears to be healthy." 8 60
    fi
    
    health_check_menu
}

# --- Backup Menu ---
backup_menu() {
    local choice
    choice=$(dialog --clear --title "Backup & Restore" \
        --menu "Choose a backup option:" $DIALOG_HEIGHT $DIALOG_WIDTH 6 \
        "1" "💾 Create Full Stack Backup" \
        "2" "📥 Restore from Backup" \
        "3" "📋 List Available Backups" \
        "4" "🗑️  Delete Old Backups" \
        "5" "⚙️  Backup Configuration" \
        "0" "⬅️  Back to Main Menu" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) create_stack_backup ;;
        2) restore_stack_backup ;;
        3) list_available_backups ;;
        4) delete_old_backups ;;
        5) backup_configuration ;;
        0) show_main_menu ;;
        *) backup_menu ;;
    esac
}

create_stack_backup() {
    local backup_name="n8n-stack-backup-$(date +%Y%m%d-%H%M%S)"
    
    dialog --title "Creating Backup" --infobox "Creating stack backup: $backup_name\nThis may take several minutes..." 6 60
    
    if [ -f "${SETUP_DIR}/manage-stack.sh" ]; then
        cd "${SETUP_DIR}"
        if bash manage-stack.sh backup >/dev/null 2>&1; then
            dialog --title "Backup Complete" --msgbox "Stack backup created successfully!\n\nBackup location: ${SETUP_DIR}/" 8 60
        else
            dialog --title "Backup Failed" --msgbox "Failed to create stack backup.\nCheck disk space and permissions." 7 50
        fi
    else
        dialog --title "Error" --msgbox "Stack management script not found.\nCannot create automated backup." 7 50
    fi
    
    backup_menu
}

restore_stack_backup() {
    # List available backup files
    local backup_files=()
    if [ -d "${SETUP_DIR}" ]; then
        while IFS= read -r -d '' file; do
            backup_files+=("$(basename "$file")" "$(date -r "$file" '+%Y-%m-%d %H:%M')")
        done < <(find "${SETUP_DIR}" -name "*backup*.tar.gz" -print0 2>/dev/null)
    fi
    
    if [ ${#backup_files[@]} -eq 0 ]; then
        dialog --title "No Backups Found" --msgbox "No backup files were found in the setup directory.\n\nCreate a backup first or specify a custom backup file location." 8 60
        backup_menu
        return
    fi
    
    local selected_backup
    selected_backup=$(dialog --clear --title "Select Backup to Restore" \
        --menu "Choose a backup file to restore:" 15 70 8 \
        "${backup_files[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$selected_backup" ]; then
        dialog --title "Restore Backup" \
            --yesno "⚠️  WARNING: This will restore from backup!\n\nThis will:\n• Stop all current services\n• Restore configuration and data\n• Restart services\n\nBackup: $selected_backup\n\nContinue?" 12 60
        
        if [ $? -eq 0 ]; then
            dialog --title "Restoring..." --infobox "Restoring from backup: $selected_backup\nThis may take several minutes..." 6 60
            
            if [ -f "${SETUP_DIR}/manage-stack.sh" ]; then
                cd "${SETUP_DIR}"
                if bash manage-stack.sh restore "$selected_backup" >/dev/null 2>&1; then
                    dialog --title "Restore Complete" --msgbox "Stack restored successfully from:\n$selected_backup\n\nAll services should be running with restored data." 8 70
                else
                    dialog --title "Restore Failed" --msgbox "Failed to restore from backup.\nCheck logs for details." 7 50
                fi
            fi
        fi
    fi
    
    backup_menu
}

list_available_backups() {
    local backup_list=""
    
    if [ -d "${SETUP_DIR}" ]; then
        local count=0
        while IFS= read -r -d '' file; do
            local size=$(du -h "$file" | cut -f1)
            local date=$(date -r "$file" '+%Y-%m-%d %H:%M:%S')
            backup_list+="$(basename "$file")\n  Size: $size  Date: $date\n\n"
            count=$((count + 1))
        done < <(find "${SETUP_DIR}" -name "*backup*.tar.gz" -print0 2>/dev/null)
        
        if [ $count -eq 0 ]; then
            backup_list="No backup files found."
        else
            backup_list="Found $count backup file(s):\n\n$backup_list"
        fi
    else
        backup_list="Setup directory not found."
    fi
    
    dialog --title "Available Backups" --msgbox "$backup_list" 16 80
    backup_menu
}

delete_old_backups() {
    local days
    days=$(dialog --title "Delete Old Backups" \
        --inputbox "Delete backups older than how many days?\n\n(Enter number of days, e.g., 30)" 10 50 "30" \
        3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$days" ] && [[ "$days" =~ ^[0-9]+$ ]]; then
        dialog --title "Deleting Old Backups" --infobox "Deleting backups older than $days days..." 5 50
        
        local deleted_count=0
        if [ -d "${SETUP_DIR}" ]; then
            while IFS= read -r -d '' file; do
                rm -f "$file"
                deleted_count=$((deleted_count + 1))
            done < <(find "${SETUP_DIR}" -name "*backup*.tar.gz" -mtime +$days -print0 2>/dev/null)
        fi
        
        dialog --title "Cleanup Complete" --msgbox "Deleted $deleted_count backup file(s) older than $days days." 7 50
    fi
    
    backup_menu
}

backup_configuration() {
    dialog --title "Backup Configuration" --msgbox "Backup configuration options:\n\n• Backups are stored in: ${SETUP_DIR}/\n• Includes: Configuration files, Docker volumes\n• Excludes: Container images (re-downloaded)\n• Compression: gzip\n• Naming: n8n-stack-backup-YYYYMMDD-HHMMSS.tar.gz\n\n💡 Tip: Regular backups help protect against data loss." 14 70
    backup_menu
}

# --- View Logs Menu ---
view_logs_menu() {
    local log_options=()
    
    # Add running services to log options
    for service in "${!SERVICES[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
            log_options+=("$service" "View $service logs")
        fi
    done
    
    log_options+=("all" "📋 View All Service Logs")
    log_options+=("system" "🖥️  System Docker Logs")
    log_options+=("back" "⬅️  Back to Health Check")
    
    if [ ${#log_options[@]} -eq 6 ]; then  # Only back, all, system options
        dialog --title "No Services Running" --msgbox "No services are currently running.\nStart some services first to view their logs." 7 50
        health_check_menu
        return
    fi
    
    local choice
    choice=$(dialog --clear --title "View Service Logs" \
        --menu "Select logs to view:" 15 60 8 \
        "${log_options[@]}" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        all) show_all_logs ;;
        system) show_system_logs ;;
        back) health_check_menu ;;
        *) 
            if [[ " ${!SERVICES[@]} " =~ " $choice " ]]; then
                show_service_logs "$choice"
            else
                view_logs_menu
            fi
            ;;
    esac
}

show_all_logs() {
    local all_logs=""
    
    for service in "${!SERVICES[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${service}$"; then
            all_logs+="\n=== $service LOGS ===\n"
            all_logs+="$(docker logs "$service" --tail 20 2>&1 || echo "Unable to get logs")\n"
        fi
    done
    
    if [ -n "$all_logs" ]; then
        echo "$all_logs" > "/tmp/all_service_logs.txt"
        dialog --title "All Service Logs" --textbox "/tmp/all_service_logs.txt" 22 90
        rm -f "/tmp/all_service_logs.txt"
    else
        dialog --title "No Logs" --msgbox "No running services found." 6 40
    fi
    
    view_logs_menu
}

show_system_logs() {
    local system_logs=""
    system_logs+="=== Docker Service Status ===\n"
    system_logs+="$(systemctl status docker --no-pager -l || echo "Unable to get Docker status")\n\n"
    system_logs+="=== Recent Docker Events ===\n"
    system_logs+="$(docker events --since 1h --until now 2>/dev/null | tail -10 || echo "No recent events")\n"
    
    echo "$system_logs" > "/tmp/system_logs.txt"
    dialog --title "System Docker Logs" --textbox "/tmp/system_logs.txt" 20 80
    rm -f "/tmp/system_logs.txt"
    
    view_logs_menu
}

# --- System Information Menu (Enhanced) ---
system_info_menu() {
    local system_info=""
    
    # System resources
    local memory_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    local disk_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    local cpu_cores=$(nproc)
    local load_avg=$(uptime | awk '{print $(NF-2), $(NF-1), $NF}')
    
    system_info+="=== System Resources ===\n"
    system_info+="• RAM: ${memory_gb}GB total\n"
    system_info+="• Disk Space: ${disk_gb}GB available\n"
    system_info+="• CPU Cores: ${cpu_cores}\n"
    system_info+="• Load Average: ${load_avg}\n\n"
    
    # Docker information
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        local compose_version=$(docker compose version --short 2>/dev/null || echo "Not available")
        
        system_info+="=== Docker Information ===\n"
        system_info+="• Docker Version: ${docker_version}\n"
        system_info+="• Compose Version: ${compose_version}\n"
        
        local running_containers=$(docker ps -q 2>/dev/null | wc -l)
        local total_containers=$(docker ps -aq 2>/dev/null | wc -l)
        system_info+="• Containers: ${running_containers}/${total_containers} running\n"
        
        local images_count=$(docker images -q 2>/dev/null | wc -l)
        system_info+="• Images: ${images_count}\n"
        
        local volumes_count=$(docker volume ls -q 2>/dev/null | wc -l)
        system_info+="• Volumes: ${volumes_count}\n\n"
    fi
    
    # Network information
    local public_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "Unable to detect")
    system_info+="=== Network Information ===\n"
    system_info+="• Public IP: ${public_ip}\n"
    
    if docker network ls | grep -q "n8n_network"; then
        system_info+="• n8n Network: ✓ Available\n"
    else
        system_info+="• n8n Network: ❌ Missing\n"
    fi
    
    # Installation information
    if [ -d "$SETUP_DIR" ]; then
        system_info+="\n=== Installation Information ===\n"
        system_info+="• Setup Directory: $SETUP_DIR\n"
        
        if [ -f "$SETUP_DIR/.env" ]; then
            system_info+="• Environment Config: ✓ Found\n"
        else
            system_info+="• Environment Config: ❌ Missing\n"
        fi
        
        if [ -f "$SETUP_DIR/manage-stack.sh" ]; then
            system_info+="• Stack Management: ✓ Available\n"
        else
            system_info+="• Stack Management: ❌ Not Available\n"
        fi
        
        # Count modular compose files
        local compose_count=$(find "$SETUP_DIR" -name "docker-compose.*.yml" 2>/dev/null | wc -l)
        system_info+="• Modular Services: ${compose_count} configured\n"
    else
        system_info+="\n=== Installation Information ===\n"
        system_info+="• Status: No installation found\n"
    fi
    
    # Service status summary
    system_info+="\n=== Service Status Summary ===\n"
    update_all_service_status
    local running=0
    local total=0
    for service in "${!SERVICES[@]}"; do
        local status="${SERVICE_STATUS[$service]:-⚪ Unknown}"
        total=$((total + 1))
        if [[ "$status" == *"🟢 Running"* ]]; then
            running=$((running + 1))
        fi
        system_info+="• $service: $status\n"
    done
    system_info+="\n• Summary: ${running}/${total} services running\n"
    
    dialog --title "System Information" --msgbox "$system_info" 24 80
    show_main_menu
}

# --- Cleanup Menu (Enhanced) ---
cleanup_menu() {
    local choice
    choice=$(dialog --clear --title "Cleanup & Uninstall" \
        --menu "⚠️  WARNING: Cleanup operations are permanent!\n\nChoose a cleanup option:" 15 70 7 \
        "1" "🧹 Clean Docker Images & Cache" \
        "2" "🗑️  Remove Individual Service" \
        "3" "💣 Remove All Services (Keep Data)" \
        "4" "💥 Complete Removal (All Data Lost)" \
        "5" "🔄 Reset to Fresh State" \
        "6" "📋 Show What Will Be Removed" \
        "0" "⬅️  Back to Main Menu" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        1) clean_docker_cache ;;
        2) remove_individual_service_menu ;;
        3) remove_all_services_keep_data ;;
        4) complete_removal ;;
        5) reset_to_fresh_state ;;
        6) show_removal_preview ;;
        0) show_main_menu ;;
        *) cleanup_menu ;;
    esac
}

clean_docker_cache() {
    dialog --title "Clean Docker Cache" \
        --yesno "This will remove:\n\n• Unused Docker images\n• Build cache\n• Stopped containers (non-stack)\n• Unused networks\n• Unused volumes (non-stack)\n\nStack data and running containers will be preserved.\nContinue?" 12 60
    
    if [ $? -eq 0 ]; then
        dialog --title "Cleaning..." --infobox "Cleaning Docker cache and unused resources...\nThis may take a few minutes." 6 60
        
        # Clean up Docker resources
        local cleaned=""
        cleaned+="$(docker system prune -f 2>/dev/null || echo "System prune completed")\n"
        cleaned+="$(docker image prune -a -f 2>/dev/null || echo "Image prune completed")\n"
        cleaned+="$(docker volume prune -f 2>/dev/null || echo "Volume prune completed")\n"
        
        dialog --title "Cleanup Complete" --msgbox "Docker cleanup completed:\n\n$cleaned" 12 70
    fi
    
    cleanup_menu
}

remove_individual_service_menu() {
    local service_options=()
    
    for service in "${!SERVICES[@]}"; do
        local status="${SERVICE_STATUS[$service]:-⚪ Unknown}"
        if [[ "$status" != *"⚪ Not Installed"* ]]; then
            service_options+=("$service" "$status")
        fi
    done
    
    if [ ${#service_options[@]} -eq 0 ]; then
        dialog --title "No Services to Remove" --msgbox "No installed services found to remove." 6 50
        cleanup_menu
        return
    fi
    
    service_options+=("back" "⬅️  Back to Cleanup Menu")
    
    local choice
    choice=$(dialog --clear --title "Remove Individual Service" \
        --menu "Select a service to remove:" 15 60 8 \
        "${service_options[@]}" \
        3>&1 1>&2 2>&3)
    
    case $choice in
        back) cleanup_menu ;;
        *) confirm_individual_service_removal "$choice" ;;
    esac
}

confirm_individual_service_removal() {
    local service="$1"
    
    dialog --title "Remove $service" \
        --yesno "⚠️  Remove $service?\n\nThis will:\n• Stop the $service container\n• Remove the $service container\n• Keep data volumes (safe)\n• Keep configuration files\n\nData can be recovered by reinstalling.\nContinue?" 12 60
    
    if [ $? -eq 0 ]; then
        dialog --title "Removing..." --infobox "Removing $service...\nPlease wait." 5 40
        
        # Use the modular cleanup script if available
        local script_path="${MODULAR_DIR}/scripts/install-${service}.sh"
        if [ -f "$script_path" ]; then
            if bash "$script_path" --cleanup >/dev/null 2>&1; then
                dialog --title "Success" --msgbox "$service removed successfully!\n\nData volumes were preserved." 7 50
            else
                dialog --title "Error" --msgbox "Failed to remove $service cleanly.\nSome manual cleanup may be required." 8 50
            fi
        else
            # Fallback manual removal
            docker stop "$service" >/dev/null 2>&1 || true
            docker rm "$service" >/dev/null 2>&1 || true
            dialog --title "Manual Removal" --msgbox "$service container removed.\n\nConfiguration and volumes remain." 7 50
        fi
    fi
    
    cleanup_menu
}

remove_all_services_keep_data() {
    dialog --title "Remove All Services" \
        --yesno "⚠️  Remove all services but keep data?\n\nThis will:\n• Stop all containers\n• Remove all containers\n• Keep all data volumes (SAFE)\n• Keep configuration files\n• Keep Docker network\n\nAll data can be recovered by reinstalling.\nContinue?" 14 60
    
    if [ $? -eq 0 ]; then
        dialog --title "Removing Services..." --infobox "Removing all services...\nKeeping data safe." 6 50
        
        # Stop and remove all service containers
        for service in "${!SERVICES[@]}"; do
            docker stop "$service" >/dev/null 2>&1 || true
            docker rm "$service" >/dev/null 2>&1 || true
        done
        
        # Remove compose files but keep .env
        if [ -d "$SETUP_DIR" ]; then
            find "$SETUP_DIR" -name "docker-compose.*.yml" -delete 2>/dev/null || true
            rm -f "$SETUP_DIR/manage-stack.sh" 2>/dev/null || true
        fi
        
        dialog --title "Removal Complete" --msgbox "All services removed successfully!\n\n✅ Data volumes preserved\n✅ Environment configuration kept\n✅ Docker network maintained\n\nReinstall services anytime to recover data." 10 60
    fi
    
    cleanup_menu
}

complete_removal() {
    dialog --title "⚠️  DANGER ZONE" \
        --yesno "💥 COMPLETE REMOVAL - ALL DATA WILL BE LOST!\n\nThis will PERMANENTLY remove:\n• All containers\n• All data volumes (PERMANENT DATA LOSS)\n• All configuration files\n• Docker network\n• Installation directory\n\n🚨 THIS CANNOT BE UNDONE!\n\nType 'DELETE EVERYTHING' to confirm:" 16 70
    
    if [ $? -eq 0 ]; then
        local confirmation
        confirmation=$(dialog --title "Final Confirmation" \
            --inputbox "Type 'DELETE EVERYTHING' to confirm complete removal:" 8 60 \
            3>&1 1>&2 2>&3)
        
        if [ "$confirmation" = "DELETE EVERYTHING" ]; then
            dialog --title "Complete Removal" --infobox "Performing complete removal...\nThis will take a moment." 6 50
            
            perform_complete_cleanup
            
            dialog --title "Complete Removal Finished" --msgbox "Complete removal finished.\n\nAll n8n stack components and data have been permanently removed.\n\nThe system is now clean and ready for a fresh installation." 10 60
            exit 0
        else
            dialog --title "Removal Cancelled" --msgbox "Complete removal cancelled.\nNothing was removed." 6 50
        fi
    fi
    
    cleanup_menu
}

perform_complete_cleanup() {
    # Stop and remove all containers
    for service in "${!SERVICES[@]}"; do
        docker stop "$service" >/dev/null 2>&1 || true
        docker rm "$service" >/dev/null 2>&1 || true
    done
    
    # Remove all volumes (DATA LOSS)
    local volumes=("n8n_data" "caddy_data" "caddy_config" "qdrant_data" "portainer_data")
    for volume in "${volumes[@]}"; do
        docker volume rm "$volume" >/dev/null 2>&1 || true
    done
    
    # Remove network
    docker network rm n8n_network >/dev/null 2>&1 || true
    
    # Remove installation directory
    rm -rf "$SETUP_DIR" >/dev/null 2>&1 || true
    
    # Clean Docker resources
    docker system prune -a -f --volumes >/dev/null 2>&1 || true
}

reset_to_fresh_state() {
    dialog --title "Reset to Fresh State" \
        --yesno "Reset the stack to fresh state?\n\nThis will:\n• Stop all services\n• Remove containers\n• Keep data volumes (SAFE)\n• Reset configuration to defaults\n• Recreate Docker network\n\nData is preserved but configuration is reset.\nContinue?" 14 60
    
    if [ $? -eq 0 ]; then
        dialog --title "Resetting..." --infobox "Resetting stack to fresh state...\nKeeping your data safe." 6 50
        
        # Stop and remove containers
        for service in "${!SERVICES[@]}"; do
            docker stop "$service" >/dev/null 2>&1 || true
            docker rm "$service" >/dev/null 2>&1 || true
        done
        
        # Reset network
        docker network rm n8n_network >/dev/null 2>&1 || true
        docker network create n8n_network >/dev/null 2>&1 || true
        
        # Reset configuration but keep .env
        if [ -d "$SETUP_DIR" ]; then
            find "$SETUP_DIR" -name "docker-compose.*.yml" -delete 2>/dev/null || true
            rm -f "$SETUP_DIR/manage-stack.sh" 2>/dev/null || true
            rm -f "$SETUP_DIR/Caddyfile" 2>/dev/null || true
            rm -f "$SETUP_DIR/qdrant-config.yaml" 2>/dev/null || true
        fi
        
        dialog --title "Reset Complete" --msgbox "Stack reset to fresh state!\n\n✅ Data volumes preserved\n✅ Network recreated\n✅ Configuration reset\n\nYou can now reinstall services with fresh configuration." 10 60
    fi
    
    cleanup_menu
}

show_removal_preview() {
    local preview=""
    
    preview+="=== CURRENT INSTALLATION ===\n\n"
    
    # Show installed services
    update_all_service_status
    local installed_services=()
    for service in "${!SERVICES[@]}"; do
        local status="${SERVICE_STATUS[$service]:-⚪ Unknown}"
        if [[ "$status" != *"⚪ Not Installed"* ]]; then
            installed_services+=("$service")
            preview+="🔹 $service: $status\n"
        fi
    done
    
    if [ ${#installed_services[@]} -eq 0 ]; then
        preview+="No services currently installed.\n"
    fi
    
    # Show volumes
    preview+="\n=== DATA VOLUMES ===\n"
    local volumes=("n8n_data" "caddy_data" "caddy_config" "qdrant_data" "portainer_data")
    local found_volumes=()
    for volume in "${volumes[@]}"; do
        if docker volume ls | grep -q "$volume"; then
            found_volumes+=("$volume")
            local size=$(docker run --rm -v "$volume":/data alpine du -sh /data 2>/dev/null | cut -f1 || echo "Unknown")
            preview+="💾 $volume (Size: $size)\n"
        fi
    done
    
    if [ ${#found_volumes[@]} -eq 0 ]; then
        preview+="No data volumes found.\n"
    fi
    
    # Show configuration
    preview+="\n=== CONFIGURATION ===\n"
    if [ -d "$SETUP_DIR" ]; then
        preview+="📁 Setup Directory: $SETUP_DIR\n"
        if [ -f "$SETUP_DIR/.env" ]; then
            preview+="⚙️  Environment Config: Present\n"
        fi
        local compose_count=$(find "$SETUP_DIR" -name "docker-compose.*.yml" 2>/dev/null | wc -l)
        preview+="🐳 Compose Files: $compose_count\n"
    else
        preview+="No configuration directory found.\n"
    fi
    
    # Show cleanup options summary
    preview+="\n=== CLEANUP OPTIONS SUMMARY ===\n\n"
    preview+="1. Clean Cache: Removes unused Docker resources only\n"
    preview+="2. Remove Service: Remove specific service, keep data\n"
    preview+="3. Remove All (Keep Data): Remove services, preserve volumes\n"
    preview+="4. Complete Removal: ⚠️  PERMANENT DATA LOSS\n"
    preview+="5. Reset Fresh: Reset config, keep data\n"
    
    dialog --title "Removal Preview" --msgbox "$preview" 24 80
    cleanup_menu
}

# --- Utility Functions (Enhanced) ---
detect_existing_installation_silent() {
    # Check for containers
    for service in "${!SERVICES[@]}"; do
        if docker ps -a --format "table {{.Names}}" 2>/dev/null | grep -q "^${service}$"; then
            return 0
        fi
    done
    
    # Check for volumes
    local volumes=("n8n_data" "caddy_data" "qdrant_data" "portainer_data")
    for volume in "${volumes[@]}"; do
        if docker volume ls 2>/dev/null | grep -q "$volume"; then
            return 0
        fi
    done
    
    # Check for setup directory
    if [ -d "$SETUP_DIR" ]; then
        return 0
    fi
    
    return 1
}

perform_full_cleanup_silent() {
    # Use the modular cleanup approach
    for service in "${!SERVICES[@]}"; do
        local script_path="${MODULAR_DIR}/scripts/install-${service}.sh"
        if [ -f "$script_path" ]; then
            bash "$script_path" --cleanup >/dev/null 2>&1 || true
        fi
    done
    
    # Additional cleanup
    docker network rm n8n_network >/dev/null 2>&1 || true
    rm -rf "$SETUP_DIR" >/dev/null 2>&1 || true
}

exit_application() {
    clear
    echo "Thank you for using n8n Stack Manager!"
    echo
    echo "🎯 Quick Reference:"
    echo "• Fresh install: sudo $0"
    echo "• Stack management: ${SETUP_DIR}/manage-stack.sh"
    echo "• Individual services: Use this UI"
    echo
    echo "📚 Documentation: https://docs.n8n.io/"
    echo "🏠 Community: https://community.n8n.io/"
    echo
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
    
    # Check if modular directory exists
    if [ ! -d "${MODULAR_DIR}/scripts" ]; then
        dialog --title "Missing Modular Scripts" --msgbox "The modular installation scripts directory was not found.\n\nExpected location: ${MODULAR_DIR}/scripts/\n\nPlease ensure this UI script is in the same directory as the modular setup." 10 70
        exit 1
    fi
    
    # Start main menu loop
    while true; do
        show_main_menu
    done
}

# Trap to clean up dialog on exit
trap 'clear' EXIT

# Run main function
main "$@"