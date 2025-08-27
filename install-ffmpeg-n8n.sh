#!/bin/bash

# ==============================================================================
# FFmpeg Installation Script for n8n Docker Container (Ubuntu-based)
# This script installs FFmpeg in an existing n8n container running on Ubuntu
# Uses modern 'apt' commands instead of 'apt-get'
# ==============================================================================

set -euo pipefail

# --- Configuration ---
readonly SCRIPT_NAME="n8n FFmpeg Installer"
readonly SCRIPT_VERSION="1.0.0"
readonly N8N_CONTAINER_NAME="${N8N_CONTAINER_NAME:-n8n}"

# --- Color Functions ---
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1" >&2; exit 1; }

# --- Helper Functions ---
check_container_exists() {
    if ! docker ps -a --format "table {{.Names}}" | grep -q "^${N8N_CONTAINER_NAME}$"; then
        error "Container '${N8N_CONTAINER_NAME}' not found. Please ensure n8n is running."
    fi
}

check_container_running() {
    if ! docker ps --format "table {{.Names}}" | grep -q "^${N8N_CONTAINER_NAME}$"; then
        error "Container '${N8N_CONTAINER_NAME}' is not running. Please start n8n first."
    fi
}

check_docker_available() {
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed or not in PATH"
    fi
    
    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running or you don't have permission to access it"
    fi
}

install_ffmpeg() {
    info "Installing FFmpeg in n8n container (Ubuntu-based setup)..."
    
    # Update package lists using apt (modern Ubuntu command)
    info "Updating package lists..."
    docker exec "$N8N_CONTAINER_NAME" sh -c "apt update" || {
        error "Failed to update package lists in container"
    }
    
    # Install FFmpeg using apt
    info "Installing FFmpeg package..."
    docker exec "$N8N_CONTAINER_NAME" sh -c "apt install -y ffmpeg" || {
        error "Failed to install FFmpeg in container"
    }
    
    # Clean up package cache to reduce container size
    info "Cleaning up package cache..."
    docker exec "$N8N_CONTAINER_NAME" sh -c "apt clean && rm -rf /var/lib/apt/lists/*" || {
        warning "Failed to clean up package cache (not critical)"
    }
}

verify_ffmpeg_installation() {
    info "Verifying FFmpeg installation..."
    
    # Check if FFmpeg is available
    if docker exec "$N8N_CONTAINER_NAME" sh -c "command -v ffmpeg >/dev/null 2>&1"; then
        local ffmpeg_version
        ffmpeg_version=$(docker exec "$N8N_CONTAINER_NAME" ffmpeg -version 2>/dev/null | head -n 1 | cut -d' ' -f3 || echo "unknown")
        success "FFmpeg is installed successfully! Version: $ffmpeg_version"
        return 0
    else
        error "FFmpeg installation verification failed"
    fi
}

show_usage_examples() {
    echo
    info "🎬 FFmpeg is now available in your n8n container!"
    echo
    echo "Example n8n workflow uses:"
    echo "1. Convert video formats:"
    echo "   Command: ffmpeg -i input.mp4 output.avi"
    echo
    echo "2. Extract audio from video:"
    echo "   Command: ffmpeg -i input.mp4 -vn -acodec copy output.aac"
    echo
    echo "3. Resize video:"
    echo "   Command: ffmpeg -i input.mp4 -vf scale=1280:720 output.mp4"
    echo
    echo "4. Convert audio formats:"
    echo "   Command: ffmpeg -i input.wav output.mp3"
    echo
    echo "5. Create video thumbnail:"
    echo "   Command: ffmpeg -i input.mp4 -ss 00:00:01.000 -vframes 1 thumbnail.png"
    echo
    echo "6. Test FFmpeg in container:"
    echo "   Command: docker exec $N8N_CONTAINER_NAME ffmpeg -version"
    echo
    warning "💡 Remember to restart n8n workflows that use FFmpeg after installation"
    info "💡 This script is designed for Ubuntu-based n8n containers using 'apt' package manager"
    echo
}

show_container_info() {
    info "📋 Container Information:"
    echo "   Container Name: $N8N_CONTAINER_NAME"
    echo "   Container Status: $(docker inspect --format='{{.State.Status}}' "$N8N_CONTAINER_NAME" 2>/dev/null || echo 'unknown')"
    echo "   Container Image: $(docker inspect --format='{{.Config.Image}}' "$N8N_CONTAINER_NAME" 2>/dev/null || echo 'unknown')"
    echo
}

# --- Main Function ---
main() {
    echo "🎬======================================================"
    echo "   $SCRIPT_NAME v$SCRIPT_VERSION"
    echo "======================================================"
    echo

    # Perform checks
    info "🔍 Performing system checks..."
    check_docker_available
    check_container_exists
    check_container_running
    
    show_container_info
    
    # Confirm installation
    if [ -t 0 ]; then
        echo -n "Install FFmpeg in n8n container '$N8N_CONTAINER_NAME'? [y/N]: "
        read -r confirm
        if [[ ! "${confirm,,}" =~ ^(y|yes)$ ]]; then
            info "Installation cancelled."
            exit 0
        fi
    fi
    
    # Install FFmpeg
    install_ffmpeg
    
    # Verify installation
    verify_ffmpeg_installation
    
    # Show usage examples
    show_usage_examples
    
    success "🎉 FFmpeg installation completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    -h|--help|help)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Install FFmpeg in n8n Docker container (Ubuntu-based setup)"
        echo
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  --container    Specify container name (default: n8n)"
        echo
        echo "Environment Variables:"
        echo "  N8N_CONTAINER_NAME    n8n container name (default: n8n)"
        echo
        echo "Examples:"
        echo "  $0                              # Install in default 'n8n' container"
        echo "  N8N_CONTAINER_NAME=my-n8n $0   # Install in 'my-n8n' container"
        echo "  $0 --container my-n8n          # Install in 'my-n8n' container"
        exit 0
        ;;
    --container)
        if [ -z "${2:-}" ]; then
            error "Container name required after --container"
        fi
        N8N_CONTAINER_NAME="$2"
        ;;
    "")
        # No arguments, proceed with main function
        ;;
    *)
        error "Unknown option: $1. Use --help for usage information."
        ;;
esac

# Run main function
main "$@"